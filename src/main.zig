const std = @import("std");

const fs = std.fs;
const path = std.path;
const Ast = std.zig.Ast;

pub fn main() !void {
    const gpa = std.heap.c_allocator;

    var file = try fs.cwd().openFile("src/main.zig", .{});
    defer file.close();

    const meta = try file.metadata();
    const contents = try gpa.allocSentinel(u8, meta.size(), 0);
    defer gpa.free(contents);

    var ast = try Ast.parse(gpa, contents, .zig);
    defer ast.deinit();
}

