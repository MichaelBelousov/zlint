const std = @import("std");
const Ast = std.zig.Ast;
const LinterContext = @import("../lint.zig").Context;
const Rule = @import("../rule.zig").Rule;
const NodeWrapper = @import("../rule.zig").NodeWrapper;

const print = std.debug.print;

pub const NoUndefined = struct {
    pub const Name = "NoUndefined";

    pub fn runOnNode(_: *const NoUndefined, wrapper: NodeWrapper, ctx: LinterContext) void {
        const node = wrapper.node;
        const ast = ctx.ast;

        if (node.tag != .identifier) return;
        const name = ast.tokenSlice(node.main_token);
        print("found identifier: {s}\n", .{name});
        if (std.mem.eql(u8, name, "undefined")) {
            ctx.diagnostic("Do not use undefined.", node.loc);
        }
    }

    pub fn rule(self: *NoUndefined) Rule {
        // const r: *anyopaque = self;
        return Rule.init(self);
    }
};
