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
    kind: Kind,
    literal: union(enum) {
        string: []const u8,
        identifier: []const u8,
        integer: i64,
        none,
    },
    children: ?std.ArrayListUnmanaged(Node),
};

pub const Kind = enum {
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

    // used by declarations
    @"pub",

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
    errors: std.ArrayListUnmanaged(ParseErrorWithPayload),
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
    ExpectedCommaFoundEof,
    UnexpectedToken,
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
                .children = .empty,
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

                continue :ast_builder try parser.parseStatement() orelse
                    break :ast_builder;
            }
            // don't bother freeing the node if !success, we are using an arena
        },
        .error_with_payload => |err| {
            if (success) {
                success = false;

                _ = parser.arena.reset(.retain_capacity);

                parser.result = .{
                    .errors = .empty,
                };
            }
            try parser.result.errors.append(parser.allocator, err);

            continue :ast_builder try parser.parseStatement() orelse
                break :ast_builder;
        },
    }
}

fn parseStatement(parser: *Parser) !?NodeOrError {
    const current_token = parser.token_iterator.next() orelse
        return null;

    switch (current_token.kind) {
        .identifier => {
            // use peek() and not next() in case the next_token is part of an expression
            const next_token = parser.token_iterator.peek() orelse
                return .{ .error_with_payload = .{
                    .err = ParseError.UnfinishedStatement,
                    .payload = current_token,
                } };

            switch (next_token.kind) {
                .colon => return .{ .node = parser.defineLabel(current_token) },
                .at => {
                    return try parser.defineSection();
                },
                else => {
                    return try parser.defineOutputExpression(current_token);
                },
            }
        },

        .@"const" => {
            return try parser.defineConst();
        },
        .@"var" => {
            return try parser.defineVar();
        },
        .macro => {
            return try parser.defineMacro();
        },
        .@"pub" => {
            return try parser.definePub(current_token);
        },
        .import => {
            return try parser.defineImport(current_token);
        },
        .@"if" => {
            return try parser.defineIf(current_token);
        },
        .elseif, .@"else" => {
            // handle elseif and else when generating if
            return .{
                .error_with_payload = .{
                    .payload = .{
                        .kind = current_token.kind,
                        .lexeme = current_token.lexeme,
                        .literal = current_token.literal,
                        .location = current_token.location,
                    },
                    .err = ParseError.UnexpectedToken,
                },
            };
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
    _ = parser.token_iterator.skip(); // skip the : following the identifier
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

    const location = try parser.defineExpression(null);
    switch (location) {
        .node => |expression| {
            try node.children.?.append(expression);
        },
        .error_with_payload => |err| return err,
    }

    return node;
}

fn definePub(parser: *Parser, current_token: Token) !NodeOrError {
    const new_token = parser.token_iterator.next() orelse
        return .{ .error_with_payload = .{
            .err = ParseError.UnfinishedStatement,
            .payload = current_token,
        } };

    const decl_or_error: NodeOrError = switch (new_token.kind) {
        .@"const" => try parser.defineConst(),
        .@"var" => try parser.defineVar(),
        .macro => try parser.defineMacro(),
        else => return .{
            .error_with_payload = .{
                .err = ParseError.UnexpectedToken,
                .payload = new_token,
            },
        },
    };

    switch (decl_or_error) {
        .node => |node| {
            var children: std.ArrayListUnmanaged(Node) = .initCapacity(parser.allocator, 1);
            children.appendAssumeCapacity(node);

            return .{
                .node = .{
                    .kind = .@"pub",
                    .literal = .none,
                    .children = children,
                },
            };
        },
        .error_with_payload => |error_with_payload| return .{
            .error_with_payload = .{
                .err = error_with_payload.err,
                .payload = new_token,
            },
        },
    }
}

fn defineImport(parser: *Parser, current_token: Token) !NodeOrError {
    const filename_node: Node = switch (try parser.defineExpression(null)) {
        .node => |node| node,
        .error_with_payload => |err| return .{ .error_with_payload = err },
    };

    const as = parser.token_iterator.next() orelse
        return .{
            .error_with_payload = .{
                .payload = current_token,
                .err = ParseError.UnfinishedStatement,
            },
        };

    if (as.kind != .as)
        return .{
            .error_with_payload = .{
                .payload = as,
                .err = ParseError.UnexpectedToken,
            },
        };

    const import_identifier = parser.token_iterator.next() orelse
        return .{
            .error_with_payload = .{
                .payload = current_token,
                .err = ParseError.UnfinishedStatement,
            },
        };

    if (import_identifier.kind != .identifier)
        return .{
            .error_with_payload = .{
                .payload = import_identifier,
                .err = ParseError.UnexpectedToken,
            },
        };

    const identifier_node: Node = .{
        .kind = .identifier,
        .literal = import_identifier.literal,
        .children = null,
    };

    var children: std.ArrayListUnmanaged(Node) = .initCapacity(parser.allocator, 2);
    children.appendAssumeCapacity(identifier_node);
    children.appendAssumeCapacity(filename_node);

    return .{
        .node = .{
            .kind = .import,
            .literal = .node,
            .children = children,
        },
    };
}

fn defineOutputExpression(parser: *Parser, initial_token: ?Token) !NodeOrError {
    const expression_or_err = try parser.defineExpression(initial_token);

    switch (expression_or_err) {
        .node => |expression| {
            var children: std.ArrayListUnmanaged(Node) = .initCapacity(parser.allocator, 1);
            try children.appendAssumeCapacity(parser.allocator, expression);

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
                    return .{ .error_with_payload = .{
                        .err = ParseError.UnexpectedToken,
                        .payload = next_token,
                    } };
                }
            } else {
                return .{
                    .error_with_payload = .{
                        .err = ParseError.ExpectedCommaFoundEof,
                        .payload = parser.token_iterator.previous() orelse
                            // this would only be reachable if there were no previous tokens,
                            // but we just parsed an expression which contained at least 1 token
                            // since it returned a node
                            unreachable,
                    },
                };
            }
        },
        .error_with_payload => return expression_or_err,
    }
}

fn defineExpression(parser: *Parser, initial_token: ?Token) !NodeOrError {
    _ = parser;
    _ = initial_token;
}

test {
    std.testing.refAllDecls(Parser);
}
