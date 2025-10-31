`timescale 1ns / 1ps
`include "constants.vh"

//////////////////////////////////////////////////////////////////////////////////
//
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME:
//  STUDENT B NAME:
//  STUDENT C NAME:
//
//  MODIFIED: Direct port connections instead of UART for single-board design
//
//////////////////////////////////////////////////////////////////////////////////

module Top_Student (
    input  wire        clk,
    input  wire        btnL,
    input  wire        btnU,
    input  wire        btnD,
    input  wire        btnR,
    input  wire        btnC,
    input  wire [15:0] sw,
    output wire [15:0] led,
    output wire [ 7:0] JA,
    output wire [ 7:0] JB,
    output wire [ 7:0] JC
);
  localparam MAX_DATA = 32;

  wire rst = sw[15];
  wire mode_zoom = sw[14];
  wire button_for_graph = sw[13];
  wire led_for_output = sw[12];
  wire kb_select = sw[0];

  wire clk_25M, clk_6p25M, clk_1k;
  clock_divider clkgen (
      .clk100M(clk),
      .clk_25M(clk_25M),
      .clk_6p25M(clk_6p25M),
      .clk_1k(clk_1k)
  );

  wire up_p, down_p, left_p, right_p, confirm_p;
  nav_keys #(
      .CLK_HZ(100_000_000),
      .DB_MS(20),
      .RPT_START_MS(500),
      .RPT_MS(60),
      .ACTIVE_LOW(0)
  ) U_NAV (
      .clk(clk),
      .rst(rst),
      .btnU(btnU),
      .btnD(btnD),
      .btnL(btnL),
      .btnR(btnR),
      .btnC(btnC),
      .up_p(up_p),
      .down_p(down_p),
      .left_p(left_p),
      .right_p(right_p),
      .confirm_p(confirm_p)
  );

  // MODIFIED: Direct connections between input and compute (no UART)
  wire                  compute_start;
  wire                  compute_clear;
  wire [           7:0] compute_len;
  wire [8*MAX_DATA-1:0] compute_bus;
  wire                  result_valid;
  wire [           7:0] result_len;
  wire [8*MAX_DATA-1:0] result_bus;

  wire [15:0] debug_led_input, debug_led_output;

  student_input #(
      .CLK_HZ  (100_000_000),
      .MAX_DATA(MAX_DATA)
  ) U_INPUT (
      .clk(clk),
      .rst(rst),
      .kb_sel(kb_select),
      .up_p(~button_for_graph & up_p),
      .down_p(~button_for_graph & down_p),
      .left_p(~button_for_graph & left_p),
      .right_p(~button_for_graph & right_p),
      .confirm_p(~button_for_graph & confirm_p),

      // Direct compute interface
      .compute_start(compute_start),
      .compute_clear(compute_clear),
      .compute_len(compute_len),
      .compute_bus(compute_bus),
      .result_valid(result_valid),
      .result_len(result_len),
      .result_bus(result_bus),

      .clk_pix(clk_6p25M),
      .oled_keypad_out(JA),
      .oled_text_out(JB),
      .debug_led(debug_led_input)
  );

  student_compute_direct #(
      .CLK_HZ  (100_000_000),
      .MAX_DATA(MAX_DATA)
  ) U_OUTPUT (
      .clk(clk),
      .rst(rst),

      // Direct compute interface
      .compute_start(compute_start),
      .compute_clear(compute_clear),
      .compute_len(compute_len),
      .compute_bus(compute_bus),
      .result_valid(result_valid),
      .result_len(result_len),
      .result_bus(result_bus),

      .debug_led(debug_led_output)
  );

  assign led = led_for_output ? debug_led_input : debug_led_output;

  graph_plotter_top_demo2x1 U_GRAPH (
      .clk_100(clk),
      .clk_pix(clk_6p25M),
      .rst(rst),
      .left_p(button_for_graph & left_p),
      .right_p(button_for_graph & right_p),
      .up_p(button_for_graph & up_p),
      .down_p(button_for_graph & down_p),
      .confirm_p(button_for_graph & confirm_p),
      .mode_zoom(mode_zoom),
      .oled_out(JC)
  );

endmodule
