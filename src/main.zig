const std = @import("std");
const lint = @import("lint.zig");
const Source = @import("source.zig").Source;
const semantic = @import("semantic.zig");

const fs = std.fs;
const path = std.path;
const assert = std.debug.assert;
const print = std.debug.print;

const Ast = std.zig.Ast;
const Linter = lint.Linter;

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    print("opening foo.zig\n", .{});
    const file = try fs.cwd().openFile("fixtures/foo.zig", .{});
    var source = try Source.init(gpa, file);
    defer source.deinit();

    var linter = Linter.init(gpa);
    defer linter.deinit();

    var errors = try linter.runOnSource(&source);
    for (errors.items) |err| {
        print("{s}\n", .{err.message});
    }
    errors.deinit();

}

test {
    std.testing.refAllDecls(@This());
}


