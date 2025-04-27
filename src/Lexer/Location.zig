const Lexer = @import("Lexer.zig");
const PrettyLocation = Lexer.PrettyLocation;

row: u32,
col: u32,

path: []const u8,
content: [:0]const u8,

start: u32,
end: u32,

pub fn getText(self: @This()) []const u8 {
    return self.content[self.start..self.end];
}

pub fn shallowCopy(self: @This(), start: u32, end: u32) @This() {
    var new = self;
    new.start = start;
    new.end = end;

    return new;
}

pub fn init(path: []const u8, content: [:0]const u8) @This() {
    return @This(){
        .path = path,
        .content = content,

        .col = 1,
        .row = 1,

        .start = undefined,
        .end = undefined,
    };
}
