message: string,
severity: Severity = .err,
labels: []Span = .{},
source_name: ?string = null,
help: ?string = null,

pub fn new(message: string) Error {
    return Error{
        .message = message,
    };
}

pub fn newAtLocation(message: string, span: Span, source_name: string) Error {
    return Error{
        .message = message,
        .source_name = source_name,
        .labels = [_]Span{ span },
    };
}

/// Severity level for issues found by lint rules.
///
/// Each lint rule gets assigned a severity level.
/// - Errors cause a non-zero exit code. They are highlighted in red.
/// - Warnings do not affect exit code and are yellow.
/// - Off skips the rule entirely.
const Severity = enum {
    err,
    warning,
    off,
};

const Error = @This();

const std = @import("std");
const string = @import("str.zig").string;
const Span = @import("source.zig").Span;
