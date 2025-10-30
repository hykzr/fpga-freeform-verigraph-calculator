`timescale 1ns / 1ps
`include "constants.vh"

//////////////////////////////////////////////////////////////////////////////////
//
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME:
//  STUDENT B NAME:
//  STUDENT C NAME:
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

    // NEW: OLED on JA header for graph demo
    output wire [7:0] JA,

    // Existing PMODs / display for your other modules
    output wire [7:0] JB,
    output wire [7:0] JC
);
  localparam BAUD_RATE = 115200;
  localparam MAX_DATA = 32;
  wire rst = sw[15];
  // ---------------- Clocks ----------------
  wire clk_25M, clk_6p25M, clk_1k;
  clock_divider clkgen (
      .clk100M(clk),
      .clk_25M(clk_25M),
      .clk_6p25M(clk_6p25M),
      .clk_1k(clk_1k)
  );
  //   wire input_rx, input_tx, compute_rx, compute_tx;
  //   assign input_rx   = compute_tx;
  //   assign compute_rx = input_tx;
  //   wire kb_select = sw[0];
  //   wire [15:0] debug_led_input, debug_led_output;
  //   student_input #(
  //       .CLK_HZ(100_000_000),
  //       .BAUD_RATE(BAUD_RATE),
  //       .MAX_DATA(MAX_DATA)
  //   ) U_INPUT (
  //       .clk(clk),
  //       .rst(rst),
  //       .kb_sel(kb_select),
  //       .btnU(btnU),
  //       .btnD(btnD),
  //       .btnL(btnL),
  //       .btnR(btnR),
  //       .btnC(btnC),
  //       .rx(input_rx),
  //       .tx(input_tx),
  //       .clk_pix(clk_6p25M),
  //       .oled_keypad_out(JC[7:0]),
  //       .oled_text_out(JB[7:0]),
  //       .debug_led(debug_led_input)
  //   );

  //   student_compute #(
  //       .CLK_HZ(100_000_000),
  //       .BAUD_RATE(BAUD_RATE),
  //       .MAX_DATA(MAX_DATA)
  //   ) U_OUTPUT (
  //       .clk(clk),
  //       .rst(rst),
  //       .rx(compute_rx),
  //       .tx(compute_tx),
  //       .debug_led(debug_led_output)
  //   );
  // assign led = debug_led_input;


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

  // Use sw[14] to choose mode: 0=pan (use arrows), 1=zoom (Up=zoom in, Down=zoom out)
  wire mode_zoom = sw[14];
  wire move_up = up_p & ~mode_zoom;
  wire move_down = down_p & ~mode_zoom;
  wire move_left = left_p & ~mode_zoom;
  wire move_right = right_p & ~mode_zoom;
  wire zoom_in_p = mode_zoom & up_p;
  wire zoom_out_p = mode_zoom & down_p;
  wire clear_pulse = confirm_p;  // BtnC pulse clears drawn points

  // OLED scan signals for the graph demo (SECOND OLED on JA)
  wire [12:0] graph_pixel_index;
  wire [15:0] graph_pixel_colour;
  wire [7:0] graph_oled_bus;

  // Graph demo top (self-contained; uses dummy y = 2x + 1)
  graph_plotter_top_demo2x1 U_GRAPH (
      .clk_100(clk),
      .rst(rst),

      .p_left(move_left),
      .p_right(move_right),
      .p_up(move_up),
      .p_down(move_down),
      .p_zoom_in(zoom_in_p),
      .p_zoom_out(zoom_out_p),
      .p_clear_curves(clear_pulse),

      .pixel_index (graph_pixel_index),
      .pixel_colour(graph_pixel_colour)
  );

  // Drive a dedicated OLED on JA[7:0]
  oled U_OLED_GRAPH (
      .clk_6p25m(clk_6p25M),
      .rst(rst),
      .pixel_color(graph_pixel_colour),
      .oled_out(graph_oled_bus),     // wire to JA
      .pixel_index(graph_pixel_index)
  );

  assign JA[7:0] = graph_oled_bus;

endmodule
