`timescale 1ns / 1ps
`include "constants.vh"

//////////////////////////////////////////////////////////////////////////////////
//
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME:
//  STUDENT B NAME:
//  STUDENT C NAME:
//
//  UART TESTING BRANCH: Connect input to laptop for compute verification
//  - student_compute removed
//  - RsRx/RsTx exposed for laptop connection
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
    output wire [ 7:0] JC,

    // UART to laptop (for testing)
    input  wire RsRx,  // Connect to laptop TX
    output wire RsTx   // Connect to laptop RX
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

  wire [15:0] debug_led_input;

  // student_input connected directly to laptop via UART
  student_input #(
      .CLK_HZ(100_000_000),
      .BAUD_RATE(BAUD_RATE),
      .MAX_DATA(MAX_DATA)
  ) U_INPUT (
      .clk            (clk),
      .rst            (rst),
      .kb_sel         (kb_select),
      .up_p           (~button_for_graph & up_p),
      .down_p         (~button_for_graph & down_p),
      .left_p         (~button_for_graph & left_p),
      .right_p        (~button_for_graph & right_p),
      .confirm_p      (~button_for_graph & confirm_p),
      .rx             (RsRx),                           // From laptop
      .tx             (RsTx),                           // To laptop
      .clk_pix        (clk_6p25M),
      .oled_keypad_out(JA),
      .oled_text_out  (JB),
      .debug_led      (debug_led_input)
  );

  assign led = debug_led_input;

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
