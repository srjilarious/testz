; zkdocs simplified highlights — stripped of #lua-match? predicates
; so tree-sitter can run without a custom predicate evaluator.

; Keywords
[
  "asm"
  "defer"
  "errdefer"
  "test"
  "error"
  "const"
  "var"
] @keyword

[
  "struct"
  "union"
  "enum"
  "opaque"
] @keyword.type

"fn" @keyword.function

[
  "and"
  "or"
  "orelse"
] @keyword.operator

"return" @keyword.return

[
  "if"
  "else"
  "switch"
] @keyword.conditional

[
  "for"
  "while"
  "break"
  "continue"
] @keyword.repeat

[
  "usingnamespace"
  "export"
] @keyword.import

[
  "try"
  "catch"
] @keyword.exception

[
  "volatile"
  "allowzero"
  "noalias"
  "addrspace"
  "align"
  "callconv"
  "linksection"
  "pub"
  "inline"
  "noinline"
  "extern"
  "comptime"
  "packed"
  "threadlocal"
] @keyword.modifier

; Built-in functions: @import, @intCast, @ptrCast, …
(builtin_identifier) @function.builtin

; Built-in types: u8, i32, bool, anytype, …
(builtin_type) @type.builtin

; Built-in constants
[
  "null"
  "unreachable"
  "undefined"
] @constant.builtin

; Type aliases from struct/enum/union/opaque literals (structural, no predicate)
(variable_declaration
  (identifier) @type
  "="
  [
    (struct_declaration)
    (enum_declaration)
    (union_declaration)
    (opaque_declaration)
  ])

; Function declarations
(function_declaration
  name: (identifier) @function)

; Function calls
(call_expression
  function: (identifier) @function.call)

(call_expression
  function: (field_expression
    member: (identifier) @function.call))

; Literals
(string)           @string
(multiline_string) @string
(integer)          @number
(float)            @number.float
(boolean)          @boolean
(character)        @character
(escape_sequence)  @string.escape

; Comments
(comment) @comment
