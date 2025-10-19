`include "constants.vh"

module expr_parser #(
    parameter integer DEPTH = 32,
    parameter integer W     = 32
) (
    input  wire [8*DEPTH-1:0] mem_bus,  // byte i at mem_bus[8*i +: 8]
    input  wire [        5:0] len,      // 0..DEPTH
    output reg  [        2:0] op_code,  // `OP_* macros
    output reg  [      W-1:0] op_a,
    output reg  [      W-1:0] op_b,
    output reg                has_a,
    output reg                has_b,
    output reg  [        3:0] errors
);

  // --------------------------------------------------------------------------
  // Decls (no declarations inside always/loop)
  // --------------------------------------------------------------------------
  integer         i;
  reg             seen_op;
  reg             parsing_b;
  reg             oflow;
  reg     [W-1:0] acc;
  reg     [W-1:0] t;  // temp for multiply-by-10 + add
  reg     [  7:0] c;  // current byte under parse

  function is_digit;
    input [7:0] ch;
    begin
      is_digit = (ch >= "0") && (ch <= "9");
    end
  endfunction

  function [2:0] map_op;
    input [7:0] ch;
    begin
      case (ch)
        "+": map_op = `OP_ADD;
        "-": map_op = `OP_SUB;
        "*": map_op = `OP_MUL;
        "/": map_op = `OP_DIV;
        default: map_op = `OP_NONE;
      endcase
    end
  endfunction
  // --------------------------------------------------------------------------
  // Combinational parse: A [op] B with unsigned base-10 integers
  // --------------------------------------------------------------------------
  always @* begin
    // defaults
    op_code   = `OP_NONE;
    op_a      = {W{1'b0}};
    op_b      = {W{1'b0}};
    has_a     = 1'b0;
    has_b     = 1'b0;
    errors    = `ERR_NONE;
    seen_op   = 1'b0;
    parsing_b = 1'b0;
    oflow     = 1'b0;
    acc       = {W{1'b0}};
    t         = {W{1'b0}};
    c         = 8'h00;

    if (len == 0) begin
      errors = `ERR_EMPTY;
    end else begin
      // IMPORTANT: fixed bound to DEPTH; guard body with (i < len)
      for (i = 0; i < DEPTH; i = i + 1) begin
        if (i < len) begin
          c = mem_bus[8*i+:8];

          if (is_digit(c)) begin
            t = acc * 10;
            if (t < acc) oflow = 1'b1;
            t = t + (c - "0");
            if (t < acc) oflow = 1'b1;
            acc = t;
          end else if (map_op(c) != `OP_NONE) begin
            if (!seen_op) begin
              op_a      = acc;
              has_a     = 1'b1;
              acc       = {W{1'b0}};
              op_code   = map_op(c);
              seen_op   = 1'b1;
              parsing_b = 1'b1;
            end else begin
              errors = errors | `ERR_TOO_MANY_OPS;
            end
          end else if (c != " " && c != "\t") begin
            // ignore other chars for now
          end

        end  // if (i < len)
      end  // for

      // Flush trailing accumulator
      if (parsing_b) begin
        op_b  = acc;
        has_b = 1'b1;  // counts even if B==0; adjust if you require at least one digit
      end else begin
        op_a  = acc;
        has_a = 1'b1;
      end

      if (oflow) errors = errors | `ERR_OVERFLOW;

      // Missing operand checks
      if (op_code == `OP_NONE) begin
        if (!has_a) errors = errors | `ERR_MISSING_OPER;
      end else begin
        if (!has_a || !has_b) errors = errors | `ERR_MISSING_OPER;
      end
    end
  end

endmodule
