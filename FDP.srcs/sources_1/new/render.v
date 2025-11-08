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

module text_grid_renderer #(
    parameter integer FONT_SCALE = 2,
    parameter integer MAX_DATA   = 32
) (
    input  wire [           12:0] pixel_index,
    input  wire [            7:0] text_len,
    input  wire [ 8*MAX_DATA-1:0] text_bus,
    input  wire [16*MAX_DATA-1:0] color_bus,    // Color per character
    output reg  [           15:0] pixel_color
);
  localparam integer DISP_W = `DISP_W;
  localparam integer DISP_H = `DISP_H;

  localparam integer GW = 5 * FONT_SCALE;
  localparam integer GH = 7 * FONT_SCALE;
  localparam integer CELL_W = GW + FONT_SCALE;
  localparam integer CELL_H = GH + FONT_SCALE;
  localparam integer COLS = DISP_W / CELL_W;
  localparam integer ROWS = DISP_H / CELL_H;

  wire [ 6:0] x = pixel_index % DISP_W;
  wire [ 6:0] y = pixel_index / DISP_W;

  wire [ 2:0] cx = x / CELL_W;
  wire [ 2:0] cy = y / CELL_H;
  wire [ 6:0] ox = cx * CELL_W;
  wire [ 6:0] oy = cy * CELL_H;

  wire [ 7:0] idx = cy * COLS + cx;

  reg  [ 7:0] ascii;
  reg  [15:0] char_color;
  always @* begin
    ascii = 8'h20;
    char_color = `C_TEXT;  // Default text color
    if ((idx < text_len) && (idx < MAX_DATA)) begin
      ascii = text_bus[8*idx+:8];
      char_color = color_bus[16*idx+:16];
    end
  end

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

  always @* begin
    pixel_color = `C_BG;
    if (glyph_on) pixel_color = char_color;  // Use per-character color
  end
endmodule

module text_oled #(
    parameter integer FONT_SCALE = 2,
    parameter integer MAX_DATA   = 32
) (
    input  wire                   clk_pix,
    input  wire                   rst,
    input  wire [            7:0] text_len,
    input  wire [ 8*MAX_DATA-1:0] text_bus,
    input  wire [16*MAX_DATA-1:0] color_bus,  // Color input
    output wire [            7:0] oled_out
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
      .text_len(text_len),
      .color_bus(color_bus)
  );
  oled u_oled (
      .clk_6p25m  (clk_pix),
      .rst        (rst),
      .pixel_color(pixel_color),
      .oled_out   (oled_out),
      .pixel_index(pixel_index)
  );
endmodule
