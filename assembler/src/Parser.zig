const std = @import("std");
const Token = @import("Scanner.zig").Token;
const common = @import("common.zig");

const Parser = @This();

token_iterator: common.ScalarIterator(Token),

arena: std.heap.ArenaAllocator,
allocator: std.mem.Allocator,

is_child: bool,
is_import: bool,

result: ParseResult,

pub const Node = struct {
    kind: NodeKind,
    literal: union(enum) {
        string: []const u8,
        identifier: []const u8,
        integer: i64,
        none,
    },
    children: ?std.ArrayList(Node),
};

pub const NodeKind = enum {
    /// root node, list of statements
    start,

    // list of statements
    block,

    statement,

    // kinds of statements
    label,
    section,
    declaration,
    import,
    conditional,
    loop,
    flow_changes,
    expression,
    output_expression, // an expression that becomes subleq code

    // kinds of declaration
    const_decl,
    var_decl,
    macro_decl,

    // used by macro_decl
    macro_params,

    // kinds of conditional
    @"if",
    elseif,
    @"else",

    // kinds of flow_changes
    @"return",
    @"break",
    @"continue",

    // kinds of expression
    boolean_or,
    boolean_and,
    comparison,
    has,
    bitwise,
    bitshift,
    additive,
    multiplicative,
    unary,
    array_access,
    call,
    import_access,
    value,

    // kinds of value
    integer,
    string,
    identifier,
    next_word,
    current_word,
    section_start,
    array_def,

    // used by array_def
    range,

    // used by call
    macro_args,
};

pub const ParseResult = union(enum) {
    ast: Node,
    errors: std.ArrayList(ParseErrorWithPayload),
};

const NodeOrError = union(enum) {
    node: Node,
    error_with_payload: ParseErrorWithPayload,
};

pub const ParseErrorWithPayload = common.ErrorWithPayload(
    Token,
    ParseError,
);

pub const ParseError = error{
    UnexpectedLiteral,
    UnfinishedStatement,
};

pub fn init(
    allocator: std.mem.Allocator,
    tokens: []const Token,
    is_import: bool,
) Parser {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const arena_allocator = arena.allocator();

    return .{
        .arena = arena,
        .allocator = arena_allocator,
        .result = .{
            .ast = .{
                .kind = .start,
                .literal = .none,
                .children = .init(arena_allocator),
            },
        },
        .token_iterator = common.scalarIterator(Token, tokens),
        .is_child = false,
        .is_import = is_import,
    };
}

pub fn deinit(parser: Parser) void {
    parser.arena.deinit();
}

pub fn parse(parser: *Parser) !ParseResult {
    std.debug.assert(std.meta.activeTag(parser.result) == .ast);
    var success = true;

    ast_builder: switch (try parser.parseStatement()) {
        .node => |statement| {
            if (success) {
                try parser.result.tokens.append(statement);
            }
            // don't bother freeing the node if !success, we are using an arena
        },
        .error_with_payload => |err| {
            if (success) {
                success = false;

                _ = parser.arena.reset(.retain_capacity);

                parser.result = .{
                    .errors = .init(parser.allocator),
                };
            }
            try parser.result.errors.append(err);

            continue :ast_builder parser.parseStatement() orelse
                break :ast_builder;
        },
    }
}

fn parseStatement(parser: *Parser) !?NodeOrError {
    const current_token = parser.token_iterator.next() orelse
        return null;

    const next_token = parser.token_iterator.peek() orelse
        return .{ .error_with_payload = .{
        .err = ParseError.UnfinishedStatement,
        .payload = current_token,
    } };

    switch (current_token.kind) {
        .identifier => {
            switch (next_token.kind) {
                .colon => return .{ .node = parser.defineLabel(current_token) },
                .at => {
                    return try parser.defineSection();
                },
                else => {
                    // expression
                },
            }
        },
        .@"var" => {},
        .@"const" => {},
        .macro => {},
        .@"pub" => {},
        .import => {},
        .@"if" => {},
        .elseif => {
            // error here, handle elseif when generating if
        },
        .@"else" => {
            // error here, handle else when generating if
        },
        .loop => {},
        .@"return" => {},
        .@"break" => {},
        .@"continue" => {},
        else => {
            // expression
        },
    }
}

/// asserts that this is a valid label
fn defineLabel(parser: *Parser, current_token: Token) Node {
    _ = parser.token_iterator.skip();
    return Node{
        .kind = .label,
        .literal = .{ .identifier = current_token.lexeme },
        .children = null,
    };
}

fn defineSection(parser: *Parser, current_token: Token) !NodeOrError {
    var node: Node = .{
        .kind = .section,
        .literal = .{ .identifier = current_token.lexeme },
        .children = .init(parser.allocator),
    };

    const location = try parser.defineExpression();
    switch (location) {
        .node => |expression| {
            try node.children.?.append(expression);
        },
        .error_with_payload => |err| return err,
    }

    return node;
}

fn defineOutputExpression(parser: *Parser) !NodeOrError {
    const expression_or_err = try parser.defineExpression();

    switch (expression_or_err) {
        .node => |expression| {
            var children: std.ArrayList(Node) = .init(parser.allocator);
            try children.append(expression);

            if (parser.token_iterator.next()) |next_token| {
                if (next_token.kind == .comma) {
                    return .{
                        .node = .{
                            .kind = .output_expression,
                            .literal = .none,
                            .children = children,
                        },
                    };
                } else {
                    return NodeOrError{ .error_with_payload = .{
                        .err = ParseError.ExpectedCommaFoundEof,
                        .payload = next_token,
                    } };
                }
            } else {
                return NodeOrError{ .error_with_payload = .{
                    .err = ParseError.ExpectedCommaFoundEof,
                    .payload = .{},
                } };
            }
        },
        .error_with_payload => return expression_or_err,
    }
}

fn defineExpression(parser: *Parser) !NodeOrError {
    _ = parser; // autofix
    @compileError("TODO");
}

test {
    std.testing.refAllDecls(Parser);
}
