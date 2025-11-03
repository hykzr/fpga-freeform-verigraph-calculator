`timescale 1ns / 1ps
`include "constants.vh"

module focus_grid #(
    parameter ROWS = 4,
    COLS = 4
) (
    input wire clk,
    input wire rst,

    // Button navigation
    input wire up_p,
    input wire down_p,
    input wire left_p,
    input wire right_p,
    input wire confirm_p,

    // Mouse input
    input wire [6:0] mouse_x,    // 0..95 (OLED coords)
    input wire [5:0] mouse_y,    // 0..63 (OLED coords)
    input wire       mouse_left, // Left button state

    output reg [2:0] row,
    output reg [2:0] col,
    output reg       select_pulse
);

  // Calculate cell dimensions
  localparam integer CELL_W = `DISP_W / COLS;
  localparam integer CELL_H = `DISP_H / ROWS;

  // Border thickness (ignore clicks here)
  localparam integer BORDER = 1;

  // Mouse click edge detection
  reg mouse_left_prev;
  wire mouse_click = mouse_left && !mouse_left_prev;

  // Calculate which cell mouse is over
  wire [2:0] mouse_col = mouse_x / CELL_W;
  wire [2:0] mouse_row = mouse_y / CELL_H;

  // Calculate position within cell
  wire [6:0] cell_x = mouse_x - (mouse_col * CELL_W);
  wire [5:0] cell_y = mouse_y - (mouse_row * CELL_H);

  // Check if mouse is NOT on border (with safety bounds check)
  wire in_valid_col = (mouse_col < COLS);
  wire in_valid_row = (mouse_row < ROWS);
  wire not_on_border = (cell_x >= BORDER) && (cell_x < CELL_W - BORDER) &&
                       (cell_y >= BORDER) && (cell_y < CELL_H - BORDER);
  wire valid_click = mouse_click && in_valid_col && in_valid_row && not_on_border;

  always @(posedge clk) begin
    if (rst) begin
      row <= 0;
      col <= 0;
      select_pulse <= 1'b0;
      mouse_left_prev <= 1'b0;
    end else begin
      // Update mouse button history
      mouse_left_prev <= mouse_left;

      // Default: button confirm
      select_pulse <= confirm_p;

      // Mouse click takes priority
      if (valid_click) begin
        // Set focus to clicked cell and trigger
        row <= mouse_row;
        col <= mouse_col;
        select_pulse <= 1'b1;
      end else begin
        // Normal button navigation (only if no valid click)
        if (up_p && row > 0) row <= row - 1;
        if (down_p && row < ROWS - 1) row <= row + 1;
        if (left_p && col > 0) col <= col - 1;
        if (right_p && col < COLS - 1) col <= col + 1;
      end
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

    output reg [8*5-1:0] label_bytes,  // [7:0]=first char to draw, then [15:8]... up to 5 chars
    output reg [    2:0] label_len,    // 0..5

    output reg [8*6-1:0] emit_bytes,  // [7:0]=first byte to emit, then [15:8]... up to 6 bytes
    output reg [    2:0] emit_len,    // 0..6

    output wire is_clear,  // convenience flags
    output wire is_equals,
    output wire is_back  // backspace key
);
  // defaults: nothing
  always @* begin
    label_bytes = 40'h00_00_00_00_00;
    label_len   = 3'd0;
    emit_bytes  = 48'h00_00_00_00_00_00;
    emit_len    = 3'd0;

    // ASCII printable → pass-through (digits, ops, parens, '.', '%', 'e', etc.)
    if (key_token >= 8'd32 && key_token <= 8'd126) begin
      label_bytes = {32'h00000000, key_token}; // single-char label
      label_len   = 3'd1;
      emit_bytes  = {40'h0000000000, key_token}; // single-byte emit
      emit_len    = 3'd1;
    end

    // Non-ASCII specials override here
    case (key_token)
      // ===== Page 2 functions: lowercase labels, emit with '(' =====
      `SIN_KEY: begin
        label_bytes = {16'h0000, "n","i","s"};  // "sin"
        label_len   = 3'd3;
        emit_bytes  = {16'h0000, "(", "n","i","s"}; // "sin("
        emit_len    = 3'd4;
      end
      `COS_KEY: begin
        label_bytes = {16'h0000, "s","o","c"};  // "cos"
        label_len   = 3'd3;
        emit_bytes  = {16'h0000, "(", "s","o","c"}; // "cos("
        emit_len    = 3'd4;
      end
      `TAN_KEY: begin
        label_bytes = {16'h0000, "n","a","t"};  // "tan"
        label_len   = 3'd3;
        emit_bytes  = {16'h0000, "(", "n","a","t"}; // "tan("
        emit_len    = 3'd4;
      end
      `LN_KEY: begin
        label_bytes = {24'h000000,"n","l"}; // "ln"
        label_len   = 3'd2;
        emit_bytes  = {24'h000000, "(", "n","l"}; // "ln("
        emit_len    = 3'd3;
      end
      `LOG_KEY: begin
        label_bytes = {16'h0000, "g","o","l"}; // "log"
        label_len   = 3'd3;
        emit_bytes  = {16'h0000, "(", "g","o","l"}; // "log("
        emit_len    = 3'd4;
      end

      // ===== Page 3 functions: display math notation, emit function names =====
      `ABS_KEY: begin
        label_bytes = {16'h0000, "|","x","|"};  // |x|
        label_len   = 3'd3;
        emit_bytes  = {16'h0000, "(", "s","b","a"}; // "abs("
        emit_len    = 3'd4;
      end
      `FLOOR_KEY: begin
        label_bytes = {8'h00, `FLOOR_R_KEY, "x", `FLOOR_L_KEY};  // ⌊x⌋
        label_len   = 3'd3;
        emit_bytes  = {"(", "r","o","o","l","f"}; // "floor("
        emit_len    = 3'd6;
      end
      `CEIL_KEY: begin
        label_bytes = {8'h00, `CEIL_R_KEY, "x", `CEIL_L_KEY};  // ⌈x⌉
        label_len   = 3'd4;
        emit_bytes  = {8'h00, "(", "l","i","e","c"}; // "ceil("
        emit_len    = 3'd5;
      end
      `ROUND_KEY: begin
        label_bytes = "dnuor";  // "round"
        label_len   = 3'd5;
        emit_bytes  = {"(", "d","n","u","o","r"}; // "round("
        emit_len    = 3'd6;
      end
      `MIN_KEY: begin
        label_bytes = {16'h0000, "n","i","m"};  // "min"
        label_len   = 3'd3;
        emit_bytes  = {16'h0000, "(", "n","i","m"}; // "min("
        emit_len    = 3'd4;
      end
      `MAX_KEY: begin
        label_bytes = {16'h0000, "x","a","m"};  // "max"
        label_len   = 3'd3;
        emit_bytes  = {16'h0000, "(", "x","a","m"}; // "max("
        emit_len    = 3'd4;
      end
      `POW_KEY: begin
        label_bytes = {16'h0000, "w","o","p"};  // "pow"
        label_len   = 3'd3;
        emit_bytes  = {16'h0000, "(", "w","o","p"}; // "pow("
        emit_len    = 3'd4;
      end

      // ===== constants/symbols: draw the glyph, emit token (NOT text) =====
      `PI_KEY: begin
        label_bytes = {32'h00000000, `PI_KEY}; // single-glyph label
        label_len   = 3'd1;
        emit_bytes  = {40'h0000000000, `PI_KEY}; // emit token
        emit_len    = 3'd1;
      end
      `SQRT_KEY: begin
        label_bytes = {32'h00000000, `SQRT_KEY}; // single-glyph label
        label_len   = 3'd1;
        emit_bytes  = {40'h0000000000, `SQRT_KEY}; // emit token (NOT "sqrt(")
        emit_len    = 3'd1;
      end

      // ===== Special keys =====
      `BACK_KEY: begin
        label_bytes = {32'h00000000, `BACK_KEY}; // special glyph for backspace
        label_len   = 3'd1;
        emit_bytes  = 48'h000000000000; // no emit (handled separately)
        emit_len    = 3'd0;
      end

      default: ;  // keep whatever the ASCII default set
    endcase
  end

  assign is_clear  = (key_token == "C");
  assign is_equals = (key_token == "=");
  assign is_back   = (key_token == `BACK_KEY);
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

    // Mouse input
    input wire [6:0] mouse_x,
    input wire [5:0] mouse_y,
    input wire       mouse_left,

    // pixel render side
    input  wire       clk_pix,  // pixel clock for your OLED pipeline
    output wire [7:0] oled_out,

    // emit-to-buffer interface (append path)
    output wire        tb_append,      // pulse: append emit_bytes
    output wire [ 2:0] tb_append_len,  // 0..6
    output wire [47:0] tb_append_bus,  // bytes LSB-first (6 bytes)
    output wire        tb_clear,       // pulse when 'C' pressed
    output wire        tb_back,        // pulse when backspace pressed
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
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_left(mouse_left),
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
  wire [39:0] label_bytes;
  wire [ 2:0] label_len;
  wire [47:0] emit_bytes;
  wire [ 2:0] emit_len;
  wire k_is_eq, k_is_clr, k_is_back;

  key_token_codec u_codec (
      .key_token(token),
      .label_bytes(label_bytes),
      .label_len(label_len),
      .emit_bytes(emit_bytes),
      .emit_len(emit_len),
      .is_clear(k_is_clr),
      .is_equals(k_is_eq),
      .is_back(k_is_back)
  );

  // -------- Emit-to-buffer signals (append/clear/equals) --------
  assign tb_append = select_pulse && (!k_is_eq) && (!k_is_clr) && (!k_is_back) && (emit_len != 0);
  assign tb_append_len = emit_len;
  assign tb_append_bus = emit_bytes;
  assign tb_clear = select_pulse && k_is_clr;
  assign tb_back = select_pulse && k_is_back;
  assign is_equal = select_pulse && k_is_eq;

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
      .mouse_x  (mouse_x),
      .mouse_y  (mouse_y),
      .oled_out (oled_out)
  );
endmodule

module keypad_renderer #(
    parameter integer FONT_SCALE = 2,
    parameter integer GRID_ROWS = 4,
    parameter integer GRID_COLS = 4,
    parameter [8*GRID_ROWS*GRID_COLS-1:0] KB_LAYOUT = {"0C=+", "123-", "456*", "789/"}
) (
    input wire       clk_pix,    // 6.25 MHz OLED pixel clock
    input wire       rst,        // active-high reset
    input wire [2:0] focus_row,  // from input_core
    input wire [2:0] focus_col,  // from input_core

    // Mouse cursor position
    input wire [6:0] mouse_x,
    input wire [5:0] mouse_y,

    output wire [7:0] oled_out  // hook to JB[7:0] (or JA/JC)
);
  // ---- Derived geometry ----
  localparam integer CELL_W = `DISP_W / GRID_COLS;
  localparam integer CELL_H = `DISP_H / GRID_ROWS;
  // ---- x,y from pixel_index ----
  wire [12:0] pixel_index;
  wire [15:0] pixel_color;
  wire [6:0] x = pixel_index % `DISP_W;
  wire [6:0] y = pixel_index / `DISP_W;
  // ---- Which cell am I in? ----
  wire [2:0] cx = x / CELL_W;  // 0..GRID_COLS-1
  wire [2:0] cy = y / CELL_H;  // 0..GRID_ROWS-1
  wire [6:0] ox = cx * CELL_W;
  wire [6:0] oy = cy * CELL_H;
  // ---- Base layers ----
  wire in_cell = (x >= ox) && (y >= oy) && (x < ox + CELL_W) && (y < oy + CELL_H);
  wire border_on = in_cell && ( y==oy || y==(oy+CELL_H-1) || x==ox || x==(ox+CELL_W-1) );
  wire is_focus = (cx == focus_col) && (cy == focus_row);
  // ---- Get per-cell token (ASCII or *_KEY) from layout ----
  wire [7:0] cell_token;
  keypad_map #(
      .GRID_ROWS(GRID_ROWS),
      .GRID_COLS(GRID_COLS),
      .KB_LAYOUT(KB_LAYOUT)
  ) LAB (
      .row(cy),
      .col(cx),
      .ascii(cell_token),
      .is_equals(),
      .is_clear()
  );
  // ---- Token -> label (up to 5 chars), no need for emit here ----
  wire [39:0] label_bytes;  // [7:0]=char0 (left), [15:8]=char1, ..., [39:32]=char4
  wire [ 2:0] label_len;  // 0..5
  key_token_codec CODEC (
      .key_token(cell_token),
      .label_bytes(label_bytes),
      .label_len(label_len),
      .emit_bytes(),
      .emit_len(),
      .is_clear(),
      .is_equals(),
      .is_back()
  );
  // ---- Glyph group placement (5x7 scaled) ----
  localparam [6:0] GW = 5 * FONT_SCALE;  // glyph width
  localparam [6:0] GH = 7 * FONT_SCALE;  // glyph height
  localparam [6:0] GAP = FONT_SCALE;  // spacing between glyphs
  wire [9:0] group_w_chars = label_len * GW;
  wire [9:0] group_w_gaps = (label_len == 0) ? 10'd0 : (label_len - 1) * GAP;
  wire [9:0] group_w_total = group_w_chars + group_w_gaps;
  wire [6:0] gx0 = ox + (CELL_W - group_w_total[6:0]) / 2;  // leftmost glyph x
  wire [6:0] gy = oy + (CELL_H - GH) / 2;
  // ---- Up to 5 glyphs side-by-side ----
  wire [7:0] ch0 = label_bytes[7:0];
  wire [7:0] ch1 = label_bytes[15:8];
  wire [7:0] ch2 = label_bytes[23:16];
  wire [7:0] ch3 = label_bytes[31:24];
  wire [7:0] ch4 = label_bytes[39:32];
  wire glyph0_on, glyph1_on, glyph2_on, glyph3_on, glyph4_on;
  glyph_blitter #(
      .FONT_SCALE(FONT_SCALE)
  ) GLY0 (
      .x    (x),
      .y    (y),
      .gx   (gx0),
      .gy   (gy),
      .ascii(ch0),       // pass full 8-bit (supports PI/SQRT/bracket tokens)
      .on   (glyph0_on)
  );
  glyph_blitter #(
      .FONT_SCALE(FONT_SCALE)
  ) GLY1 (
      .x(x),
      .y(y),
      .gx(gx0 + GW + GAP),
      .gy(gy),
      .ascii(ch1),
      .on(glyph1_on)
  );
  glyph_blitter #(
      .FONT_SCALE(FONT_SCALE)
  ) GLY2 (
      .x(x),
      .y(y),
      .gx(gx0 + 2 * (GW + GAP)),
      .gy(gy),
      .ascii(ch2),
      .on(glyph2_on)
  );
  glyph_blitter #(
      .FONT_SCALE(FONT_SCALE)
  ) GLY3 (
      .x(x),
      .y(y),
      .gx(gx0 + 3 * (GW + GAP)),
      .gy(gy),
      .ascii(ch3),
      .on(glyph3_on)
  );
  glyph_blitter #(
      .FONT_SCALE(FONT_SCALE)
  ) GLY4 (
      .x(x),
      .y(y),
      .gx(gx0 + 4 * (GW + GAP)),
      .gy(gy),
      .ascii(ch4),
      .on(glyph4_on)
  );
  // Only enable glyphs 0..label_len-1
  wire gl_on = ((label_len > 0) && glyph0_on) |
               ((label_len > 1) && glyph1_on) |
               ((label_len > 2) && glyph2_on) |
               ((label_len > 3) && glyph3_on) |
               ((label_len > 4) && glyph4_on);

  // Mouse cursor (single pixel)
  wire cursor_on = (x == mouse_x) && (y == mouse_y);

  // ---- Compose ----
  reg [15:0] px;
  always @* begin
    px = `C_BG;
    if (in_cell) px = `C_BTN;
    if (is_focus && in_cell) px = `C_FOCUS;
    if (border_on) px = `C_BORDER;
    if (gl_on) px = `C_TEXT;  // text on top
    if (cursor_on) px = 16'hFFFF;  // White pixel for cursor (on top of everything)
  end
  oled u_oled (
      .clk_6p25m  (clk_pix),
      .rst        (rst),
      .pixel_color(px),
      .oled_out   (oled_out),
      .pixel_index(pixel_index)
  );
endmodule
