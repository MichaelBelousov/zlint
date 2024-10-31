/// A declared variable/function/whatever.
///
/// Type: `pub struct Symbol<'a>`
const Symbol = struct {
    /// Identifier name.
    ///
    /// Symbols only borrow their names. These string slices reference data in
    /// source text, which owns the allocation.
    ///
    /// `&'a str`
    name: string,
    /// This symbol's type. Only present if statically determinable, since
    /// analysis doesn't currently do type checking.
    ty: ?Type,
    /// Unique identifier for this symbol.
    id: Id,
    /// Scope this symbol is declared in.
    scope: Scope.Id,
    /// Index of the AST node declaring this symbol.
    ///
    /// Usually a `var`/`const` declaration, function statement, etc.
    decl: Ast.Node.Index,
    visibility: Visibility,

    /// Uniquely identifies a symbol across a source file.
    pub const Id = u32;
    pub const MAX_ID = std.math.maxInt(Id);

    /// Visibility to external code.
    ///
    /// Does not encode convention-based visibility. This reflects the `pub` Zig
    /// keyword.
    ///
    /// TODO: handle exports?
    pub const Visibility = enum {
        public,
        private,
    };
};

/// Stores symbols created and referenced within a Zig program.
///
/// ## Members and Exports
/// - members are "instance properties". Zig doesn't have classes, and doesn't
///   exactly have methods, so this is a bit of a misnomer. Basically, if you
///   create a new variable or constant that is an instantiation of a struct, its
///   struct fields and "methods" are members
///
/// - Exports are symbols directly accessible on the symbol itself. A symbol's
///   exports include private functions, even though accessing them is a compile
///   error.
///
/// ```zig
/// const Foo = struct {
///   bar: i32,                       // member
///   pub const qux = 42,             // export
///   const quux = 42,                // export, not public
///   pub fn baz(self: *Foo) void {}, // member
///   pub fn bang() void {},          // export
/// };
/// ```
const SymbolTable = struct {
    /// Indexed by symbol id.
    ///
    /// Do not write to this list directly.
    symbols: std.ArrayListUnmanaged(Symbol) = .{},
    /// Symbols on "instance objects" (e.g. field properties and instance
    /// methods).
    ///
    /// Do not write to this list directly.
    members: std.ArrayListUnmanaged(SymbolIdList) = .{},
    /// Symbols directly accessible on the symbol itself (e.g. static methods,
    /// constants, enum members).
    ///
    /// Do not write to this list directly.
    exports: std.ArrayListUnmanaged(SymbolIdList) = .{},

    const SymbolIdList = std.ArrayListUnmanaged(Symbol.Id);

    pub fn addSymbol(self: *SymbolTable, alloc: Allocator, name: string, ty: ?Type, scope_id: Scope.Id, visibility: Symbol.Visibility) !Symbol {
        assert(self.symbols.items.len < Symbol.MAX_ID);
        const id: Symbol.Id = @intCast(self.symbols.items.len);
        const symbol: *Symbol = try self.symbols.addOne(alloc);
        symbol.* = Symbol{
            // line break
            .name = name,
            .ty = ty,
            .id = id,
            .scope = scope_id,
            .visibility = visibility,
            .decl = Ast.Node.Index{ .index = 0, .scope = 0 },
        };

        const members: *SymbolIdList = try self.members.addOne(alloc);
        const exports: *SymbolIdList = try self.exports.addOne(alloc);
        members.* = .{};
        exports.* = .{};

        // sanity check
        assert(self.symbols.items.len == self.members.items.len);
        assert(self.symbols.items.len == self.exports.items.len);

        return error.NotImplemented;
    }

    pub fn deinit(self: *SymbolTable, alloc: Allocator) void {
        self.symbols.deinit(alloc);

        for (self.members.items) |members| {
            members.deinit(alloc);
        }
        self.members.deinit(alloc);

        for (self.exports.items) |exports| {
            exports.deinit(alloc);
        }
        self.exports.deinit(alloc);
    }
};

const std = @import("std");

const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const Scope = @import("scope.zig").Scope;
const Type = std.builtin.Type;

const assert = std.debug.assert;
const string = @import("str.zig").string;
