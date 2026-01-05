row: u32,
col: u32,

source: u32 = 0,

start: u32,
end: u32,

pub fn getText(self: @This(), content: [:0]const u8) []const u8 {
    return content[self.start..self.end];
}

pub fn shallowCopy(self: @This(), start: u32, end: u32) @This() {
    var new = self;
    new.start = start;
    new.end = end;

    return new;
}

pub fn init() @This() {
    return @This(){
        .col = 1,
        .row = 1,

        .start = undefined,
        .end = undefined,
    };
}
