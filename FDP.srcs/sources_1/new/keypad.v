`timescale 1ns / 1ps
`include "constants.vh"

module focus_grid #(
    parameter ROWS = 4,
    COLS = 4
) (
    input wire clk,
    input wire rst,

    input wire up_p,
    input wire down_p,
    input wire left_p,
    input wire right_p,
    input wire confirm_p,

    input wire [6:0] mouse_x,
    input wire [5:0] mouse_y,
    input wire       mouse_left,

    output reg [2:0] row,
    output reg [2:0] col,
    output reg       select_pulse
);

  localparam integer CELL_W = `DISP_W / COLS;
  localparam integer CELL_H = `DISP_H / ROWS;
  localparam integer BORDER = 1;

  reg mouse_left_prev;
  wire mouse_click = mouse_left && !mouse_left_prev;

  wire [2:0] mouse_col = mouse_x / CELL_W;
  wire [2:0] mouse_row = mouse_y / CELL_H;

  wire [6:0] cell_x = mouse_x - (mouse_col * CELL_W);
  wire [5:0] cell_y = mouse_y - (mouse_row * CELL_H);

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
      mouse_left_prev <= mouse_left;
      select_pulse <= confirm_p;

      if (valid_click) begin
        row <= mouse_row;
        col <= mouse_col;
        select_pulse <= 1'b1;
      end else begin
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
    parameter [8*GRID_ROWS*GRID_COLS-1:0] KB_LAYOUT = {"0C=+", "123-", "456*", "789/"}
) (
    input  wire [2:0] row,
    input  wire [2:0] col,
    output reg  [7:0] ascii,
    output reg        is_equals,
    output reg        is_clear
);
  localparam integer N = GRID_ROWS * GRID_COLS;

  wire [5:0] idx = row * GRID_COLS + col;
  always @* begin
    ascii     = KB_LAYOUT[8*idx+:8];
    is_equals = (ascii == "=");
    is_clear  = (ascii == "C");
  end
endmodule

module key_token_codec (
    input wire [7:0] key_token,

    output reg [8*5-1:0] label_bytes,
    output reg [    2:0] label_len,

    output wire is_clear,
    output wire is_equals,
    output wire is_back
);
  always @* begin
    label_bytes = 40'h00_00_00_00_00;
    label_len   = 3'd0;

    if (key_token >= 8'd32 && key_token <= 8'd126) begin
      label_bytes = {32'h00000000, key_token};
      label_len   = 3'd1;
    end

    case (key_token)
      `SIN_KEY: begin
        label_bytes = {16'h0000, "n", "i", "s"};
        label_len   = 3'd3;
      end
      `COS_KEY: begin
        label_bytes = {16'h0000, "s", "o", "c"};
        label_len   = 3'd3;
      end
      `TAN_KEY: begin
        label_bytes = {16'h0000, "n", "a", "t"};
        label_len   = 3'd3;
      end
      `LN_KEY: begin
        label_bytes = {24'h000000, "n", "l"};
        label_len   = 3'd2;
      end
      `LOG_KEY: begin
        label_bytes = {16'h0000, "g", "o", "l"};
        label_len   = 3'd3;
      end
      `ABS_KEY: begin
        label_bytes = {16'h0000, "|", "x", "|"};
        label_len   = 3'd3;
      end
      `FLOOR_KEY: begin
        label_bytes = {8'h00, `FLOOR_R_KEY, "x", `FLOOR_L_KEY};
        label_len   = 3'd3;
      end
      `CEIL_KEY: begin
        label_bytes = {8'h00, `CEIL_R_KEY, "x", `CEIL_L_KEY};
        label_len   = 3'd4;
      end
      `ROUND_KEY: begin
        label_bytes = "dnuor";
        label_len   = 3'd5;
      end
      `MIN_KEY: begin
        label_bytes = {16'h0000, "n", "i", "m"};
        label_len   = 3'd3;
      end
      `MAX_KEY: begin
        label_bytes = {16'h0000, "x", "a", "m"};
        label_len   = 3'd3;
      end
      `POW_KEY: begin
        label_bytes = {16'h0000, "w", "o", "p"};
        label_len   = 3'd3;
      end
      `PI_KEY: begin
        label_bytes = {32'h00000000, `PI_KEY};
        label_len   = 3'd1;
      end
      `SQRT_KEY: begin
        label_bytes = {32'h00000000, `SQRT_KEY};
        label_len   = 3'd1;
      end
      `BACK_KEY: begin
        label_bytes = {32'h00000000, `BACK_KEY};
        label_len   = 3'd1;
      end

      default: ;
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
    parameter [8*GRID_ROWS*GRID_COLS-1:0] KB_LAYOUT = {"0C=+", "123-", "456*", "789/"}
) (
    input wire clk,
    input wire rst,

    input wire up_p,
    input wire down_p,
    input wire left_p,
    input wire right_p,
    input wire confirm_p,

    input wire [6:0] mouse_x,
    input wire [5:0] mouse_y,
    input wire       mouse_left,
    input wire       mouse_active,

    output wire       tb_append,
    output wire [7:0] tb_append_byte,
    output wire       tb_clear,
    output wire       tb_back,
    output wire       is_equal,

    output wire [2:0] focus_row,
    output wire [2:0] focus_col
);
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

  wire [39:0] label_bytes;
  wire [ 2:0] label_len;
  wire k_is_eq, k_is_clr, k_is_back;

  key_token_codec u_codec (
      .key_token(token),
      .label_bytes(label_bytes),
      .label_len(label_len),
      .is_clear(k_is_clr),
      .is_equals(k_is_eq),
      .is_back(k_is_back)
  );

  assign tb_append = select_pulse && (!k_is_eq) && (!k_is_clr) && (!k_is_back);
  assign tb_append_byte = token;
  assign tb_clear = select_pulse && k_is_clr;
  assign tb_back = select_pulse && k_is_back;
  assign is_equal = select_pulse && k_is_eq;

endmodule

module keypad_renderer #(
    parameter integer FONT_SCALE = 2,
    parameter integer GRID_ROWS = 4,
    parameter integer GRID_COLS = 4,
    parameter [8*GRID_ROWS*GRID_COLS-1:0] KB_LAYOUT = {"0C=+", "123-", "456*", "789/"}
) (
    input wire [12:0] pixel_index,
    input wire [ 2:0] focus_row,
    input wire [ 2:0] focus_col,

    input wire [6:0] mouse_x,
    input wire [5:0] mouse_y,
    input wire       mouse_left,
    input wire       mouse_active,

    output reg [15:0] pixel_color
);
  localparam integer CELL_W = `DISP_W / GRID_COLS;
  localparam integer CELL_H = `DISP_H / GRID_ROWS;
  wire [6:0] x = pixel_index % `DISP_W;
  wire [6:0] y = pixel_index / `DISP_W;
  wire [2:0] cx = x / CELL_W;
  wire [2:0] cy = y / CELL_H;
  wire [6:0] ox = cx * CELL_W;
  wire [6:0] oy = cy * CELL_H;
  wire in_cell = (x >= ox) && (y >= oy) && (x < ox + CELL_W) && (y < oy + CELL_H);
  wire border_on = in_cell && ( y==oy || y==(oy+CELL_H-1) || x==ox || x==(ox+CELL_W-1) );
  wire is_focus = (cx == focus_col) && (cy == focus_row);
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
  wire [39:0] label_bytes;
  wire [ 2:0] label_len;
  key_token_codec CODEC (
      .key_token(cell_token),
      .label_bytes(label_bytes),
      .label_len(label_len),
      .is_clear(),
      .is_equals(),
      .is_back()
  );
  localparam [6:0] GW = 5 * FONT_SCALE;
  localparam [6:0] GH = 7 * FONT_SCALE;
  localparam [6:0] GAP = FONT_SCALE;
  wire [9:0] group_w_chars = label_len * GW;
  wire [9:0] group_w_gaps = (label_len == 0) ? 10'd0 : (label_len - 1) * GAP;
  wire [9:0] group_w_total = group_w_chars + group_w_gaps;
  wire [6:0] gx0 = ox + (CELL_W - group_w_total[6:0]) / 2;
  wire [6:0] gy = oy + (CELL_H - GH) / 2;
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
      .ascii(ch0),
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
  wire gl_on = ((label_len > 0) && glyph0_on) |
               ((label_len > 1) && glyph1_on) |
               ((label_len > 2) && glyph2_on) |
               ((label_len > 3) && glyph3_on) |
               ((label_len > 4) && glyph4_on);

  wire cursor_active;
  wire [15:0] cursor_colour;
  cursor_display cursor (
      .clk(1'b0),
      .pixel_index(pixel_index),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_clicked(mouse_left),
      .mouse_active(mouse_active),
      .cursor_colour(cursor_colour),
      .cursor_active(cursor_active)
  );

  always @* begin
    pixel_color = `C_BG;
    if (in_cell) pixel_color = `C_BTN;
    if (is_focus && in_cell) pixel_color = `C_FOCUS;
    if (border_on) pixel_color = `C_BORDER;
    if (gl_on) pixel_color = `C_TEXT;
    if (cursor_active) pixel_color = cursor_colour & mouse_active;
  end

endmodule
