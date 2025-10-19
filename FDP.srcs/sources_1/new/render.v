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
    parameter integer FONT_SCALE = 2,  // tweakable
    parameter integer GRID_ROWS = 4,
    parameter integer GRID_COLS = 4,
    parameter [8*GRID_ROWS*GRID_COLS-1:0] KB_LAYOUT = {"0C=+", "123-", "456*", "789/"}
) (
    input  wire        clk_pix,      // kept for timing if you want to register outputs
    input  wire [12:0] pixel_index,
    input  wire [ 2:0] focus_row,
    focus_col,
    output reg  [15:0] pixel_color
);
  // ---- Derived geometry ----
  localparam integer CELL_W = `DISP_W / GRID_COLS;
  localparam integer CELL_H = `DISP_H / GRID_ROWS;

  // Optional sim-time guard (ignored by synth):
  // initial if ((`DISP_W % GRID_COLS)!=0 || (`DISP_H % GRID_ROWS)!=0) $error("Grid does not evenly divide display.");

  // ---- x,y from pixel_index ----
  wire [6:0] x = pixel_index % `DISP_W;
  wire [6:0] y = pixel_index / `DISP_W;

  // ---- Which cell am I in? ----
  wire [2:0] cx = x / CELL_W;  // 0..GRID_COLS-1 (fits here since 4 default)
  wire [2:0] cy = y / CELL_H;  // 0..GRID_ROWS-1
  wire [6:0] ox = cx * CELL_W;
  wire [6:0] oy = cy * CELL_H;

  // ---- Base layers ----
  wire in_cell = (x >= ox) && (y >= oy) && (x < ox + CELL_W) && (y < oy + CELL_H);
  wire border_on = in_cell && ( y==oy || y==(oy+CELL_H-1) || x==ox || x==(ox+CELL_W-1) );
  wire is_focus = (cx == focus_col) && (cy == focus_row);

  // ---- Label from parameterized keypad_map ----
  wire [7:0] label_ascii;
  wire unused_eq, unused_clr;
  keypad_map #(
      .GRID_ROWS(GRID_ROWS),
      .GRID_COLS(GRID_COLS),
      .KB_LAYOUT(KB_LAYOUT)
  ) LAB (
      .row(cy),
      .col(cx),
      .ascii(label_ascii),
      .is_equals(unused_eq),
      .is_clear(unused_clr)
  );

  // ---- Glyph center in cell (5x7) ----
  localparam integer GW = 5 * FONT_SCALE;  // glyph width
  localparam integer GH = 7 * FONT_SCALE;  // glyph height
  wire [6:0] gx = ox + (CELL_W - GW) / 2;
  wire [6:0] gy = oy + (CELL_H - GH) / 2;

  wire glyph_on;
  glyph_blitter #(
      .FONT_SCALE(FONT_SCALE)
  ) GLY (
      .x(x),
      .y(y),
      .gx(gx),
      .gy(gy),
      .ascii({1'b0, label_ascii[6:0]}),
      .on(glyph_on)
  );
  reg [15:0] px;
  // ---- Compose ----
  always @* begin
    px = `C_BG;
    if (in_cell) px = `C_BTN;
    if (is_focus && in_cell) px = `C_FOCUS;
    if (border_on) px = `C_BORDER;
    if (glyph_on) px = `C_TEXT;
    pixel_color = px;
  end
endmodule

module render_keypad #(
    // Tunables; derive cell sizes from constants + grid
    parameter integer FONT_SCALE = 2,
    parameter integer GRID_ROWS = 4,
    parameter integer GRID_COLS = 4,
    // Layout (row-major, 16 chars total). Change here or override at instantiation.
    parameter [8*GRID_ROWS*GRID_COLS-1:0] KB_LAYOUT = {
      "0C=+", "123-", "456*", "789/"
    }  // row3..row0
) (
    input  wire       clk_pix,    // 6.25 MHz OLED pixel clock
    input  wire       rst,        // active-high reset
    input  wire [2:0] focus_row,  // from input_core
    input  wire [2:0] focus_col,  // from input_core
    output wire [7:0] oled_out    // hook to JB[7:0] (or JA/JC)
);
  // Renderer <-> OLED handshake
  wire [12:0] pixel_index;
  wire [15:0] pixel_color;

  // Draw the keypad with highlight
  keypad_renderer #(
      .FONT_SCALE(FONT_SCALE),
      .GRID_ROWS (GRID_ROWS),
      .GRID_COLS (GRID_COLS),
      .KB_LAYOUT (KB_LAYOUT)
  ) u_rend (
      .clk_pix    (clk_pix),
      .pixel_index(pixel_index),
      .focus_row  (focus_row),
      .focus_col  (focus_col),
      .pixel_color(pixel_color)
  );

  // Drive the physical OLED
  oled u_oled (
      .clk_6p25m  (clk_pix),
      .rst        (rst),
      .pixel_color(pixel_color),
      .oled_out   (oled_out),
      .pixel_index(pixel_index)
  );

endmodule
