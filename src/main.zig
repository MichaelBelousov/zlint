const std = @import("std");
const lint = @import("lint.zig");
const Source = @import("source.zig").Source;

const fs = std.fs;
const path = std.path;
const assert = std.debug.assert;
const print = std.debug.print;

const Ast = std.zig.Ast;
const Linter = lint.Linter;
// const LinterContext = lint.LinterContext;

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    print("opening foo.zig\n", .{});
    const file = try fs.cwd().openFile("fixtures/foo.zig", .{});
    var source = try Source.init(gpa, file);
    defer source.deinit();

    var linter = Linter.init(gpa);
    defer linter.deinit();

    try linter.runOnSource(&source);

}

test {
    std.testing.refAllDecls(@This());
}


