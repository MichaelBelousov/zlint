// todo: re-parse from user-friendly "rules" object into this AoS.
rules: []RuleFilter,

/// Read and parse a config JSON file.
///
/// Path is relative to the current working directory. Caller is responsible
/// for freeing the returned config.
pub fn readFromFile(alloc: Allocator, path: string) !Parsed(Config) {
    const MAX_BYTES: usize = std.math.maxInt(u32);
    const contents = fs.cwd().readFileAlloc(alloc, path, MAX_BYTES) catch |err| {
        return err;
    };
    defer alloc.free(contents);

    return parse(alloc, contents);
}

/// Parse a config object from a JSON string.
///
/// String contents are borrowed. Caller is responsible for freeing the returned config.
pub fn parse(alloc: Allocator, contents: string) !Parsed(Config) {
    const config = std.json.parseFromSlice(Config, alloc, contents) catch |err| {
        return err;
    };

    return config;
}

/// A configured rule.
///
/// Stored in `"rules"` config field. Looks something like this:
/// ```json
/// {
///   // ...
///   "rules": {
///     "no-undefined": "error",
///   }
/// ```
const RuleFilter = struct {
    /// The name of the rule being configured.
    name: string,
    severity: Severity,
};

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

const Config = @This();
const Parsed = std.json.Parsed;

const std = @import("std");
const fs = std.fs;

const Allocator = std.mem.Allocator;
const string = @import("str.zig").string;
