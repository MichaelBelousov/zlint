const std = @import("std");
const fs = std.fs;

const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const assert = std.debug.assert;

pub const Source = struct {
    contents: [:0]u8,
    file: fs.File,
    ast: ?Ast = null,
    gpa: Allocator,

    pub fn init(gpa: Allocator, file: fs.File) !Source {
        const meta = try file.metadata();
        const contents = try gpa.allocSentinel(u8, meta.size(), 0);
        const bytes_read = try file.readAll(contents);
        assert(bytes_read == meta.size());
        return Source{ .contents = contents, .file = file, .gpa = gpa };
    }

    pub fn deinit(self: *Source) void {
        self.file.close();
        self.gpa.free(self.contents);
        if (self.ast != null) {
            self.ast.?.deinit(self.gpa);
        }
        self.* = undefined;
    }

    pub fn parse(self: *Source) !Ast {
        if (self.ast) |ast| {
            return ast;
        }
        self.ast = try Ast.parse(self.gpa, self.contents, .zig);
        return self.ast orelse unreachable;
    }
};
