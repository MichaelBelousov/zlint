const std = @import("std");
const _rule = @import("rule.zig");
const Source = @import("source.zig").Source;

const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const assert = std.debug.assert;
const fs = std.fs;
const print = std.debug.print;

const Rule = _rule.Rule;
const NodeWrapper = _rule.NodeWrapper;
const string = @import("str.zig").string;

// rules
const NoUndefined = @import("rules/no_undefined.zig").NoUndefined;


pub const LinterContext = struct {
    ast: *const Ast,
    pub fn new(ast: *const Ast) LinterContext {
        return LinterContext{ .ast = ast };
    }
};

pub const Linter = struct {
    rules: std.ArrayList(Rule),

    pub fn init(gpa: Allocator) Linter {
        var linter = Linter{ .rules = std.ArrayList(Rule).init(gpa) };
        var no_undef = NoUndefined{};
        linter.rules.append(no_undef.rule()) catch unreachable;
        return linter;
    }

    pub fn deinit(self: *Linter) void {
        self.rules.deinit();
    }

    pub fn runOnSource(self: *Linter, source: *Source) !void {
        const ctx = LinterContext.new(&try source.parse());
        print("running linter on source with {d} rules\n", .{self.rules.items.len});

        var i: usize = 0;
        while (i < ctx.ast.nodes.len) {
            assert(i < std.math.maxInt(u32));
            const node = ctx.ast.nodes.get(i);
            const wrapper: NodeWrapper = .{ .node = &node, .idx = @intCast(i) };
            for (self.rules.items) |rule| {
                print("running rule: {s}\n", .{rule.name});
                rule.runOnNode(wrapper, ctx) catch |e| {
                    return e;
                };
            }
            i += 1;
        }
    }
};
