# Expanse

## Overview

Expanse is a macro-assembly language for Subleq. It may also be used with other word-based OISCs.

## Subleq

Subleq is a computer architecture with only a single instruction. The instruction takes 3 arguments
`A, B, C` and does not have an opcode associated with it. The instruction does the following
(as pseudocode):
```
memory[B] = memory[B] - memory[A]

if (memory[B] <= 0) {
  goto C
} else {
  goto PC + 3
}
```
The next 3 words in memory are then taken as the next 3 arguments.

## General Syntax

- Each Subleq argument must either have a comma or EOF after it.
- Tabs are not allowed.
- Extra whitespace is allowed.
- Names must be of the form `/[_A-Za-z][_A-Za-z0-9]*/`
- Names must not conflict
- Numbers can be written in either binary, octal, decimal, or hex.
  - A base may be specified for non-decimal with a prefix of `0b`, `0o`, or `0x` respectively.
- Blocks are surrounded with curly brackets

## Macros

Macros are pieces of code that can be used multiple times. Macros are defined with the `macro`
keyword followed by the name of the macro, and a comma separated list of parameters in parentheses.
The body of the macro follows as a block. A single trailing comma is optionally allowed directly
after the final parameter. Macro definitions may optionally be preceded with the `pub` keyword, 
which allows it to be imported to an external file. Macros may only be defined at the top level of
a file.

```
macro foo(param1, param2) {
  ; code goes here
}
```
A macro that is defined may be used at any point after the definition.
```
foo(arg1, arg2)
```

### Parameters

Macro parameters are implicitly integers unless specified as an array. To specify that a parameter
is an array, prefix the name with square brackets. This will infer the length when the macro is
called. To specify a specific length, enclose that length in the square brackets. Lengths must be
greater than 0. A previous parameter to the macro may be used to define the length. Elements of an
array may then be accessed with the `!` operator. To access elements of an array without a known
length you may use a `for` which is then unrolled when compiling. To get the length of an array as a value, you may
precede the array with `#`.

```
macro foo([3]bar, baz, []qud) {
  bar!0, bar!1, baz

  for (value in qud) {
    value, value + 1, #qud * 3
  }
}
```

### Arguments

Macro arguments may be an integer or an array of integers. The length of each argument must match
the length of the corresponding parameter.

### Return

You may exit a macro with the `return` keyword at any point within a macro. You may optionally
follow it with a value to return that value.

## Arrays

### Construction
Arrays may be constructed with a comma separated list of values surrounded by square brackets. To
specify consecutive values in an array, you may use range syntax. A range is specified by writing
the first integer followed by two periods and then the second integer. If the first value is less
than the second, then the range is increasing. If the first value is greater, then the range is
decreasing. Ranges are inclusive of both ends. If an array is one of the values in the list, then
the array is expanded out, as if it was a list of its components.

An array of characters may be constructed by surrounding them in double quotes. Characters are
treated as integers encoded as UTF-8 unless passed to a pseudo-macro. To embed an 8 bit integer,
it must be written in hex and prefixed with `\x` instead of `0x`. `\"`, `\\`, `\n`, and `\t` can be
used to insert a quote, a backslash, a newline, or a tab respectively. Strings must be contained
within a single line.

```
[0, 1, 2]
[0..2]
"Hello, world!\n"
["Hello, world!\n", [2..0]]
["This is a workaround\n",
"for multi-line strings.]
```

### Usage
Arrays may be passed to macros and used in compile-time control flow and diagnostics. To access the
length of an array as prefix it with a `#`. Arrays may also be used in code, in which case they are
expanded out, as if it was a list of its components. To access an integer within the array, follow
it with square brackets with an integer inside.

## Variables and Constants

Variables and constants are named values. A constant is defined with the `const` keyword followed 
by the name of the constant, and an equals sign followed by a value. A variable is defined the same
way but with the `var` keyword. Top-level variable and constant definitions may optionally be be
preceded with the `pub` keyword to allow it to be imported to an external file. A constant may not
be redefined within its scope. A warning is issued for unused variables and constants that are not
marked as `pub`.
```
const foo = 0
const bar = foo           ; equivalent to 0
const arr1 = [foo, 1, 2]  ; equivalent to [0, 1, 2]
const arr2 = [arr1, 3]    ; equivalent to [0, 1, 2, 3]
```

### Built-in constants

- `MAX_FILESIZE`
  - Largest allowed output file size, defaults to `MAX_UWORD`
  - Must not be greater than `MAX_UWORD`
  - Must be greater than 0
- `MAX_ADDRESS`
  - Largest allowed address in the output, defaults to `MAX_FILESIZE`
  - Must not be greater than `MAX_UWORD`
  - Must be greater than 0
  - When in raw mode, this must equal `MAX_FILESIZE`
- `MAX_DEPTH`
  - Maximum depth of macro calls, defaults to 1000
  - If this depth is exceeded an error will occur
- `DIAGNOSTIC_BASE`
  - The base that numbers are printed in from diagnostic pseudo-macros, defaults to 16.
  - The possible values are 2, 8, 10, and 16
  - If not equal to 10, diagnostic pseudo-macros will prefix numbers with the relevant base prefix
- `BUILD_MODE`
  - Specifies what build mode the Subleq program is being built in, defaults to raw mode
  - 0 if building in raw mode
  - 1 if building in relocation mode
- `ENDIAN`
  - Specifies the endianness of the Subleq program, defaults to little endian
  - 0 if little endian
  - 1 is big endian
- `WORD_SIZE`
  - Word size in bytes, defaults to 2
  - Must be a value from 1 through 8
  - If an integer that can not fit in a word would be written to the output, an error will occur
- `MAX_UWORD`
  - Largest unsigned value that can fit in a word
- `MAX_WORD`
  - Largest signed value that can fit in a word
- `MIN_WORD`
  - Smallest signed value that can fit in a word

### Built-in variables

Built-in variables may not be manually reassigned, instead they take a different value depending on
their location within the program.

- `\`
  - Address of the next word, if used as a macro argument then the address points to after the macro
- `$`
  - Address of the current word, if used as a macro argument then the address points to the start of the macro
- `$$`
  - Address of the start of the current section

## Expressions

Expressions allow you to perform arithmetic on integers and arrays. An expression consisting of an
integer and an array performs the operation element-wise on each integer in the array. An
expression consisting of two arrays performs the operation pairwise by index. If an expression
consists of two arrays, then they must be the same length. Unary operations on an array return an
array of the same length. Boolean operations always return an integer. The preceding expression
rules do not apply if stated otherwise. Expressions act at compile time and do not dereference.
Expressions allow for the following operations:

- `A + B`
  - Addition
- `A - B`
  - Subtraction
- `A * B`
  - Multiplication
- `A / B`
  - Integer division
  - Rounds towards 0
  - If `B` is equal to 0, an error will occur
- `A % B`
  - Modulo
  - Result is positive if the sign of `A` and `B` are the same, otherwise the result is negative
  - If `B` is equal to 0, an error will occur
- `A << B`
  - Left shift
- `A >> B`
  - Right shift
- `~A`
  - Bitwise not
- `A & B`
  - Bitwise and
- `A | B`
  - Bitwise or
- `A ^ B`
  - Bitwise xor
- `A == B`
  - 1 if `A == B`, 0 otherwise
- `A != B`
  - 1 if `A != B`, 0 otherwise
- `A > B`
  - 1 if `A > B`, 0 otherwise
- `A >= B`
  - 1 if `A >= B`, 0 otherwise
- `A < B`
  - 1 if `A < B`, 0 otherwise
- `A <= B`
  - 1 if `A <= B`, 0 otherwise
- `A has B`
  - 1 if `A` contains `B`, 0 otherwise
  - `A` must be an array
  - If `B` is an array, all elements of `A` must be equal to an element of `B`
- `A ! B`
  - Array access
  - `A` must be an array
  - If `B` is an integer, returns the integer at the index `B`
  - If `B` is an array, returns an array containing the integers at all indices listed in `B`
  - Indices must not exceed the bounds of the array

Operations are left-associative. Parentheses may be used to group operations and increase
their precedence. The order of operations is as follows:
- Parentheses
- Array access
- Not
- Multiplication/Integer division/Modulo
- Addition/Subtraction
- Left shift/Right shift
- And
- Or/Xor
- Has
- Equality/Comparison

## Labels and Sections

Labels are named integers used to mark an address. Labels can be used in any place an integer can.
A label is created by a name followed by a colon. Labels may not be redefined. Labels are only
defined in the scope they were created in. Labels are equivalent to a constant equal to the current
address.

```
foo:

bar(foo)
```

A section specifies a new address for compilation to continue at. Negative addresses are not
allowed. Sections last until the start of the next section. The program starts with an unnamed
section at address 0. To create a section, write a `@` followed by an integer preceding a colon. The
`@` may optionally be preceeded by a name to create a label at that address. If multiple sections'
regions conflict, later sections take priority over earlier ones and a warning is issued. When
building in relocation mode, section information is emitted to the outputted binary.

```
foo @ 0x100:      ; sets current address to 256 and creates a label there

@ $ + 64:         ; sets current address to the current address + 64
```

## Control Flow

### For

For loops allow you to repeat a block of code for each integer in an array. For loops are created
with the `for` keyword followed by parentheses containing an array. The array may optionally be
preceded by a name followed by the `in` keyword. The code to be looped over follows as a block. The
block is executed once for each element in the array. If a name is specified, it declares a constant
local to each iteration of the loop equal to the current integer in the given array.

```
for (i in [1,3,5,7,9]) {
  ; ...
}
```

To loop over a range, specify the range in the array.

```
for ([0..5]) {
  ; loops 6 times without keeping track of the current iteration number
}
```

The `break` keyword will exit the innermost loop. The `continue` keyword will skip the rest of the
current loop iteration.

### If

If statements allow you to conditionally execute a block of code. If statements are created with the
`if` keyword followed by parentheses containing the condition. The code to be conditionally executed
follows as a block. The block is only executed if the condition is non-zero. The condition must be
an integer.

```
if (2 == 3) {
  ; does not execute
}
```

An `elseif` or `else` statement may be placed after an `if` or `elseif` statement. These statements
will only activate if all previous conditions in the chain were false. An `elseif` statement is
created with the `elseif` keyword followed by parentheses containing the condition and a block.
An `else` statement is created with the `else` keyword followed by a block. Both `elseif` and
`else` statements may not be created unless they directly follow an `if` or `elseif` statement.

```
if (2 == 3) {
  ; does not execute
} elseif (2 == 2) {
  ; executes
} else {
  ; does not execute
}
```

## Pseudo-Macros

Pseudo-macros are called like macros but can accomplish things not otherwise possible. Characters
in arrays are treated as bytes.

### Error

The `error` pseudo-macro allows you to halt compilation with a message. It takes a single array
argument of indeterminate length. The array is then printed and compilation halts. Numbers in the
array are printed according to `DIAGNOSTIC_BASE`.

```
error("error message")
```

### Info

The `info` pseudo-macro allows you to print a message. It takes a single array of indeterminate
length. The array is then printed. Numbers in the array are printed according to `DIAGNOSTIC_BASE`.

```
info("message")
```

## Import

The `import` keyword allows you to include constants, variables, and macros that are marked as
`pub` from another file. It is followed by an array consisting only of strings denoting the path to
the file to import, relative to the current file. The array is then followed by the `as` keyword
and the name to give the import. To access the definitions, write the name that the import was
given followed by a period and then the name of the the variable, constant, or macro. When a file
is imported, compile-time code in that file is run without writing anything to the output.

```
import "foo" as bar
bar.baz
```

## Comments

Comments are preceded by a two forward slashes and last until the end of the line.

```
// this is a comment
```

## Other Notes

- Compile-time integers are signed 64 bit.
