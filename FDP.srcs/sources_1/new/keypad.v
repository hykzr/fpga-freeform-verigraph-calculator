`timescale 1ns / 1ps
`include "constants.vh"

module focus_grid #(
    parameter ROWS = 4,
    COLS = 4
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       up_p,
    input  wire       down_p,
    input  wire       left_p,
    input  wire       right_p,
    input  wire       confirm_p,
    output reg  [2:0] row,
    output reg  [2:0] col,
    output reg        select_pulse
);
  always @(posedge clk) begin
    if (rst) begin
      row <= 0;
      col <= 0;
      select_pulse <= 1'b0;
    end else begin
      select_pulse <= confirm_p;
      if (up_p && row > 0) row <= row - 1;
      if (down_p && row < ROWS - 1) row <= row + 1;
      if (left_p && col > 0) col <= col - 1;
      if (right_p && col < COLS - 1) col <= col + 1;
    end
  end
endmodule

module keypad_map #(
    parameter integer GRID_ROWS = 4,
    parameter integer GRID_COLS = 4,
    parameter [8*GRID_ROWS*GRID_COLS-1:0] KB_LAYOUT = {
      "0C=+", "123-", "456*", "789/"
    }  // row3..row0 (Verilog concatenation is msb..lsb)
) (
    input  wire [2:0] row,
    input  wire [2:0] col,
    output reg  [7:0] ascii,
    output reg        is_equals,
    output reg        is_clear
);
  localparam integer N = GRID_ROWS * GRID_COLS;

  wire [5:0] idx = row * GRID_COLS + col;  // 0..15
  always @* begin
    // slice byte i (LSB-first in this packing scheme)
    ascii     = KB_LAYOUT[8*idx+:8];
    is_equals = (ascii == "=");
    is_clear  = (ascii == "C");
  end
endmodule

module key_token_codec (
    input wire [7:0] key_token,  // from keypad_map (1 byte)

    output reg [8*3-1:0] label_bytes,  // [7:0]=first char to draw, then [15:8], [23:16]
    output reg [    2:0] label_len,    // 0..3

    output reg [8*4-1:0] emit_bytes,  // [7:0]=first byte to emit, then [15:8], [23:16], [31:24]
    output reg [    2:0] emit_len,    // 0..4

    output wire is_clear,  // convenience flags
    output wire is_equals
);
  // defaults: nothing
  always @* begin
    label_bytes = 24'h00_00_00;
    label_len   = 3'd0;
    emit_bytes  = 32'h00_00_00_00;
    emit_len    = 3'd0;

    // ASCII printable → pass-through (digits, ops, parens, '.', '%', 'e', etc.)
    if (key_token >= 8'd32 && key_token <= 8'd126) begin
      label_bytes = {16'h0000, key_token}; // single-char label
      label_len   = 3'd1;
      emit_bytes  = {24'h000000, key_token}; // single-byte emit
      emit_len    = 3'd1;
    end

    // Non-ASCII specials override here
    case (key_token)
      // ===== functions: lowercase labels, emit with '(' =====
      `SIN_KEY: begin
        label_bytes = {"n","i","s"};  // "sin" (LSB-first)
        label_len   = 3'd3;
        emit_bytes  = {"(", "n","i","s"}; // "sin("
        emit_len    = 3'd4;
      end
      `COS_KEY: begin
        label_bytes = {"s","o","c"};  // "cos"
        label_len   = 3'd3;
        emit_bytes  = {"(", "s","o","c"}; // "cos("
        emit_len    = 3'd4;
      end
      `TAN_KEY: begin
        label_bytes = {"n","a","t"};  // "tan"
        label_len   = 3'd3;
        emit_bytes  = {"(", "n","a","t"}; // "tan("
        emit_len    = 3'd4;
      end
      `LN_KEY: begin
        label_bytes = {8'h00,"n","l"}; // "ln"
        label_len   = 3'd2;
        emit_bytes  = {8'h00, "(", "n","l"}; // "ln("
        emit_len    = 3'd3;
      end
      `LOG_KEY: begin
        label_bytes = {"g","o","l"}; // "log"
        label_len   = 3'd3;
        emit_bytes  = {"(", "g","o","l"}; // "log("
        emit_len    = 3'd4;
      end

      // ===== constants/symbols: draw the glyph, emit token (NOT text) =====
      `PI_KEY: begin
        label_bytes = {16'h0000, `PI_KEY}; // single-glyph label
        label_len   = 3'd1;
        emit_bytes  = {24'h000000, `PI_KEY}; // emit token
        emit_len    = 3'd1;
      end
      `SQRT_KEY: begin
        label_bytes = {16'h0000, `SQRT_KEY}; // single-glyph label
        label_len   = 3'd1;
        emit_bytes  = {24'h000000, `SQRT_KEY}; // emit token (NOT "sqrt(")
        emit_len    = 3'd1;
      end

      default: ;  // keep whatever the ASCII default set
    endcase
  end

  assign is_clear  = (key_token == "C");
  assign is_equals = (key_token == "=");
endmodule

module keypad_ctrl #(
    parameter integer GRID_ROWS = 4,
    parameter integer GRID_COLS = 4,
    // One byte per key (ASCII or *_KEY). Keep the SAME packing you already use
    // with your current keypad_map (idx = row*GRID_COLS + col; LSB-first slice).
    parameter [8*GRID_ROWS*GRID_COLS-1:0] KB_LAYOUT = {
      "0C=+", "123-", "456*", "789/"  // example; row3..row0
    }
) (
    input wire clk,
    input wire rst,
    // navigation pulses
    input wire up_p,
    input wire down_p,
    input wire left_p,
    input wire right_p,
    input wire confirm_p,

    // focus state (optional but handy)
    output wire [2:0] focus_row,
    output wire [2:0] focus_col,
    output wire       select_pulse,

    // key token (debug/optional)
    output wire [7:0] key_token,

    // render info for the focused key
    output wire [23:0] label_bytes,
    output wire [ 2:0] label_len,

    // emit info when confirm happens
    output wire [31:0] emit_bytes,
    output wire [ 2:0] emit_len,

    // convenience flags
    output wire is_equals,
    output wire is_clear
);
  // 1) Navigation
  focus_grid #(
      .ROWS(GRID_ROWS),
      .COLS(GRID_COLS)
  ) u_focus (
      .clk(clk),
      .rst(rst),
      .up_p(up_p),
      .down_p(down_p),
      .left_p(left_p),
      .right_p(right_p),
      .confirm_p(confirm_p),
      .row(focus_row),
      .col(focus_col),
      .select_pulse(select_pulse)
  );

  // 2) Map focused row/col to 1-byte token (ASCII or *_KEY)
  wire [7:0] ascii_token;
  wire _eq_unused, _clr_unused;

  keypad_map #(
      .GRID_ROWS(GRID_ROWS),
      .GRID_COLS(GRID_COLS),
      .KB_LAYOUT(KB_LAYOUT)
  ) u_kmap (
      .row(focus_row),
      .col(focus_col),
      .ascii(ascii_token),
      .is_equals(_eq_unused),
      .is_clear(_clr_unused)
  );

  assign key_token = ascii_token;

  // 3) Token → {label, emit}
  key_token_codec u_codec (
      .key_token(ascii_token),
      .label_bytes(label_bytes),
      .label_len(label_len),
      .emit_bytes(emit_bytes),
      .emit_len(emit_len),
      .is_clear(is_clear),
      .is_equals(is_equals)
  );

endmodule

module keypad_widget #(
    parameter integer FONT_SCALE = 2,
    parameter integer GRID_ROWS = 4,
    parameter integer GRID_COLS = 4,
    // One byte per key: ASCII or *_KEY token. Packing matches keypad_map (idx=row*GRID_COLS+col)
    parameter [8*GRID_ROWS*GRID_COLS-1:0] KB_LAYOUT = {"0C=+", "123-", "456*", "789/"}
) (
    input wire clk,  // system clock (logic)
    input wire rst,

    // navigation pulses (already debounced/repeated)
    input wire up_p,
    input wire down_p,
    input wire left_p,
    input wire right_p,
    input wire confirm_p,

    // pixel render side
    input  wire       clk_pix,  // pixel clock for your OLED pipeline
    output wire [7:0] oled_out,

    // emit-to-buffer interface (append path)
    output wire        tb_append,      // pulse: append emit_bytes
    output wire [ 2:0] tb_append_len,  // 0..4
    output wire [31:0] tb_append_bus,  // bytes LSB-first
    output wire        tb_clear,       // pulse when 'C' pressed
    output wire        is_equal,       // pulse when '=' pressed

    // (optional) expose focus for other UI uses
    output wire [2:0] focus_row,
    output wire [2:0] focus_col
);
  // -------- Focus --------
  wire select_pulse;
  focus_grid #(
      .ROWS(GRID_ROWS),
      .COLS(GRID_COLS)
  ) u_focus (
      .clk(clk),
      .rst(rst),
      .up_p(up_p),
      .down_p(down_p),
      .left_p(left_p),
      .right_p(right_p),
      .confirm_p(confirm_p),
      .row(focus_row),
      .col(focus_col),
      .select_pulse(select_pulse)
  );

  // -------- Map focused cell → token --------
  wire [7:0] token;
  wire unused_eq, unused_clr;
  keypad_map #(
      .GRID_ROWS(GRID_ROWS),
      .GRID_COLS(GRID_COLS),
      .KB_LAYOUT(KB_LAYOUT)
  ) u_map (
      .row(focus_row),
      .col(focus_col),
      .ascii(token),
      .is_equals(unused_eq),
      .is_clear(unused_clr)
  );

  // -------- Token → {label, emit} --------
  wire [23:0] label_bytes;
  wire [ 2:0] label_len;
  wire [31:0] emit_bytes;
  wire [ 2:0] emit_len;
  wire k_is_eq, k_is_clr;

  key_token_codec u_codec (
      .key_token(token),
      .label_bytes(label_bytes),
      .label_len(label_len),
      .emit_bytes(emit_bytes),
      .emit_len(emit_len),
      .is_clear(k_is_clr),
      .is_equals(k_is_eq)
  );

  // -------- Emit-to-buffer signals (append/clear/equals) --------
  assign tb_append     = select_pulse && (!k_is_eq) && (!k_is_clr) && (emit_len != 0);
  assign tb_append_len = emit_len;
  assign tb_append_bus = emit_bytes;
  assign tb_clear      = select_pulse && k_is_clr;
  assign is_equal      = select_pulse && k_is_eq;

  // -------- Per-pixel render (uses label mapping for every cell) --------
  // We reuse your renderer that internally calls keypad_map and key_token_codec per cell.
  // It needs only focus for highlight and KB_LAYOUT for tokens.
  keypad_renderer #(
      .FONT_SCALE(FONT_SCALE),
      .GRID_ROWS (GRID_ROWS),
      .GRID_COLS (GRID_COLS),
      .KB_LAYOUT (KB_LAYOUT)
  ) u_rend (
      .clk_pix  (clk_pix),
      .rst      (rst),
      .focus_row(focus_row),
      .focus_col(focus_col),
      .oled_out (oled_out)
  );
endmodule
