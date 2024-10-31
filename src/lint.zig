const std = @import("std");
const _rule = @import("rule.zig");
const _source = @import("source.zig");

const Source = _source.Source;
const Span = _source.Span;

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

pub const Error = struct {
    // line break
    message: []const u8,
    span: Span,
    rule_name: []const u8,
    source: *const Source,
};

/// Context is only valid over the lifetime of a Source and the min lifetime of all rules
pub const Context = struct {
    /// Borrowed reference to parsed AST
    ast: *const Ast,
    gpa: Allocator,
    /// Errors collected by lint rules
    errors: ErrorList,
    /// this slice is 'static (in data segment) and should never be free'd
    curr_rule_name: string = "",
    source: *const Source,

    const ErrorList = std.ArrayList(Error);

    fn init(gpa: Allocator, ast: *const Ast, source: *const Source) Context {
        return Context{
            // line break
            .ast = ast,
            .gpa = gpa,
            .errors = ErrorList.init(gpa),
            .source = source,
        };
    }

    fn deinit(self: *Context) void {
        self.errors.deinit();
        self.* = undefined;
    }

    pub inline fn updateForRule(self: *Context, rule: *const Rule) void {
        self.curr_rule_name = rule.name;
    }

    pub fn diagnostic(self: *Context, message: []const u8, loc: Span) void {
        // TODO: handle errors better
        self.errors.append(Error{
            // line break
            .message = message,
            .span = loc,
            .rule_name = self.curr_rule_name,
            .source = self.source,
        }) catch @panic("Cannot add new error: Out of memory");
    }
};

pub const Linter = struct {
    rules: std.ArrayList(Rule),
    gpa: Allocator,

    pub fn init(gpa: Allocator) Linter {
        var linter = Linter{ .rules = std.ArrayList(Rule).init(gpa), .gpa = gpa };
        var no_undef = NoUndefined{};
        // TODO: handle OOM
        linter.rules.append(no_undef.rule()) catch @panic("Cannot add new lint rule: Out of memory");
        return linter;
    }

    pub fn deinit(self: *Linter) void {
        self.rules.deinit();
    }

    pub fn runOnSource(self: *Linter, source: *Source) !void {
        const ast = try source.parse();
        var ctx = Context.init(self.gpa, &ast, source);
        print("running linter on source with {d} rules\n", .{self.rules.items.len});

        var i: usize = 0;
        while (i < ctx.ast.nodes.len) {
            assert(i < std.math.maxInt(u32));
            const node = ctx.ast.nodes.get(i);
            const wrapper: NodeWrapper = .{ .node = &node, .idx = @intCast(i) };
            for (self.rules.items) |rule| {
                ctx.updateForRule(&rule);
                rule.runOnNode(wrapper, &ctx) catch |e| {
                    return e;
                };
            }
            i += 1;
        }
    }
};
