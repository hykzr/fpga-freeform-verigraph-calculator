`include "constants.vh"

module oled (
    input clk_6p25m,
    input rst,
    input [15:0] pixel_color,
    output [7:0] oled_out,  // assign to JA or JB or JC
    output [12:0] pixel_index
);
  Oled_Display oled1 (
      .clk(clk_6p25m),
      .reset(rst),
      .frame_begin(),
      .sending_pixels(),
      .sample_pixel(),
      .pixel_index(pixel_index),
      .pixel_data(pixel_color),
      .cs(oled_out[0]),
      .sdin(oled_out[1]),
      .sclk(oled_out[3]),
      .d_cn(oled_out[4]),
      .resn(oled_out[5]),
      .vccen(oled_out[6]),
      .pmoden(oled_out[7])
  );
endmodule

module keypad_renderer #(
    parameter integer FONT_SCALE = 2,
    parameter integer GRID_ROWS = 4,
    parameter integer GRID_COLS = 4,
    parameter [8*GRID_ROWS*GRID_COLS-1:0] KB_LAYOUT = {"0C=+", "123-", "456*", "789/"}
) (
    input  wire       clk_pix,    // 6.25 MHz OLED pixel clock
    input  wire       rst,        // active-high reset
    input  wire [2:0] focus_row,  // from input_core
    input  wire [2:0] focus_col,  // from input_core
    output wire [7:0] oled_out    // hook to JB[7:0] (or JA/JC)
);
  // ---- Derived geometry ----
  localparam integer CELL_W = `DISP_W / GRID_COLS;
  localparam integer CELL_H = `DISP_H / GRID_ROWS;

  // ---- x,y from pixel_index ----
  wire [6:0] x = pixel_index % `DISP_W;
  wire [6:0] y = pixel_index / `DISP_W;
  wire [12:0] pixel_index;
  wire [15:0] pixel_color;

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

  // ---- Token -> label (up to 3 chars), no need for emit here ----
  wire [23:0] label_bytes;  // [7:0]=char0 (left), [15:8]=char1, [23:16]=char2
  wire [ 2:0] label_len;  // 0..3
  key_token_codec CODEC (
      .key_token(cell_token),
      .label_bytes(label_bytes),
      .label_len(label_len),
      .emit_bytes(),
      .emit_len(),
      .is_clear(),
      .is_equals()
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

  // ---- Up to 3 glyphs side-by-side ----
  wire [7:0] ch0 = label_bytes[7:0];
  wire [7:0] ch1 = label_bytes[15:8];
  wire [7:0] ch2 = label_bytes[23:16];

  wire glyph0_on, glyph1_on, glyph2_on;

  glyph_blitter #(
      .FONT_SCALE(FONT_SCALE)
  ) GLY0 (
      .x    (x),
      .y    (y),
      .gx   (gx0),
      .gy   (gy),
      .ascii(ch0),       // pass full 8-bit (supports PI/SQRT tokens)
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

  // Only enable glyphs 0..label_len-1
  wire gl_on = ((label_len > 0) && glyph0_on) |
               ((label_len > 1) && glyph1_on) |
               ((label_len > 2) && glyph2_on);

  // ---- Compose ----
  reg [15:0] px;
  always @* begin
    px = `C_BG;
    if (in_cell) px = `C_BTN;
    if (is_focus && in_cell) px = `C_FOCUS;
    if (border_on) px = `C_BORDER;
    if (gl_on) px = `C_TEXT;  // text on top
  end

  oled u_oled (
      .clk_6p25m  (clk_pix),
      .rst        (rst),
      .pixel_color(px),
      .oled_out   (oled_out),
      .pixel_index(pixel_index)
  );
endmodule

module text_grid_renderer #(
    parameter integer FONT_SCALE = 2,  // 1,2,3,...
    parameter integer MAX_DATA   = 32  // must be >= COLS*ROWS
) (
    input  wire [          12:0] pixel_index,  // from oled wrapper
    input  wire [           7:0] text_len,     // 0..MAX_DATA
    input  wire [8*MAX_DATA-1:0] text_bus,     // byte i at [8*i +: 8]
    output reg  [          15:0] pixel_color
);
  // ---- Derived geometry (from constants + params) ----
  localparam integer DISP_W = `DISP_W;
  localparam integer DISP_H = `DISP_H;

  localparam integer GW = 5 * FONT_SCALE;
  localparam integer GH = 7 * FONT_SCALE;
  localparam integer CELL_W = GW + FONT_SCALE;  // e.g., 10+2=12
  localparam integer CELL_H = GH + FONT_SCALE;  // e.g., 14+2=16
  localparam integer COLS = DISP_W / CELL_W;  // 96/12=8
  localparam integer ROWS = DISP_H / CELL_H;  // 64/16=4

  // ---- Current pixel (x,y) ----
  wire [6:0] x = pixel_index % DISP_W;
  wire [6:0] y = pixel_index / DISP_W;

  // ---- Which text cell? ----
  wire [2:0] cx = x / CELL_W;  // 0..COLS-1 (fits in 3 bits for COLS<=8)
  wire [2:0] cy = y / CELL_H;  // 0..ROWS-1
  wire [6:0] ox = cx * CELL_W;  // cell origin X
  wire [6:0] oy = cy * CELL_H;  // cell origin Y

  // ---- Linear index into text (row-major) ----
  wire [7:0] idx = cy * COLS + cx;  // up to 31 with default params

  // ---- Pick ASCII for this cell ----
  reg  [7:0] ascii;
  always @* begin
    ascii = 8'h20;  // space by default
    if ((idx < text_len) && (idx < MAX_DATA)) ascii = text_bus[8*idx+:8];
  end

  // ---- Glyph placement: center inside the cell ----
  wire [6:0] gx = ox + (CELL_W - GW) / 2;
  wire [6:0] gy = oy + (CELL_H - GH) / 2;

  wire glyph_on;
  glyph_blitter #(
      .FONT_SCALE(FONT_SCALE)
  ) u_g (
      .x(x),
      .y(y),
      .gx(gx),
      .gy(gy),
      .ascii(ascii),
      .on(glyph_on)
  );

  // ---- Compose color: background vs text ----
  always @* begin
    pixel_color = `C_BG;
    if (glyph_on) pixel_color = `C_TEXT;
  end
endmodule

module text_oled #(
    parameter integer FONT_SCALE = 2,
    parameter integer MAX_DATA   = 32
) (
    input  wire                  clk_pix,   // 6.25 MHz OLED pixel clock
    input  wire                  rst,       // active-high reset
    input  wire [           7:0] text_len,  // 0..MAX_DATA
    input  wire [8*MAX_DATA-1:0] text_bus,  // byte i at [8*i +: 8]
    output wire [           7:0] oled_out   // hook to JB[7:0] (or JA/JC)
);
  wire [12:0] pixel_index;
  wire [15:0] pixel_color;
  text_grid_renderer #(
      .FONT_SCALE(FONT_SCALE),
      .MAX_DATA  (MAX_DATA)
  ) tgr (
      .pixel_index(pixel_index),
      .pixel_color(pixel_color),
      .text_bus(text_bus),
      .text_len(text_len)
  );
  oled u_oled (
      .clk_6p25m  (clk_pix),
      .rst        (rst),
      .pixel_color(pixel_color),
      .oled_out   (oled_out),
      .pixel_index(pixel_index)
  );
endmodule
