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
    output wire        RsTx,

    inout wire PS2Clk,
    inout wire PS2Data
);
  localparam BAUD_RATE = 115200;
  localparam MAX_DATA = 32;

  wire rst = sw[15];
  wire mode_zoom = sw[14];
  wire button_for_graph = sw[13];
  wire [1:0] kb_select = sw[1:0];

  wire clk_25M, clk_6p25M, clk_1k;
  clock_divider clkgen (
      .clk100M(clk),
      .clk_25M(clk_25M),
      .clk_6p25M(clk_6p25M),
      .clk_1k(clk_1k)
  );

  // ========== Button Navigation (original) ==========
  wire btn_up_p, btn_down_p, btn_left_p, btn_right_p, btn_confirm_p;
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
      .up_p(btn_up_p),
      .down_p(btn_down_p),
      .left_p(btn_left_p),
      .right_p(btn_right_p),
      .confirm_p(btn_confirm_p)
  );

  // ========== PS/2 Mouse Setup ==========
  wire [6:0] mouse_x;
  wire [5:0] mouse_y;
  wire [3:0] mouse_z;
  wire mouse_left, mouse_middle, mouse_right;
  wire [15:0] debug_led_mouse;

  mouse_wrapper mouse_wrap (
      .clk(clk),
      .rst(rst),
      .ps2_clk(PS2Clk),
      .ps2_data(PS2Data),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_z(mouse_z),
      .mouse_left(mouse_left),
      .mouse_middle(mouse_middle),
      .mouse_right(mouse_right),
      .mouse_new_event()
  );

  // Debug LED shows mouse status and keypad status
  assign debug_led_mouse[15]   = mouse_left;  // 1 = graph mode
  assign debug_led_mouse[14]   = mouse_right;  // Left mouse button
  assign debug_led_mouse[13]   = mouse_middle;  // New mouse data
  assign debug_led_mouse[12:6] = mouse_x[6:0];  // Mouse X position
  assign debug_led_mouse[5:0]  = mouse_y[5:0];  // Mouse Y position

  // ========== Graph Interface ==========
  wire               graph_start;
  wire signed [31:0] graph_x_q16_16;
  wire signed [31:0] graph_y_q16_16;
  wire               graph_y_valid;
  wire               graph_y_ready;
  wire               graph_mode;
  wire        [15:0] debug_led_input;

  // ========== Student Input with Mouse Support ==========
  student_input #(
      .CLK_HZ(100_000_000),
      .BAUD_RATE(BAUD_RATE),
      .MAX_DATA(MAX_DATA)
  ) U_INPUT (
      .clk(clk),
      .rst(rst),
      .kb_sel(kb_select),
      // Button controls (for graph and keypad)
      .up_p(~button_for_graph & btn_up_p),
      .down_p(~button_for_graph & btn_down_p),
      .left_p(~button_for_graph & btn_left_p),
      .right_p(~button_for_graph & btn_right_p),
      .confirm_p(~button_for_graph & btn_confirm_p),
      // Mouse (passed through directly)
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_left(mouse_left),
      // UART and graph
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

  graph_plotter_core u_core (
      .clk_100(clk),
      .clk_pix(clk_6p25M),
      .rst(rst | ~graph_mode),
      .left_p(button_for_graph & btn_left_p),
      .right_p(button_for_graph & btn_right_p),
      .up_p(button_for_graph & btn_up_p),
      .down_p(button_for_graph & btn_down_p),
      .confirm_p(button_for_graph & btn_confirm_p),
      .mode_zoom(mode_zoom),
      .start_calc(graph_start),
      .x_q16_16(graph_x_q16_16),
      .y_ready(graph_y_ready & graph_mode),
      .y_valid(graph_y_valid & graph_mode),
      .y_q16_16(graph_y_q16_16),
      .oled_out(JC)
  );

  assign led = debug_led_mouse;
endmodule
