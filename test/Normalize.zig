const Report = struct {
    text: []const u8,
    line: u32,
    column: u32,
};

pub fn normalize(alloc: Allocator, str: []const u8) (Allocator.Error || error{notFound})![]const u8 {
    const firstReport = nextReport(str) orelse return str;

    var list = try std.ArrayList(u8).initCapacity(alloc, str.len);
    var reportList = std.ArrayList(Report){};
    errdefer reportList.deinit(alloc);

    list.appendSliceAssumeCapacity(str[0..firstReport]);

    var reports = str[firstReport..];

    while (nextReport(reports)) |current| {
        const next = (nextReport(reports[current + 1 ..]) orelse reports.len - 1) + 1;
        const reportText = reports[current..next];

        const location = try parseLocation(reportText);

        try reportList.append(alloc, .{
            .text = reportText,
            .line = location.line,
            .column = location.column,
        });

        reports = reports[next..];
    }

    std.mem.sort(Report, reportList.items, {}, struct {
        fn lessThan(_: void, a: Report, b: Report) bool {
            if (a.line != b.line) return a.line < b.line;
            return a.column < b.column;
        }
    }.lessThan);

    for (reportList.items) |report| {
        list.appendSliceAssumeCapacity(report.text);
    }

    return list.items;
}

fn parseLocation(reportText: []const u8) error{notFound}!struct { line: u32, column: u32 } {
    const start = std.mem.indexOf(u8, reportText, "]: ") orelse return error.notFound;
    const afterLevel = start + 3; // Skip ]: and space

    const firtColon: usize = std.mem.indexOf(u8, reportText[afterLevel..], ":").? + afterLevel;
    const secondColon: usize = std.mem.indexOf(u8, reportText[firtColon + 1 ..], ":").? + 1 + firtColon;
    const thrirdColon: usize = std.mem.indexOf(u8, reportText[secondColon + 1 ..], ":").? + 1 + secondColon;

    const row = std.fmt.parseInt(u32, reportText[firtColon + 1 .. secondColon], 10) catch @panic("File Too Big");
    const column = std.fmt.parseInt(u32, reportText[secondColon + 1 .. thrirdColon], 10) catch @panic("File Too Big");

    return .{ .line = row, .column = column };
}

fn nextReport(str: []const u8) ?usize {
    const info_pos = std.mem.indexOf(u8, str, "[INFO]");
    const warning_pos = std.mem.indexOf(u8, str, "[WARNING]");
    const error_pos = std.mem.indexOf(u8, str, "[ERROR]");
    const debug_pos = std.mem.indexOf(u8, str, "[DEBUG]");

    var min_pos: ?usize = null;

    if (info_pos) |pos| {
        min_pos = pos;
    }
    if (warning_pos) |pos| {
        min_pos = if (min_pos) |m| @min(m, pos) else pos;
    }
    if (error_pos) |pos| {
        min_pos = if (min_pos) |m| @min(m, pos) else pos;
    }
    if (debug_pos) |pos| {
        min_pos = if (min_pos) |m| @min(m, pos) else pos;
    }

    return min_pos;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
