const std = @import("std");
const protocol = @import("../lib.zig");
pub const InventoryItem = @import("../types/InventoryItem.zig");
const CompactSizeUint = @import("bitcoin-primitives").types.CompatSizeUint;
const genericChecksum = @import("lib.zig").genericChecksum;
const genericSerialize = @import("lib.zig").genericSerialize;
const genericDeserializeSlice = @import("lib.zig").genericDeserializeSlice;
/// InvMessage represents the "inv" message
///
/// https://developer.bitcoin.org/reference/p2p_networking.html#inv
pub const InvMessage = struct {
    inventory: []const InventoryItem,
    const Self = @This();
    pub fn name() *const [12]u8 {
        return protocol.CommandNames.INV ++ [_]u8{0} ** 9;
    }

    pub fn checksum(self: *const Self) [4]u8 {
        return genericChecksum(self);
    }

    /// Free the `inventory`
    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        allocator.free(self.inventory);
    }

    /// Serialize a message as bytes and return them.
    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        return try genericSerialize(self, allocator);
    }

    /// Serialize the message as bytes and write them to the Writer.
    pub fn serializeToWriter(self: *const Self, w: anytype) !void {
        const count = CompactSizeUint.new(self.inventory.len);
        try count.encodeToWriter(w);
        for (self.inventory) |item| {
            try item.encodeToWriter(w);
        }
    }

    pub fn deserializeSlice(allocator: std.mem.Allocator, bytes: []const u8) !Self {
        return genericDeserializeSlice(InvMessage, allocator, bytes);
    }

    pub fn deserializeReader(allocator: std.mem.Allocator, r: anytype) !Self {
        const count = try CompactSizeUint.decodeReader(r);
        const inventory = try allocator.alloc(InventoryItem, count.value());
        errdefer allocator.free(inventory);

        for (inventory) |*item| {
            item.* = try InventoryItem.decodeReader(r);
        }

        return .{ .inventory = inventory };
    }

    pub fn hintSerializedLen(self: Self) usize {
        const compact_count_length = CompactSizeUint.new(self.inventory.len).hint_encoded_len();
        const inventory_length = InventoryItem.hintSerializedLen() * self.inventory.len;

        return compact_count_length + inventory_length;
    }

    pub fn eql(self: *const @This(), other: *const @This()) bool {
        if (self.inventory.len != other.inventory.len) return false;

        for (0..self.inventory.len) |i| {
            const item_self = self.inventory[i];
            const item_other = other.inventory[i];
            if (!item_self.eql(&item_other)) {
                return false;
            }
        }

        return true;
    }
};

// TESTS
test "ok_full_flow_InvMessage" {
    const allocator = std.testing.allocator;

    {
        const inventory_items = [_]protocol.InventoryItem{
            .{ .type = 1, .hash = [_]u8{0xab} ** 32 },
            .{ .type = 2, .hash = [_]u8{0xcd} ** 32 },
            .{ .type = 2, .hash = [_]u8{0xef} ** 32 },
        };

        const inv = InvMessage{
            .inventory = inventory_items[0..],
        };
        const payload = try inv.serialize(allocator);
        defer allocator.free(payload);

        const deserialized_msg = try InvMessage.deserializeSlice(allocator, payload);
        defer deserialized_msg.deinit(allocator);
        try std.testing.expect(inv.eql(&deserialized_msg));
    }
}
