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
    ///
    /// TODO: Should this be an enum?
    pub const Flags = packed struct {
        /// Top-level "module" scope
        top: bool,
        /// Created by a function declaration.
        function: bool,
    };
};

/// Stores variable scopes created by a zig program.
pub const ScopeTree = struct {
    /// Indexed by scope id.
    scopes: ScopeList,
    /// Mappings from scopes to their descendants.
    children: std.ArrayListUnmanaged(ScopeIdList),
    alloc: Allocator,

    const ScopeList = std.ArrayListUnmanaged(Scope);
    const ScopeIdList = std.ArrayListUnmanaged(Scope.Id);

    pub fn init(alloc: Allocator) ScopeTree {
        return ScopeTree{
            .scopes = .{}, // can I do this?
            .children = .{},
            .alloc = alloc,
        };
    }

    /// Create a new scope and insert it into the scope tree.
    ///
    /// ## Errors
    /// If allocation fails. Usually due to OOM.
    pub fn addScope(self: *ScopeTree, parent: ?Scope.Id, flags: Scope.Flags) !Scope {
        assert(self.scopes.items.len < std.math.maxInt(Scope.Id));
        const id: Scope.Id = @intCast(self.scopes.items.len);

        // initialize the new scope
        const scope = try self.scopes.addOne(self.alloc);
        scope.* = Scope{ .id = id, .parent = parent, .flags = flags };

        // set up it's child list
        {
            const childList = try self.children.addOne(null, self.alloc);
            childList.* = .{};
        }

        // Add it to its parent's list of child scopes
        if (parent != null) {
            assert(parent < self.children.items.len);
            const parentChildren: ScopeIdList = self.children.items[parent];
            const childEl = try parentChildren.addOne(id, self.alloc);
            childEl.* = id;
        }

        return scope;
    }
};
