//! semantic analysis of a zig AST.
//!
//! We are intentionally not using Zig's AIR. That format strips away dead
//! code, which may be in the process of being authored. Instead, we perform
//! our own minimalist semantic analysis of an entire zig program.
//!
//! Additionally, we're avoiding an SoA (struct of arrays) format for now. Zig
//! (and many other parsers/analysis tools) use this to great perf advantage.
//! However, it sucks to work with when writing rules. We opt for simplicity to
//! reduce cognitive load and make contributing rules easier.
//!
//! Throughout this file you'll see mentions of a "program". This does not mean
//! MIKE: this is called a compilation unit in zig I believe (like in C/C++)
//! an entire linked binary or library; rather it refers to a single parsed
//! file.

pub const Builder = struct {
    _gpa: Allocator, // MIKE: I recommend calling this `a` or `alloc`, gpa means "std.heap.GeneralPurposeAllocator" which someone may not want to use
    _arena: ArenaAllocator,
    _curr_scope_id: Semantic.Scope.Id = 0, // MIKE: can you use a const so we know what 0 means? is it the compilation unit/module scope?
    _curr_symbol_id: ?Semantic.Symbol.Id = null,
    _scope_stack: std.ArrayListUnmanaged(Semantic.Scope.Id),
    /// SAFETY: initialized after parsing. Same safety rationale as _root_scope.
    _semantic: Semantic = undefined,
    /// Errors encountered during parsing and analysis.
    ///
    /// Errors in this list are allocated using this list's allocator.
    _errors: std.ArrayList(Error),

    pub fn build(gpa: Allocator, source: stringSlice) !Result {
        var builder = try Builder.init(gpa);
        errdefer builder.deinit();
        // NOTE: ast is moved
        const ast = try builder.parse(source);
        builder._semantic = Semantic{
            .ast = ast,
            ._arena = builder._arena,
            // MIKE: does it need the non arena allocator? It's not handling errors
            ._gpa = gpa,
        };
        errdefer builder._semantic.deinit();

        // initialize root scope
        try builder.enterRootScope();
        builder.assertRootScope(); // sanity check

        // MIKE: nitpick: I would recommend std.posix.getenv("DEBUG") != null instead of always printing this in debug mode
        // MIKE: even better, you can use std.log.debug and then configure the std log options to look for that env var
        // Zig guarantees that the root node ID is 0. We should be careful- they may decide to change this contract.
        if (builtin.mode == .Debug) {
            print("number of nodes: {d}\n", .{builder._semantic.ast.nodes.len});
            var i: usize = 0;
            // MIKE: zig has a while loop continue expression, which honors continue statements
            while (i < builder._semantic.ast.tokens.len) : (i += 1) {
                const tok = builder._semantic.ast.tokens.get(i);
                print("token ({d}): {any}\n", .{ i, tok });
            }
            print("\n", .{});
        }

        for (builder._semantic.ast.rootDecls()) |node| {
            // MIKE: try === catch |e| return e;
            try builder.visitNode(node);
            builder.assertRootScope();
        }

        return .{ .semantic = builder._semantic, .errors = builder._errors };
    }

    fn init(gpa: Allocator) !Builder {
        var scope_stack: std.ArrayListUnmanaged(Semantic.Scope.Id) = .{};
        try scope_stack.ensureUnusedCapacity(gpa, 8);

        return Builder{
            ._gpa = gpa,
            ._arena = ArenaAllocator.init(gpa),
            ._scope_stack = scope_stack,
            ._errors = std.ArrayList(Error).init(gpa),
        };
    }

    pub fn deinit(self: *Builder) void {
        self._scope_stack.deinit(self._gpa);
    }

    fn parse(self: *Builder, source: stringSlice) !Ast {
        const ast = try Ast.parse(self._arena.allocator(), source, .zig);

        // Record parse errors
        try self._errors.ensureUnusedCapacity(ast.errors.len);
        for (ast.errors) |ast_err| {
            // Not an error. TODO: verify this assumption
            if (ast_err.is_note) continue;
            // MIKE: when using inferred error return types, I recommend explicitly switching on the error, so that
            // if the error set is ever changed in the future, the compiler will yell at you for a non-exhaustive switch
            self.addAstError(&ast, ast_err) catch |e| switch (e) {
                error.OutOfMemory => @panic("Out of memory"),
            };
        }

        return ast;
    }

    // =========================================================================
    // ================================= VISIT =================================
    // =========================================================================

    const NULL_NODE: NodeIndex = 0;

    fn visitNode(self: *Builder, node_id: NodeIndex) anyerror!void {
        if (node_id == NULL_NODE) return; // when lhs/rhs are 0 (root node), it means `null`
        const tag: Ast.Node.Tag = self._semantic.ast.nodes.items(.tag)[node_id];
        switch (tag) {
            .root => unreachable, // root node is never referenced.
            .global_var_decl => {
                const decl = self.AST().fullVarDecl(node_id) orelse unreachable;
                self.visitGlobalVarDecl(node_id, decl);
            },
            .container_decl, .container_decl_trailing, .container_decl_two, .container_decl_two_trailing => {
                try self.enterScope(.{ .s_block = true });
                defer self.exitScope();
                return self.visitRecursive(self.getNode(node_id));
            },
            .local_var_decl, .simple_var_decl, .aligned_var_decl => {
                const decl = self.AST().fullVarDecl(node_id) orelse unreachable;
                return self.visitVarDecl(node_id, decl);
            },
            // .@"usingnamespace" => self.visitUsingNamespace(node),
            // else => std.debug.panic("unimplemented node tag: {any}", .{tag}),
            else => return self.visitRecursive(self.getNode(node_id)),
        }
    }

    /// Basic lhs/rhs traversal. This is just a shorthand.
    inline fn visitRecursive(self: *Builder, node: Node) !void {
        try self.visitNode(node.data.lhs);
        try self.visitNode(node.data.rhs);
    }

    fn visitGlobalVarDecl(self: *Builder, node_id: NodeIndex, var_decl: Ast.full.VarDecl) void {
        _ = self;
        _ = node_id;
        _ = var_decl;
        @panic("todo: visitGlobalVarDecl");
    }

    /// Visit a variable declaration. Global declarations are visited
    /// separately, because their lhs/rhs nodes and main token mean different
    /// things.
    fn visitVarDecl(self: *Builder, node_id: NodeIndex, var_decl: Ast.full.VarDecl) !void {
        const node = self.getNode(node_id);
        // main_token points to `var`, `const` keyword. `.identifier` comes immediately afterwards
        const identifier: string = self.getIdentifier(node.main_token + 1);
        const flags = Symbol.Flags{ .s_comptime = var_decl.comptime_token != null };
        const visibility = if (var_decl.visib_token == null) Symbol.Visibility.private else Symbol.Visibility.public;
        _ = try self.declareSymbol(node_id, identifier, visibility, flags);

        // MIKE: use std.log.debug
        if (builtin.mode == .Debug) {
            const main = self.getToken(node.main_token);
            const lhs = self.maybeGetNode(node.data.lhs);
            const rhs = self.maybeGetNode(node.data.rhs);

            std.debug.print("node ({d}): {any}\n", .{ node_id, node });
            std.debug.print("main: {any}\n", .{main});
            std.debug.print("lhs: {any}\n", .{lhs});
            std.debug.print("rhs: {any}\n", .{rhs});
            std.debug.print("{any}\n\n", .{var_decl});
        }

        return self.visitRecursive(node);
    }

    // =========================================================================
    // ======================== SCOPE/SYMBOL MANAGEMENT ========================
    // =========================================================================

    // NOTE: root scope is entered differently to avoid unnecessary parent-null
    // checks. Parent is only ever null for root scopes.

    inline fn enterRootScope(self: *Builder) !void {
        assert(self._scope_stack.items.len == 0);
        const root_scope = try self._semantic.scopes.addScope(self._gpa, null, .{ .s_top = true });
        assert(root_scope.id == 0);
        // Builder.init() allocates enough space for 8 scopes.
        self._scope_stack.appendAssumeCapacity(root_scope.id);
    }

    fn enterScope(self: *Builder, flags: Semantic.Scope.Flags) !void {
        print("entering scope\n", .{});
        const parent_id = self._scope_stack.getLast(); // panics if stack is empty
        const scope = try self._semantic.scopes.addScope(self._gpa, parent_id, flags);
        try self._scope_stack.append(self._gpa, scope.id);
    }

    inline fn exitScope(self: *Builder) void {
        print("exiting scope\n", .{});
        assert(self._scope_stack.items.len > 1); // cannot pop root scope
        _ = self._scope_stack.pop();
    }

    inline fn currentScope(self: *const Builder) Semantic.Scope.Id {
        assert(self._scope_stack.items.len != 0);
        return self._scope_stack.getLast();
    }

    fn assertRootScope(self: *const Builder) void {
        assert(self._scope_stack.items.len == 1);
        assert(self._scope_stack.items[0] == 0);
    }

    /// Declare a symbol in the current scope.
    fn declareSymbol(self: *Builder, declaration_node: Ast.Node.Index, name: string, visibility: Symbol.Visibility, flags: Symbol.Flags) !Symbol.Id {
        const symbol = try self._semantic.symbols.addSymbol(self._gpa, declaration_node, name, self.currentScope(), visibility, flags);
        return symbol.id;
    }

    // =========================================================================
    // ============================ RANDOM GETTERS =============================
    // =========================================================================

    // MIKE: why uppercase?
    inline fn AST(self: *const Builder) *const Ast {
        return &self._semantic.ast;
    }

    /// Get a node by its ID.
    ///
    /// ## Panics
    /// - If attempting to access the root node (which acts as null).
    /// - If `node_id` is out of bounds.
    inline fn getNode(self: *const Builder, node_id: NodeIndex) Node {
        return self.maybeGetNode(node_id) orelse @panic("attempted to access null node");
    }

    /// Get a node by its ID, returning `null` if its the root node (which acts as null).
    ///
    /// ## Panics
    /// - If `node_id` is out of bounds.
    inline fn maybeGetNode(self: *const Builder, node_id: NodeIndex) ?Node {
        if (node_id == 0) return null;
        assert(node_id < self.AST().nodes.len);

        return self.AST().nodes.get(node_id);
    }

    inline fn getToken(self: *const Builder, token_id: TokenIndex) RawToken {
        assert(token_id < self.AST().tokens.len);

        const t = self.AST().tokens.get(token_id);
        return .{
            .tag = t.tag,
            .start = t.start,
        };
    }

    /// Get an identifier name from an `.identifier` token.
    fn getIdentifier(self: *Builder, token_id: Ast.TokenIndex) string {
        const ast = self.AST();

        if (builtin.mode == .Debug) {
            const tag = ast.tokens.items(.tag)[token_id];
            assert(tag == .identifier);
        }

        const slice = ast.tokenSlice(token_id);
        return slice;
    }

    // =========================================================================
    // =========================== ERROR MANAGEMENT ============================
    // =========================================================================

    fn addAstError(self: *Builder, ast: *const Ast, ast_err: Ast.Error) !void {
        const alloc = self._errors.allocator;
        // MIKE: I feel like you could use a fixed stack buffer writer here instead...
        var msg: std.ArrayListUnmanaged(u8) = .{};
        defer msg.deinit(alloc);
        try ast.renderError(ast_err, msg.writer(alloc));

        // TODO: render `ast_err.extra.expected_tag`
        const byte_offset: Ast.ByteOffset = ast.tokens.items(.start)[ast_err.token];
        const loc = ast.tokenLocation(byte_offset, ast_err.token);
        const labels = .{Span{ .start = @intCast(loc.line_start), .end = @intCast(loc.line_end) }};
        _ = labels;

        return self.addErrorOwnedMessage(try msg.toOwnedSlice(alloc), null);
    }

    /// Record an error encountered during parsing or analysis.
    ///
    /// All parameters are borrowed. Errors own their data, so each parameter gets cloned onto the heap.
    fn addError(self: *Builder, message: string, labels: []Span, help: ?string) !void {
        const alloc = self._errors.allocator;
        const heap_message = try alloc.dupeZ(u8, message);
        const heap_labels = try alloc.dupe(Span, labels);
        const heap_help: ?string = if (help == null) null else try alloc.dupeZ(help.?);
        const err = try Error{ .message = heap_message, .labels = heap_labels, .help = heap_help };
        try self._errors.append(err);
    }

    // MIKE: maybe call it addErrorMove?
    /// Create and record an error. `message` is an owned slice moved into the new Error.
    // fn addErrorOwnedMessage(self: *Builder, message: string, labels: []Span, help: ?string) !void {
    fn addErrorOwnedMessage(self: *Builder, message: string, help: ?string) !void {
        const alloc = self._errors.allocator;
        // const heap_labels = try alloc.dupe(labels);
        const heap_help: ?string = if (help == null) null else try alloc.dupeZ(u8, help.?);
        const err = Error{ .message = message, .help = heap_help };
        // const err = try Error{ .message = message, .labels = heap_labels, .help = heap_help };
        try self._errors.append(err);
    }

    pub const Result = struct {
        semantic: Semantic,
        errors: std.ArrayList(Error),

        pub fn hasErrors(self: *Result) bool {
            return self.errors.items.len != 0;
        }

        /// Free the error list, leaving `semantic` untouched.
        pub fn deinitErrors(self: *Result) void {
            const err_alloc = self.errors.allocator;
            // MIKE: use a mutable capture and prefer for loops over slices
            for (self.errors.items) |*err| {
                err.deinit(err_alloc);
            }
            self.errors.deinit();
        }
    };
};

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Type = std.builtin.Type;
const assert = std.debug.assert;
const print = std.debug.print;

pub const Semantic = @import("./semantic/Semantic.zig");
const Scope = Semantic.Scope;
const Symbol = Semantic.Symbol;

const Ast = std.zig.Ast;
const Node = Ast.Node;
const NodeIndex = Ast.Node.Index;
// Struct used in AST tokens SOA is not pub so we hack it in here.
const RawToken = struct {
    tag: std.zig.Token.Tag,
    start: u32,
};
const TokenIndex = Ast.TokenIndex;

const Error = @import("./Error.zig");
const Span = @import("./source.zig").Span;

const str = @import("str.zig");
const string = str.string;
const stringSlice = str.stringSlice;
