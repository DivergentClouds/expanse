const std = @import("std");
const Scanner = @import("Scanner.zig");
const common = @import("common.zig");

const Parser = @This();

result: ParseResult,

token_iterator: common.ScalarIterator(Scanner.Token),

arena: std.heap.ArenaAllocator,
allocator: std.mem.Allocator,

is_child: bool,

pub const Node = struct {
    kind: NodeKind,
    literal: union(enum) {
        integer: i64,
        character: u8,
        none,
    },
    children: std.ArrayList(Node),
};

pub const NodeKind = enum {
    /// root of program
    root,

    /// root of an import
    imported_root,

    /// for operations with 2 arguments
    binary_expression,

    /// for operations with 1 argument
    unary_operation,
};

pub const ParseResult = union(enum) {
    ast: Node,
    errors: std.ArrayList(ParseErrorWithPayload),
};

const NodeOrError = union(enum) {
    node: Node,
    err: ParseErrorWithPayload,
};

pub const ParseErrorWithPayload = common.ErrorWithPayload(
    Scanner.Token,
    ParseError,
);

pub const ParseError = error{
    UnexpectedLiteral,
    NoEofToken,
};

pub fn init(
    allocator: std.mem.Allocator,
    tokens: []const Scanner.Token,
) Parser {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const child_allocator = arena.allocator();

    return .{
        .arena = arena,
        .allocator = child_allocator,
        .result = .{
            .ast = .{
                .kind = .root,
                .literal = .none,
                .children = .init(child_allocator),
            },
        },
        .token_iterator = common.scalarIterator(Scanner.Token, tokens),
        .is_child = false,
    };
}

fn initImport(
    parent: Parser,
    tokens: []const Scanner.Token,
) Parser {
    return .{
        .arena = parent.arena,
        .allocator = parent.allocator,
        .result = .{
            .ast = Node{
                .kind = .imported_root,
                .children = .init(parent.allocator),
            },
        },
        .token_iterator = common.scalarIterator(Scanner.Token, tokens),
        .is_child = true,
    };
}

pub fn deinit(parser: Parser) void {
    parser.arena.deinit();
}

pub fn parse(parser: *Parser) !ParseResult {
    std.debug.assert(std.meta.activeTag(parser.result) == .ast);

    var success = true;

    var token = parser.token_iterator.next() orelse
        return parser.result;

    ast_builder: switch (try parser.parseToken(token)) {
        .node => |node| {
            if (success) {
                try parser.result.ast.children.append(node);
            }

            if (token.kind == .eof) {
                break :ast_builder;
            } else {
                token = parser.token_iterator.next() orelse {
                    continue :ast_builder NodeOrError{
                        .err = .{
                            .err = ParseError.NoEofToken,
                            .payload = token,
                        },
                    };
                };

                continue :ast_builder try parser.parseToken(token);
            }
        },
        .err => |err| {
            if (success) {
                success = false;

                parser.result = .{
                    .errors = .init(parser.allocator),
                };
            }
            try parser.result.errors.append(err);

            token = parser.token_iterator.next() orelse {
                continue :ast_builder NodeOrError{
                    .err = .{
                        .err = ParseError.NoEofToken,
                        .payload = token,
                    },
                };
            };

            continue :ast_builder try parser.parseToken(token);
        },
    }

    return parser.result;
}

fn parseToken(parser: *Parser, token: Scanner.Token) !NodeOrError {
    const lookahead = parser.token_iterator.peek();

    var node: Node = undefined;
    _ = &node; // autofix

    switch (token.kind) {
        .integer => {
            if (std.mem.indexOfScalar(
                Scanner.TokenKind,
                &integer_lhs_operators,
                lookahead,
            ) != null) {}
        },
        else => std.debug.panic(
            "TODO: implement {s}\n",
            .{@tagName(token.kind)},
        ),
    }
}

fn parseBinaryOp(parser: *Parser, operation: Scanner.TokenKind, lhs: Node) Node {
    _ = parser; // autofix
    _ = operation; // autofix
    _ = lhs; // autofix
}

const integer_lhs_operators = [_]Scanner.TokenKind{
    .plus,
    .minus,
    .times,
    .divide,
    .modulo,
    .left_shift,
    .right_shift,
    .bit_not,
    .bit_and,
    .bit_or,
    .double_equals,
    .not_equals,
    .greater,
    .greater_or_equal,
    .less,
    .less_or_equal,
};

const operators = [_]Scanner.TokenKind{
    .has,
    .access,
} ++ integer_lhs_operators;

test {
    std.testing.refAllDecls(Parser);
}
