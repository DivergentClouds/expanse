const std = @import("std");
const common = @import("common.zig");

const Scanner = @This();

source: std.fs.File,
source_name: []const u8,
location: Location,
list: List,
allocator: std.mem.Allocator,

/// caller owns result and must deinitialize with `deinitList`
pub fn init(
    source_name: []const u8,
    allocator: std.mem.Allocator,
) !Scanner {
    return Scanner{
        .source_name = source_name,
        .source = try std.fs.cwd().openFile(source_name, .{}),
        .location = .{
            .index = 0,
            .line = 1,
            .column = 0,
        },
        .list = .{
            .tokens = std.ArrayList(Token).init(allocator),
        },
        .allocator = allocator,
    };
}

pub fn deinitAll(
    scanner: Scanner,
) void {
    scanner.source.close();
    scanner.list.deinit(scanner.allocator);
}

pub const List = union(enum) {
    tokens: std.ArrayList(Token),
    errors: std.ArrayList(ScanErrorWithPayload),

    pub fn deinit(list: List, allocator: std.mem.Allocator) void {
        switch (list) {
            .tokens => {
                for (list.tokens.items) |item| {
                    item.deinit(allocator);
                }
                list.tokens.deinit();
            },
            .errors => list.errors.deinit(),
        }
    }
};

pub const TokenOrError = union(enum) {
    token: Token,
    error_with_payload: ScanErrorWithPayload,
};

const keywords = [_][]const u8{
    "macro",
    "return",
    "for",
    "in",
    "const",
    "var",
    "pub",
    "if",
    "elseif",
    "else",
    "error",
    "info",
    "import",
    "has",
};

/// Returns `scanner.list`.
pub fn scan(scanner: *Scanner) !List {
    std.debug.assert(std.meta.activeTag(scanner.list) == .tokens);

    var success = true;

    list_builder: switch (try scanner.scanToken()) {
        .token => |token| {
            if (success) {
                try scanner.list.tokens.append(token);
            } else {
                token.deinit(scanner.allocator);
            }
            if (token.kind == .eof) {
                break :list_builder;
            } else {
                continue :list_builder try scanner.scanToken();
            }
        },
        .error_with_payload => |err| {
            if (success) {
                success = false;

                scanner.list.deinit(scanner.allocator);
                scanner.list = .{
                    .errors = std.ArrayList(ScanErrorWithPayload).init(
                        scanner.allocator,
                    ),
                };
            }
            try scanner.list.errors.append(err);

            continue :list_builder try scanner.scanToken();
        },
    }

    return scanner.list;
}

pub fn scanToken(scanner: *Scanner) !TokenOrError {
    const reader = scanner.source.reader();

    const starting_location = scanner.location;

    var lexeme_byte_list = std.ArrayList(u8).init(scanner.allocator);
    defer lexeme_byte_list.deinit();

    scanner.incrementLocation(1);

    const byte = reader.readByte() catch {
        return .{
            .token = Token{
                .kind = .eof,
                .lexeme = "",
                .literal = .{ .none = {} },
                .location = scanner.location,
            },
        };
    };

    try lexeme_byte_list.append(byte);

    var token_kind: TokenKind = undefined;

    switch (byte) {
        '\n' => {
            scanner.location.column = 0;
            scanner.location.line += 1;
            scanner.location.index += 1;

            token_kind = .newline;
        },
        ',' => token_kind = .comma,
        '{' => token_kind = .right_brace,
        '}' => token_kind = .left_brace,
        '(' => token_kind = .right_paren,
        ')' => token_kind = .left_paren,
        '[' => token_kind = .right_bracket,
        ']' => token_kind = .left_bracket,
        '#' => token_kind = .hash,
        '$' => {
            if (try scanner.match('$')) {
                token_kind = .start_of_section;
            } else {
                token_kind = .current_word;
            }
        },
        '\\' => token_kind = .next_word,
        ':' => token_kind = .colon,
        '@' => token_kind = .at,
        '+' => token_kind = .plus,
        '-' => token_kind = .minus,
        '*' => token_kind = .times,
        '/' => {
            if (try scanner.match('/')) {
                try scanner.skipComment();
            } else {
                token_kind = .divide;
            }
        },
        '%' => token_kind = .modulo,
        '~' => token_kind = .bit_not,
        '&' => token_kind = .bit_and,
        '|' => token_kind = .bit_or,
        '=' => {
            if (try scanner.match('=')) {
                token_kind = .equals;
            } else {
                token_kind = .assign;
            }
        },
        '.' => {
            if (try scanner.match('.')) {
                token_kind = .range;
            } else {
                token_kind = .import_access;
            }
        },
        '<' => {
            if (try scanner.match('=')) {
                token_kind = .less_or_equal;
            } else if (try scanner.match('<')) {
                token_kind = .left_shift;
            } else {
                token_kind = .less;
            }
        },
        '>' => {
            if (try scanner.match('=')) {
                token_kind = .greater_or_equal;
            } else if (try scanner.match('>')) {
                token_kind = .right_shift;
            } else {
                token_kind = .greater;
            }
        },
        '!' => {
            if (try scanner.match('=')) {
                token_kind = .not_equals;
            } else {
                token_kind = .array_access;
            }
        },
        '"' => {
            // scan string
            scanner.readString(&lexeme_byte_list) catch |err| {
                if (common.inErrorSet(ScanError, err)) {
                    return .{
                        .error_with_payload = .{
                            .payload = starting_location,
                            .err = @errorCast(err),
                        },
                    };
                } else return err;
            };

            const unparsed_string =
                lexeme_byte_list.items[1 .. lexeme_byte_list.items.len - 1];

            // parse "\n" and such here
            var string_array_list = std.ArrayList(u8).init(scanner.allocator);
            defer string_array_list.deinit();

            var problem_offset: u64 = 0;

            parseString(unparsed_string, &string_array_list, &problem_offset) catch |err| {
                if (common.inErrorSet(ScanError, err)) {
                    return .{
                        .error_with_payload = .{
                            .payload = Location{
                                .index = starting_location.index + problem_offset + 1, // index 0 is starting double quote
                                .column = starting_location.column + problem_offset + 1,
                                .line = starting_location.line,
                            },
                            .err = @errorCast(err),
                        },
                    };
                } else return err;
            };

            const lexeme = try lexeme_byte_list.toOwnedSlice();
            errdefer scanner.allocator.free(lexeme);

            // return string token here
            return .{
                .token = .{
                    .kind = .string,
                    .lexeme = lexeme,
                    .literal = .{
                        .string = try string_array_list.toOwnedSlice(),
                    },
                    .location = starting_location,
                },
            };
        },
        '\t' => {
            return .{
                .error_with_payload = .{
                    .payload = starting_location,
                    .err = ScanError.TabFound,
                },
            };
        },
        else => {
            if (std.ascii.isDigit(byte)) {
                // integer literal
                try scanner.readInteger(&lexeme_byte_list, byte);

                const integer = std.fmt.parseInt(
                    i64,
                    lexeme_byte_list.items,
                    0,
                ) catch return .{
                    .error_with_payload = .{
                        .payload = starting_location,
                        .err = ScanError.InvalidInteger,
                    },
                };

                return .{
                    .token = .{
                        .kind = .integer,
                        .lexeme = try lexeme_byte_list.toOwnedSlice(),
                        .literal = .{
                            .integer = integer,
                        },
                        .location = starting_location,
                    },
                };
            } else if (std.ascii.isAlphabetic(byte) or byte == '_') {
                // identifier literal or keyword
                try scanner.source.seekBy(-1);
                try scanner.readIdentifier(&lexeme_byte_list);

                const lexeme = try lexeme_byte_list.toOwnedSlice();

                for (keywords) |keyword| {
                    if (std.mem.eql(u8, lexeme, keyword)) {
                        return .{
                            .token = .{
                                .kind = std.meta.stringToEnum(TokenKind, lexeme) orelse unreachable,
                                .lexeme = lexeme,
                                .literal = .{ .none = {} },
                                .location = starting_location,
                            },
                        };
                    }
                } else {
                    // identifier
                    return .{
                        .token = .{
                            .kind = .identifier,
                            .lexeme = lexeme,
                            .literal = .{ .none = {} },
                            .location = starting_location,
                        },
                    };
                }
            } else if (!std.ascii.isWhitespace(byte)) {
                return .{
                    .error_with_payload = .{
                        .payload = starting_location,
                        .err = ScanError.InvalidLexeme,
                    },
                };
            }
        },
    }
    return .{
        .token = .{
            .kind = token_kind,
            .lexeme = try lexeme_byte_list.toOwnedSlice(),
            .literal = .{ .none = {} },
            .location = starting_location,
        },
    };
}

fn readString(
    scanner: *Scanner,
    array_list: *std.ArrayList(u8),
) !void {
    const reader = scanner.source.reader();

    var prev_backslash: bool = false; // for escape codes

    while (reader.readByte() catch null) |byte| {
        if (prev_backslash) {
            prev_backslash = false;

            try array_list.append(byte);
        } else {
            try array_list.append(byte);
            if (byte == '\\')
                prev_backslash = true
            else if (byte == '"')
                break;
        }
    } else {
        return ScanError.UnclosedString;
    }
    scanner.incrementLocation(array_list.items.len - 1);
}

fn parseString(
    unparsed_string: []const u8,
    parsed_string: *std.ArrayList(u8),
    index: *u64, // starts at 0
) !void {
    const index_max = unparsed_string.len;

    while (index.* < index_max) : (index.* += 1) {
        var byte = unparsed_string[index.*];

        if (byte == '\\') {
            index.* += 1;
            if (index.* > index_max)
                return ScanError.InvalidStringEscapeCode;

            byte = unparsed_string[index.*];
            switch (byte) {
                '\\' => try parsed_string.append('\\'),
                'n' => try parsed_string.append('\n'),
                't' => try parsed_string.append('\t'),
                '"' => try parsed_string.append('"'),
                'x' => {
                    if (index.* + 2 > index_max)
                        return ScanError.InvalidStringEscapeCode;

                    index.* += 1;
                    byte = unparsed_string[index.*];

                    var out = std.fmt.charToDigit(byte, 16) catch
                        return ScanError.InvalidStringEscapeCode;
                    out <<= 4;

                    index.* += 1;
                    byte = unparsed_string[index.*];

                    out |= std.fmt.charToDigit(byte, 16) catch
                        return ScanError.InvalidStringEscapeCode;

                    try parsed_string.append(out);
                },
                else => return ScanError.InvalidStringEscapeCode,
            }
        } else {
            switch (byte) {
                '\n', '\r' => return ScanError.NewlineFoundInString,
                else => try parsed_string.append(byte),
            }
        }
    }
}

fn match(scanner: Scanner, expected: u8) !bool {
    const reader = scanner.source.reader();

    const char = reader.readByte() catch
        return false;

    if (char != expected) {
        try scanner.source.seekBy(-1);
        return false;
    }

    return true;
}

fn incrementLocation(scanner: *Scanner, amount: u64) void {
    scanner.location.index += amount;
    scanner.location.column += amount;
}

fn skipComment(
    scanner: *Scanner,
) !void {
    const reader = scanner.source.reader();

    var length: u64 = 0;

    while (reader.readByte() catch null) |byte| {
        if (byte == '\n') {
            try scanner.source.seekBy(-1);
            break;
        }

        length += 1;
    }

    scanner.incrementLocation(length);
}

/// reads an integer
/// assumes first character is valid
fn readInteger(
    scanner: *Scanner,
    array_list: *std.ArrayList(u8),
    first: u8,
) !void {
    const source = scanner.source;
    const reader = source.reader();

    var base: u8 = 10;

    if (first == '0') {
        const second = try reader.readByte();

        switch (second) {
            '0'...'9', 'b', 'o', 'x' => {
                try array_list.append(second);

                switch (second) {
                    'b' => base = 2,
                    'o' => base = 8,
                    'x' => base = 16,
                    else => {},
                }
            },
            else => {
                try source.seekBy(-1);
            },
        }
    }

    if (reader.readByte() catch null) |byte| {
        integer_builder: switch (byte) {
            '0'...'9' => {
                if (byte & 0xf < base) {
                    try array_list.append(byte);
                    continue :integer_builder reader.readByte() catch
                        break :integer_builder;
                } else {
                    try source.seekBy(-1);
                }
            },
            'a'...'f', 'A'...'F' => {
                if (base == 16) {
                    try array_list.append(byte);
                    continue :integer_builder reader.readByte() catch
                        break :integer_builder;
                } else {
                    try source.seekBy(-1);
                }
            },
            else => {
                try source.seekBy(-1);
            },
        }
    }
    scanner.incrementLocation(array_list.items.len - 1); // already incremented once in parseChar
}

/// reads an identifier, keyword, or structurally similar lexeme
/// the first byte is already read
fn readIdentifier(
    scanner: *Scanner,
    array_list: *std.ArrayList(u8),
) !void {
    const reader = scanner.source.reader();

    if (reader.readByte() catch null) |byte| {
        identifier_builder: switch (byte) {
            'a'...'z', 'A'...'Z', '0'...'9', '_' => |char| {
                try array_list.append(char);
                continue :identifier_builder reader.readByte() catch
                    break :identifier_builder;
            },
            else => {
                try scanner.source.seekBy(-1);
            },
        }
    }

    scanner.incrementLocation(array_list.items.len - 1); // first byte is already read
}

pub const ScanError = error{
    InvalidLexeme,
    InvalidInteger,
    InvalidStringEscapeCode,
    TabFound,
    NewlineFoundInString,
    UnclosedString,
};

pub const ScanErrorWithPayload = common.ErrorWithPayload(
    Location,
    ScanError,
);

pub fn printError(
    scanner: Scanner,
    error_with_payload: ScanErrorWithPayload,
) !void {
    const stderr = std.io.getStdErr().writer();

    const location = error_with_payload.payload;

    const line_start_index = location.index - location.column;
    try scanner.source.seekTo(line_start_index);

    var line_list = std.ArrayList(u8).init(scanner.allocator);
    defer line_list.deinit();

    // don't error on EOF
    scanner.source.reader().streamUntilDelimiter(line_list.writer(), '\n', null) catch |err| {
        switch (err) {
            error.EndOfStream => {},
            else => return err,
        }
    };

    try stderr.print(
        \\Error: {s}
        \\{s} {d}:{d}
        \\{s}
        \\
    , .{
        @errorName(error_with_payload.err),
        scanner.source_name,
        location.line,
        location.column,
        line_list.items,
    });

    for (0..location.column) |_| {
        try stderr.writeByte(' ');
    }
    try stderr.writeAll("^\n\n");
}

pub const TokenKind = enum {
    // non-operator symbol tokens
    newline,
    comma,
    left_brace, // {
    right_brace, // }
    left_paren, // (
    right_paren, // )
    left_bracket, // [
    right_bracket, // ]
    hash,
    assign,
    import_access, // .
    next_word, // >
    start_of_section, // $$
    current_word, // $
    range,
    colon,
    at,

    // operators
    plus,
    minus,
    times,
    divide,
    modulo,
    left_shift,
    right_shift,
    bit_not,
    bit_and,
    bit_or,
    equals,
    not_equals,
    greater,
    greater_or_equal,
    less,
    less_or_equal,
    has,
    array_access, // !

    // literals
    identifier,
    integer,
    string,

    // keywords
    macro,
    @"return",
    @"for",
    in,
    @"const",
    @"var",
    @"pub",
    @"if",
    elseif,
    @"else",
    @"error",
    info,
    import,

    // misc
    eof,
};

pub const Location = struct {
    index: u64,
    line: u64,
    column: u64,
};

pub const Token = struct {
    kind: TokenKind,
    lexeme: []const u8,
    literal: union {
        string: []const u8,
        integer: i64,
        none: void,
    },
    location: Location,

    pub fn deinit(token: Token, allocator: std.mem.Allocator) void {
        allocator.free(token.lexeme);

        if (token.kind == .string) {
            allocator.free(token.literal.string);
        }
    }
};

test {
    std.testing.refAllDecls(Scanner);
}
