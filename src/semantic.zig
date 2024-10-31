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
//! an entire linked binary or library; rather it refers to a single parsed
//! file.

pub const Builder = struct {
    _gpa: Allocator,
    _arena: ArenaAllocator,
    _curr_scope_id: Semantic.Scope.Id = 0,
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
        const ast = try builder.parse(builder._arena.allocator(), source, .zig);
        builder._semantic = Semantic{
            .ast = ast,
            ._arena = builder._arena,
            ._gpa = gpa,
        };
        errdefer builder._semantic.deinit();

        // initialize root scope
        try builder.enterRootScope();
        builder.assertRootScope(); // sanity check

        // Zig guarantees that the root node ID is 0. We should be careful- they may decide to change this contract.
        for (builder._semantic.ast.rootDecls()) |node| {
            builder.visitNode(node);
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

    fn parse(self: *Builder, source: stringSlice) !Ast {
        const ast = try Ast.parse(self._arena.allocator(), source, .zig);

        // Record parse errors
        if (ast.errors.len != 0) {
            try self._errors.ensureUnusedCapacity(ast.errors.len);
            for (ast.errors) |ast_err| {
                // Not an error. TODO: verify this assumption
                if (ast_err.is_note) continue;
                self.addAstError(ast, ast_err);
            }
        }

        return ast;
    }

    // =========================================================================
    // ================================= VISIT =================================
    // =========================================================================

    fn visitNode(self: *Builder, node: Ast.Node.Index) void {
        const tag: Ast.Node.Tag = self._semantic.ast.nodes.items(.tag)[node.index];
        switch (tag) {
            .root => unreachable, // root node is never referenced.
            .global_var_decl | .local_var_decl | .simple_var_decl | .aligned_var_decl => self.visitVarDecl(node),
            // .@"usingnamespace" => self.visitUsingNamespace(node),
            else => std.debug.panic("unimplemented node tag: {any}", .{tag}),
        }
    }

    fn visitVarDecl(self: *Builder, node: Ast.Node.Index) void {
        const var_decl = self._semantic.ast.fullVarDecl(node) orelse unreachable;
        std.debug.print("{any}", .{var_decl});
    }

    // =========================================================================
    // ======================== SCOPE/SYMBOL MANAGEMENT ========================
    // =========================================================================

    // NOTE: root scope is entered differently to avoid uneccessary parent-null
    // checks. Parent is only ever null for root scopes.

    fn enterRootScope(self: *Builder) !void {
        assert(self._scope_stack.items.len == 0);
        const root_scope = try self._semantic.scopes.addScope(self._gpa, null, .{ .s_top = true });
        assert(root_scope.id == 0);
        // Builder.init() allocates enough space for 8 scopes.
        self._scope_stack.appendAssumeCapacity(root_scope.id);
    }

    fn enterScope(self: *Builder, flags: Semantic.Scope.Flags) void {
        const parent_id = self._scope_stack.getLast(); // panics if stack is empty
        const scope = try self._semantic.scopes.addScope(self._gpa, parent_id, flags);
        self._scope_stack.append(self._gpa, scope.id);
    }

    inline fn assertRootScope(self: *const Builder) void {
        assert(self._scope_stack.items.len == 1);
        assert(self._scope_stack.items[0] == 0);
    }

    // =========================================================================
    // =========================== ERROR MANAGEMENT ============================
    // =========================================================================

    fn addAstError(self: *Builder, ast: *const Ast, ast_err: Ast.Error) !void {
        const alloc = self._errors.allocator;
        var msg = std.ArrayListUnmanaged(u8);
        defer msg.deinit(alloc);
        ast.renderError(ast_err, msg.writer(alloc));

        // TODO: render `ast_err.extra.expected_tag`
        const byte_offset: Ast.ByteOffset = ast.tokens.items(.start)[ast_err.token];
        const loc = ast.tokenLocation(byte_offset, ast_err.token);
        const labels = .{Span{ .start = @intCast(loc.line_start), .end = @intCast(loc.line_end) }};

        return self.addErrorOwnedMessage(msg.toOwnedSlice(alloc), labels, null);
    }

    /// Record an error encountered during parsing or analysis.
    ///
    /// All parameters are borrowed. Errors own their data, so each parameter gets cloned onto the heap.
    fn addError(self: *Builder, message: string, labels: []Span, help: ?string) !void {
        const alloc = self._errors.allocator;
        const heap_message = try alloc.dupeZ(message);
        const heap_labels = try alloc.dupe(labels);
        const heap_help: ?string = if (help == null) null else try alloc.dupeZ(help);
        const err = try Error{ .message = heap_message, .labels = heap_labels, .help = heap_help };
        try self._errors.append(err);
    }

    /// Create and record an error. `message` is an owned slice moved into the new Error.
    fn addErrorOwnedMessage(self: *Builder, message: string, labels: []Span, help: ?string) !void {
        const alloc = self._errors.allocator;
        const heap_labels = try alloc.dupe(labels);
        const heap_help: ?string = if (help == null) null else try alloc.dupeZ(help);
        const err = try Error{ .message = message, .labels = heap_labels, .help = heap_help };
        try self._errors.append(err);
    }

    pub const Result = struct {
        semantic: Semantic,
        errors: std.ArrayList(Error),

        pub fn hasErrors(self: *Result) bool {
            return self.errors.len != 0;
        }

        /// Free the error list, leaving `semantic` untouched.
        pub fn deinitErrors(self: *Result) void {
            for (self.errors.items) |err| {
                err.deinit(self.errors.allocator);
            }
            self.errors.deinit(self.semantic.gpa);
        }
    };
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Ast = std.zig.Ast;
const Type = std.builtin.Type;
const assert = std.debug.assert;

pub const Semantic = @import("./semantic/Semantic.zig");
const Error = @import("./Error.zig");
const Span = @import("./source.zig").Span;

const str = @import("str.zig");
const string = str.string;
const stringSlice = str.stringSlice;
