pub const Message = @import("Message.zig");

const ReportBucketSize = std.math.pow(usize, 2, 2);
pub const Report = @import("Report.zig");

pub const expect = Report.expect;
pub const incompatibleLiteral = Report.incompatibleLiteral;
pub const incompatibleType = Report.incompatibleType;

pub const Reports = Bucketarray(Report, usize, ReportBucketSize);

pub const UnexpectedToken = @import("UnexpectedToken.zig");
pub const IncompatibleType = @import("IncompatibleType.zig");
pub const IncompatibleLiteral = @import("IncompatibleLiteral.zig");

const Bucketarray = @import("../Util/BucketArray.zig").BucketArray;

const std = @import("std");
