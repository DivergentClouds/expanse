const std = @import("std");

pub fn ScalarIterator(comptime T: type) type {
    return struct {
        buffer: []const T,
        index: usize,

        const Self = @This();

        pub fn next(self: *Self) ?T {
            const result = self.peek() orelse return null;
            self.index += 1;
            return result;
        }

        pub fn peek(self: Self) ?T {
            if (self.index >= self.buffer.len) return null;
            return self.buffer[self.index];
        }

        pub fn skip(self: *Self) bool {
            if (self.index == self.buffer.len) return false;

            self.index += 1;
            return true;
        }

        pub fn rest(self: Self) []const T {
            return self.buffer[self.index..];
        }
    };
}

pub fn scalarIterator(comptime T: type, buffer: []const T) ScalarIterator(T) {
    return .{ .buffer = buffer, .index = 0 };
}

pub const Base = enum(u8) {
    binary = 2,
    octal = 8,
    decimal = 10,
    hex = 16,
};

pub const BuildMode = enum(u8) { // u8 in case other build modes are added
    raw = 0,
    relocation = 1,
    _,
};

pub const Endian = enum(u1) {
    little = 0,
    big = 1,
};

pub const Options = struct {
    max_depth: u64 = 1000,
    diagnostic_base: Base = .decimal,
    build_mode: BuildMode = .raw,
    endian: Endian = .little,
    word_size: u4 = 2, // in range (1, 8)
    max_filesize: u64 = 0,
    max_address: u64 = 0,
};

pub fn inErrorSet(comptime ErrorSet: type, err: anyerror) bool {
    comptime std.debug.assert(@typeInfo(ErrorSet).error_set != null);

    inline for (@typeInfo(ErrorSet).error_set.?) |e| {
        const error_field = @field(ErrorSet, e.name);

        if (error_field == err) {
            return true;
        }
    } else return false;
}

pub fn ErrorWithPayload(
    comptime Payload: type,
    comptime ErrorSet: type,
) type {
    return struct {
        payload: Payload,
        err: ErrorSet,
    };
}

test {
    std.testing.refAllDecls(@This());
}
