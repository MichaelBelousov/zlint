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

const 

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Ast = std.zig.Ast;
const Type = std.builtin.Type;
const assert = std.debug.assert;

const scope = @import("scope.zig");
const symbol = @import("semantic/symbol.zig");
const Semantic = @import("semantic/Semantic.zig");
const Scope = scope.Scope;
const Symbol = symbol.Symbol;
const ScopeTree = scope.ScopeTree;
const SymbolTable = symbol.SymbolTable;

const str = @import("str.zig");
const string = str.string;
const stringSlice = str.stringSlice;
