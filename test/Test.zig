const File = @import("File.zig");
const SubCommand = @import("SubCommand.zig").SubCommand;
const Result = @import("Result.zig").Result;

file: File,
results: [@typeInfo(SubCommand).@"enum".fields.len]Result = undefined,
