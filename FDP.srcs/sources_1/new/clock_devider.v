`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 29.09.2025 09:20:14
// Design Name:
// Module Name: clock_devider
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module clock_div #(
    parameter INPUT_FREQ  = 100_000_000,   // 100 MHz default
    parameter OUTPUT_FREQ = 1_000_000      // 1 MHz default
  )(
    input  wire clk_in,
    output reg  clk_out = 0
  );

  // Derived half-period count
  localparam integer DIV_COUNT = (INPUT_FREQ / (2 * OUTPUT_FREQ));
  localparam integer COUNTER_BITS = $clog2(DIV_COUNT);

  reg [COUNTER_BITS-1:0] counter = 0;

  always @(posedge clk_in)
  begin
    if (counter == DIV_COUNT - 1)
    begin
      clk_out <= ~clk_out;
      counter <= 0;
    end
    else
    begin
      counter <= counter + 1;
    end
  end
endmodule

module clock_divider(
    input  wire clk100M,
    output wire clk_25M,
    output wire clk_6p25M,
    output wire clk_1k
  );
  // 25 MHz
  clock_div #(.INPUT_FREQ(100_000_000),.OUTPUT_FREQ(25_000_000))
            div25 (.clk_in(clk100M),.clk_out(clk_25M));
  // 6.25 MHz
  clock_div #(
              .INPUT_FREQ(100_000_000),
              .OUTPUT_FREQ(6_250_000)
            ) div6p25 (
              .clk_in(clk100M),
              .clk_out(clk_6p25M)
            );
  // 1 kHz
  clock_div #(
              .INPUT_FREQ(100_000_000),
              .OUTPUT_FREQ(1_000)
            ) div1k (
              .clk_in(clk100M),
              .clk_out(clk_1k)
            );

endmodule
