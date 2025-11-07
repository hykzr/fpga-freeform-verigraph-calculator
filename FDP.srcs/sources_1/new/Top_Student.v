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

    inout wire PS2Clk,
    inout wire PS2Data
);
  localparam MAX_DATA = 32;
  localparam OLED_ROTATE_180 = 1;

  wire rst = sw[15];
  wire mode_zoom = sw[14];
  wire button_for_graph = sw[13];

  wire clk_25M, clk_6p25M, clk_1k;
  clock_divider clkgen (
      .clk100M(clk),
      .clk_25M(clk_25M),
      .clk_6p25M(clk_6p25M),
      .clk_1k(clk_1k)
  );

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

  wire [6:0] mouse_x;
  wire [5:0] mouse_y;
  wire [3:0] mouse_z;
  wire mouse_left, mouse_middle, mouse_right;

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

  wire mouse_mode;
  mouse_mode_switch mode_sw (
      .clk(clk),
      .rst(rst),
      .mouse_middle(mouse_middle),
      .mouse_mode(mouse_mode)
  );

  wire               mouse_for_keypad = ~mouse_mode;
  wire               mouse_for_graph = mouse_mode;

  wire               graph_start;
  wire signed [31:0] graph_x_q16_16;
  wire signed [31:0] graph_y_q16_16;
  wire               graph_y_valid;
  wire               graph_y_ready;
  wire               graph_mode;
  wire        [15:0] debug_led_input;

  student_input #(
      .CLK_HZ(100_000_000),
      .MAX_DATA(MAX_DATA),
      .OLED_ROTATE_180(OLED_ROTATE_180)
  ) U_INPUT (
      .clk(clk),
      .rst(rst),
      .up_p(~button_for_graph & btn_up_p),
      .down_p(~button_for_graph & btn_down_p),
      .left_p(~button_for_graph & btn_left_p),
      .right_p(~button_for_graph & btn_right_p),
      .confirm_p(~button_for_graph & btn_confirm_p),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_z(mouse_z),
      .mouse_left(mouse_left & mouse_for_keypad),
      .mouse_active(mouse_for_keypad),
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
      .rst(rst),
      .graph_mode(graph_mode),
      .left_p(button_for_graph & btn_left_p),
      .right_p(button_for_graph & btn_right_p),
      .up_p(button_for_graph & btn_up_p),
      .down_p(button_for_graph & btn_down_p),
      .confirm_p(button_for_graph & btn_confirm_p),
      .mode_zoom(mode_zoom),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_z(mouse_z),
      .mouse_left(mouse_left & mouse_for_graph),
      .mouse_active(mouse_for_graph),
      .start_calc(graph_start),
      .x_q16_16(graph_x_q16_16),
      .y_ready(graph_y_ready & graph_mode),
      .y_valid(graph_y_valid & graph_mode),
      .y_q16_16(graph_y_q16_16),
      .oled_out(JC)
  );

  assign led[15:4] = debug_led_input[15:4];
  assign led[3:0]  = mouse_z;
endmodule
