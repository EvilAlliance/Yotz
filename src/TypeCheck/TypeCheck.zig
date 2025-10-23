const Self = @This();

ast: *Parser.Ast,
message: Message,
tu: *const TranslationUnit,

pub fn init(ast: *Parser.Ast, tu: *const TranslationUnit) Self {
    return Self{
        .ast = ast,
        .message = Message.init(ast),
        .tu = tu,
    };
}

pub fn checkRoot(self: *Self, alloc: Allocator, rootIndex: Parser.NodeIndex) Allocator.Error!void {
    const root = self.ast.getNode(.Bound, rootIndex);

    var nodeIndex = root.data.@"0".load(.acquire);
    const endIndex = root.data.@"1".load(.acquire);

    while (nodeIndex != endIndex) {
        const node = self.ast.getNode(.Bound, nodeIndex);
        defer nodeIndex = node.next.load(.acquire);

        switch (node.tag.load(.acquire)) {
            .variable, .constant => {
                // NOTE: At the time being this is not changed so it should be fine;
                const expressionIndex = node.data.@"1".load(.acquire);
                const expressionNode = self.ast.getNode(.UnCheck, expressionIndex);
                const expressionTag = expressionNode.tag.load(.acquire);

                if (expressionIndex == 0 or expressionTag == .funcProto) {
                    try self.checkFunctionOuter(alloc, nodeIndex);
                } else if (expressionTag == .constant or expressionTag == .variable) {
                    @panic("Not messing with this yet");
                } else {
                    unreachable;
                }
            },

            else => unreachable,
        }
    }
}

fn dupe(self: *const Self, alloc: Allocator) Allocator.Error!*Self {
    const selfDupe = try Util.dupe(alloc, self.*);
    const chunk = try alloc.create(Parser.NodeList.Chunk);
    chunk.* = try Parser.NodeList.Chunk.init(alloc, self.ast.nodeList.base);

    const ast = try alloc.create(Parser.Ast);
    ast.* = Parser.Ast.init(chunk, self.tu);
    selfDupe.ast = ast;

    return selfDupe;
}

fn destroyDupe(self: *const Self, alloc: Allocator) void {
    alloc.destroy(self.ast.nodeList);
    alloc.destroy(self.ast);
    alloc.destroy(self);
}

pub fn checkFunctionOuter(self: *Self, alloc: Allocator, variableIndex: Parser.NodeIndex) Allocator.Error!void {
    const variable = self.ast.getNode(.Bound, variableIndex);
    const funcIndex = variable.data.@"1".load(.acquire);
    if (funcIndex == 0) {
        const callBack = struct {
            fn callBack(args: getTupleFromParams(checkFunctionOuter)) void {
                defer args[0].destroyDupe(args[1]);
                @call(.auto, checkFunctionOuter, args) catch {
                    TranslationUnit.failed = true;
                    std.log.err("Run Out of Memory", .{});
                };
            }
        }.callBack;

        try TranslationUnit.observer.push(alloc, variableIndex, callBack, .{ try self.dupe(alloc), alloc, variableIndex });

        return;
    }

    while (true) {
        Type.transformType(self, self.ast.getNode(.UnBound, funcIndex).data[1].load(.acquire));

        const typeIndex = variable.data[0].load(.acquire);
        if (typeIndex != 0) {
            Type.transformType(self, typeIndex);
            self.checkTypeFunction(alloc, typeIndex, funcIndex);
            break;
        } else {
            const result = try self.inferTypeFunction(alloc, variableIndex, funcIndex);

            if (result)
                break;
        }
    }
}

pub fn checkTypeFunction(self: *const Self, alloc: Allocator, funcTypeIndex: Parser.NodeIndex, funcIndex: Parser.NodeIndex) void {
    _ = alloc;
    const funcProto = self.ast.getNode(.UnBound, funcIndex);
    std.debug.assert(funcProto.tag.load(.acquire) == .funcProto);
    std.debug.assert(funcProto.data[0].load(.acquire) == 0);

    const funcRetTypeIndex = funcProto.data[1].load(.acquire);

    const funcType = self.ast.getNode(.Bound, funcTypeIndex);
    std.debug.assert(funcType.tag.load(.acquire) == .funcType);
    std.debug.assert(funcType.data[0].load(.acquire) == 0);

    const retTypeIndex = funcType.data[1].load(.acquire);

    if (!Type.typeEqual(self, funcRetTypeIndex, retTypeIndex)) {
        self.message.err.incompatibleType(retTypeIndex, funcRetTypeIndex, self.ast.getNodeLocation(.UnBound, funcRetTypeIndex));
    }
}

pub fn inferTypeFunction(self: *Self, alloc: Allocator, variableIndex: Parser.NodeIndex, funcIndex: Parser.NodeIndex) Allocator.Error!bool {
    const proto = self.ast.getNode(.UnBound, funcIndex);
    std.debug.assert(proto.tag.load(.acquire) == .funcProto);

    const tIndex = proto.data[1].load(.acquire);
    std.debug.assert(tIndex != 0);
    std.debug.assert(self.ast.getNode(.UnBound, tIndex).tag.load(.acquire) == .type);

    const functionTypeIndex = try self.ast.nodeList.appendIndex(alloc, Parser.Node{
        .tag = .init(.funcType),
        .tokenIndex = .init(proto.tokenIndex.load(.acquire)),
        .data = .{ .init(0), .init(tIndex) },
        .flags = .init(.{ .inferedFromExpression = true }),
    });

    const nodePtr = self.ast.getNodePtr(.Bound, variableIndex);
    const result = nodePtr.data.@"0".cmpxchgWeak(0, functionTypeIndex, .acq_rel, .monotonic);
    self.ast.unlockShared();

    return result == null;
}

pub fn checkFunction(self: *Self, alloc: Allocator, funcIndex: Parser.NodeIndex) type {
    _ = .{ self, alloc, funcIndex };
}

fn getTupleFromParams(comptime func: anytype) type {
    const typeFunc = @TypeOf(func);
    const typeInfo = @typeInfo(typeFunc);

    const params = typeInfo.@"fn".params;
    // var fieldArr: [params.len]std.builtin.Type.StructField = undefined;
    // for (params, 0..) |param, i| {
    //     const name = std.fmt.comptimePrint("f{}", .{i});
    //
    //     fieldArr[i] = .{
    //         .name = name,
    //         .type = param.type.?,
    //         .default_value_ptr = null,
    //         .is_comptime = false,
    //         .alignment = @alignOf(param.type.?),
    //     };
    // }
    //
    // return @Type(.{
    //     .@"struct" = .{
    //         .fields = &fieldArr,
    //         .layout = .auto,
    //         .decls = &.{},
    //         .is_tuple = false,
    //         .backing_integer = null,
    //     },
    // });

    var typeArr: [params.len]type = undefined;

    for (params, 0..) |param, i|
        typeArr[i] = param.type.?;

    return std.meta.Tuple(&typeArr);
}

pub const ObserverParams = getTupleFromParams(checkFunctionOuter);

const Type = @import("Type.zig");

const Parser = @import("./../Parser/mod.zig");
const Message = @import("../Message/Message.zig");
const TranslationUnit = @import("../TranslationUnit.zig");

const Util = @import("../Util.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
