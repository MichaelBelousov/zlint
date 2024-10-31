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

const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const Type = std.builtin.Type;

const string = @import("str.zig").string;
const assert = std.debug.assert;

/// A declared variable/function/whatever.
///
/// `pub struct Symbol<'a>`
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

    /// Uniquely identifies a symbol across a source file.
    pub const Id = u32;
};

const SymbolTable = struct {
    symbols: std.ArrayList(Symbol),
};

pub const Scope = struct {
    /// Unique identifier for this scope.
    id: Id,
    /// Scope hints.
    flags: Flags,
    parent: ?Id,

    /// Uniquely identifies a scope within a source file.
    pub const Id = u32;

    /// Scope flags provide hints about what kind of node is creating the
    /// scope.
    pub const Flags = packed struct {
        /// Top-level "module" scope
        top: bool,
        /// Created by a function declaration.
        function: bool,
    };
};

pub const ScopeTree = struct {
    /// Indexed by scope id.
    scopes: std.ArrayListUnmanaged(Scope),
    /// Mappings from scopes to their descendants.
    children: std.ArrayListUnmanaged(std.ArrayListUnmanaged(Scope.Id)),
    alloc: Allocator,

    pub fn init(alloc: Allocator) ScopeTree {
        return ScopeTree{
            .scopes = .{}, // can I do this?
            .children = .{},
            .alloc = alloc,
        };
    }

    pub fn addScope(self: *ScopeTree, parent: ?Scope.Id, flags: Scope.Flags) Scope.Id {
        const id = self.scopes.items.len;
        assert(id < std.math.maxInt(u32));

        self.scopes.items.append(Scope{ .id = id, .parent = parent, .flags = flags });
        if (parent != null) {
            const parentChildren = self.children.items[parent];
            parentChildren.append(id);
        }
        self.children.items.append(std.ArrayListUnmanaged(Scope.Id).init(self.scopes.items.len));
        return id;
    }
};
