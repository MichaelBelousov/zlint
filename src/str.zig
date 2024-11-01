// MIKE: gross lol
pub const string = []const u8;
// how is this a string slice? It's a sentinel terminated pointer, not a slice...
// if you really want a name, it's a cstring
pub const stringSlice = [:0]const u8;
pub const stringMut = []u8;
