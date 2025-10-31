`timescale 1ns / 1ps
`include "constants.vh"

module Top_Student (
    input  wire        clk,
    input  wire        btnL,
    btnU,
    btnD,
    btnR,
    btnC,
    input  wire [15:0] sw,
    output wire [15:0] led,
    output wire [ 7:0] JA,
    JB,
    JC,
    input  wire        RsRx,
    output wire        RsTx
);
  localparam BAUD_RATE = 115200;
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

  // Graph interface
  wire               graph_start;
  wire signed [31:0] graph_x_q16_16;
  wire signed [31:0] graph_y_q16_16;
  wire               graph_y_valid;
  wire               graph_y_ready;
  wire               graph_mode;
  wire        [15:0] debug_led_input;

  student_input #(
      .CLK_HZ(100_000_000),
      .BAUD_RATE(BAUD_RATE),
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
      .rx(RsRx),
      .tx(RsTx),
      .graph_start(graph_start),
      .graph_x_q16_16(graph_x_q16_16),
      .graph_y_q16_16(graph_y_q16_16),
      .graph_y_valid(graph_y_valid),
      .graph_y_ready(graph_y_ready),
      .graph_mode(graph_mode),
      .clk_pix(clk_6p25M),
      .oled_keypad_out(JA),
      .oled_text_out(JB),
      .debug_led(debug_led_input)
  );

  assign led = debug_led_input;

  graph_plotter_core u_core (
      .clk_100(clk),
      .clk_pix(clk_6p25M),
      .rst(rst | ~graph_mode),
      .left_p(button_for_graph & left_p),
      .right_p(button_for_graph & right_p),
      .up_p(button_for_graph & up_p),
      .down_p(button_for_graph & down_p),
      .confirm_p(button_for_graph & confirm_p),
      .mode_zoom(mode_zoom),
      .start_calc(graph_start),
      .x_q16_16(graph_x_q16_16),
      .y_ready(graph_y_ready & graph_mode),
      .y_valid(graph_y_valid & graph_mode),
      .y_q16_16(graph_y_q16_16),
      .oled_out(JC)
  );
endmodule
