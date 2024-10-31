const std = @import("std");
const source = @import("../source.zig");

const Ast = std.zig.Ast;
const Node = Ast.Node;
const Loc = std.zig.Loc;
const Span = source.Span;
const LinterContext = @import("../lint.zig").Context;
const Rule = @import("../rule.zig").Rule;
const NodeWrapper = @import("../rule.zig").NodeWrapper;

const print = std.debug.print;

pub const NoUndefined = struct {
    pub const Name = "NoUndefined";

    pub fn runOnNode(_: *const NoUndefined, wrapper: NodeWrapper, ctx: *LinterContext) void {
        const node = wrapper.node;
        const ast = ctx.ast();

        if (node.tag != .identifier) return;
        const name = ast.tokenSlice(node.main_token);
        if (!std.mem.eql(u8, name, "undefined")) return;
        // const location = ast.tokenLocation(0, node.main_token);
        const start = wrapper.getMainTokenOffset(ast);
        const len: u32 = @intCast(name.len);
        const span = Span{ .start = start, .end = start + len };
        ctx.diagnostic("Do not use undefined.", span);
    }

    pub fn rule(self: *NoUndefined) Rule {
        // const r: *anyopaque = self;
        return Rule.init(self);
    }
};
