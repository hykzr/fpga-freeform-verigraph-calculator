// Read (debounced) button pulse record current row and col
module focus_grid #(
    parameter ROWS = 5,
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

  wire [31:0] idx = row * GRID_COLS + col;  // 0..15
  always @* begin
    // slice byte i (LSB-first in this packing scheme)
    ascii     = KB_LAYOUT[8*idx+:8];
    is_equals = (ascii == "=");
    is_clear  = (ascii == "C");
  end
endmodule
