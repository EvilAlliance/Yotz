pub const Message = @import("Message.zig");

const ReportBucketSize = std.math.pow(usize, 2, 2);
pub const Report = @import("Report.zig");

pub const expect = Report.expect;
pub const incompatibleLiteral = Report.incompatibleLiteral;
pub const incompatibleType = Report.incompatibleType;
pub const missingMain = Report.missingMain;
pub const undefinedVariable = Report.undefinedVariable;
pub const redefinition = Report.redefinition;
pub const definedLater = Report.definedLater;
pub const dependencyCycle = Report.dependencyCycle;
pub const mustReturnU8 = Report.mustReturnU8;
pub const missingReturn = Report.missingReturn;
pub const unreachableStatement = Report.unreachableStatement;
pub const expectedFunction = Report.expectedFunction;
pub const incompatibleReturnType = Report.incompatibleReturnType;

pub const Reports = ArrayListThreadSafe(Report);

pub const UnexpectedToken = @import("UnexpectedToken.zig");
pub const IncompatibleType = @import("IncompatibleType.zig");
pub const IncompatibleLiteral = @import("IncompatibleLiteral.zig");
pub const MissingMain = @import("MissingMain.zig");
pub const UndefinedVariable = @import("UndefinedVariable.zig");
pub const Redefinition = @import("Redefinition.zig");
pub const DefinedLater = @import("DefinedLater.zig");
pub const DependencyCycle = @import("DependencyCycle.zig");
pub const MustReturnU8 = @import("MustReturnU8.zig");
pub const MissingReturn = @import("MissingReturn.zig");
pub const UnreachableStatement = @import("UnreachableStatement.zig");
pub const ExpectedFunction = @import("ExpectedFunction.zig");
pub const IncompatibleReturnType = @import("IncompatibleReturnType.zig");

const Bucketarray = @import("../Util/BucketArray.zig").BucketArray;
const ArrayListThreadSafe = @import("../Util/ArrayListThreadSafe.zig").ArrayListThreadSafe;

const std = @import("std");
