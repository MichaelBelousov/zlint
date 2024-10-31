const std = @import("std");
const str = @import("str.zig");
const fs = std.fs;

const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const assert = std.debug.assert;
const string = str.string;

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

pub const LocationSpan = struct {
    span: Span,
    location: Location,
};
pub const Span = struct {
    start: u32,
    end: u32,
};

pub const Location = struct {
    line: u32,
    column: u32,

    pub fn fromSpan(contents: string, span: Span) Location {
        const l = std.zig.findLineColumn(contents, @intCast(span.start));
        return Location{
            .line = l.line,
            .column = l.column,
        };
    }
    // TODO: toSpan()
};
