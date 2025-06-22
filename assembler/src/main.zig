const std = @import("std");

const Scanner = @import("Scanner.zig");
const common = @import("common.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var in_file_name: ?[]const u8 = null;
    var out_file_name: ?[]const u8 = null;

    var options = common.Options{};

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // skip arg 0
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            const option = arg[2..];
            const value_str = args.next() orelse
                return error.NoValueGivenToOption;

            if (std.mem.eql(u8, option, "build_mode")) {
                options.build_mode = std.meta.stringToEnum(common.BuildMode, value_str) orelse
                    return error.InvalidBuildMode;
            } else if (std.mem.eql(u8, option, "endian")) {
                options.endian = std.meta.stringToEnum(common.Endian, value_str) orelse
                    return error.InvalidEndianness;
            } else {
                const value = try std.fmt.parseInt(u64, value_str, 0);

                if (std.mem.eql(u8, option, "max_filesize")) {
                    if (value == 0) {
                        return error.MaxFilesizeTooSmall;
                    }

                    options.max_filesize = value;
                } else if (std.mem.eql(u8, option, "max_address")) {
                    if (value == 0) {
                        return error.MaxAddressTooSmall;
                    }

                    options.max_address = value;
                } else if (std.mem.eql(u8, option, "max_depth")) {
                    options.max_depth = value;
                } else if (std.mem.eql(u8, option, "diagnostic_base")) {
                    options.diagnostic_base = try std.meta.intToEnum(common.Base, value);
                } else if (std.mem.eql(u8, option, "word_size")) {
                    if (value >= 1 and value <= 8) {
                        options.word_size = @intCast(value);
                    } else {
                        return error.InvalidWordSize;
                    }
                } else {
                    return error.InvalidOption;
                }
            }
        } else if (std.mem.eql(u8, arg, "-o")) {
            if (out_file_name != null) {
                return error.TooManyOutputFiles;
            }
            out_file_name = args.next() orelse
                return error.NoNameGivenToOutput;
        } else {
            if (in_file_name != null) {
                return error.TooManyInputFiles;
            }

            in_file_name = arg;
        }
    }

    const max_max_filesize: u64 = @intCast(
        (@as(u65, 1) << @as(u7, options.word_size) * 8) - 1,
    );

    if (options.max_filesize == 0) { // cannot assign 0 with cli args
        options.max_filesize = max_max_filesize;
    }

    if (options.max_filesize > max_max_filesize) {
        return error.MaxFilesizeTooLarge;
    }

    if (options.max_address == 0) { // cannot assign 0 with cli args
        options.max_address = options.max_filesize;
    }

    if (options.build_mode == .raw and options.max_address != options.max_filesize) {
        return error.RawModeMaximumMismatch;
    }

    if (out_file_name == null) {
        out_file_name = switch (options.build_mode) {
            .raw => "out.sl",
            .relocation => "out.rsl",
            _ => unreachable,
        };
    }

    if (in_file_name) |name|
        try assemble(name, out_file_name.?, options, allocator)
    else
        return error.NoInputFileGiven;
}

fn assemble(
    in_file_name: []const u8,
    out_file_name: []const u8,
    options: common.Options,
    allocator: std.mem.Allocator,
) !void {
    _ = options; // autofix
    var scanner = try Scanner.init(in_file_name, allocator);
    defer scanner.deinitAll();

    const list = try scanner.scan();

    switch (list) {
        .errors => {
            for (list.errors.items) |item| {
                try scanner.printError(item);
            }
            return error.ScanError;
        },
        else => {},
    }

    const tokens = list.tokens.items;
    _ = tokens; // autofix
    _ = out_file_name; // autofix
}

test {
    _ = @import("Scanner.zig");
    _ = @import("Parser.zig");
}
