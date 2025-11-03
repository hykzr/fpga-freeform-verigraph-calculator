`timescale 1ns / 1ps
`include "constants.vh"

// PS/2 Mouse Wrapper
// Wraps MouseCtl (which internally uses Ps2Interface)
// Properly initializes mouse bounds and outputs OLED coordinates
module mouse_wrapper (
    input wire clk,
    input wire rst,

    // PS/2 Hardware pins
    inout wire ps2_clk,
    inout wire ps2_data,

    // Mouse state outputs (OLED coordinates)
    output wire [6:0] mouse_x,         // 0..95 (DISP_W-1)
    output wire [5:0] mouse_y,         // 0..63 (DISP_H-1)
    output wire [3:0] mouse_z,         // Scroll wheel delta
    output wire       mouse_left,      // Left button down
    output wire       mouse_middle,    // Middle button down
    output wire       mouse_right,     // Right button down
    output wire       mouse_new_event  // New mouse data available
);

  // MouseCtl outputs (12-bit internal)
  wire [11:0] mouse_x_internal;
  wire [11:0] mouse_y_internal;

  // Initialization state machine
  // Need to set max_x to DISP_W (96), then max_y to DISP_H (64)
  reg  [ 1:0] init_state;
  reg  [11:0] value_reg;
  reg setmax_x_reg, setmax_y_reg;

  localparam INIT_IDLE = 2'd0;
  localparam INIT_SET_X = 2'd1;
  localparam INIT_SET_Y = 2'd2;
  localparam INIT_DONE = 2'd3;

  always @(posedge clk) begin
    if (rst) begin
      init_state <= INIT_SET_X;
      value_reg <= `DISP_W;  // 96
      setmax_x_reg <= 1'b0;
      setmax_y_reg <= 1'b0;
    end else begin
      case (init_state)
        INIT_SET_X: begin
          value_reg <= `DISP_W;
          setmax_x_reg <= 1'b1;  // Pulse setmax_x
          init_state <= INIT_SET_Y;
        end
        INIT_SET_Y: begin
          value_reg <= `DISP_H;  // 64
          setmax_x_reg <= 1'b0;
          setmax_y_reg <= 1'b1;  // Pulse setmax_y
          init_state <= INIT_DONE;
        end
        INIT_DONE: begin
          setmax_x_reg <= 1'b0;
          setmax_y_reg <= 1'b0;
          // Stay in this state
        end
        default: init_state <= INIT_SET_X;
      endcase
    end
  end

  // Instantiate MouseCtl (entity name is MouseCtl, not Mouse_Control)
  MouseCtl mouse_ctrl (
      .clk(clk),
      .rst(rst),
      .ps2_clk(ps2_clk),
      .ps2_data(ps2_data),
      .xpos(mouse_x_internal),
      .ypos(mouse_y_internal),
      .zpos(mouse_z),
      .left(mouse_left),
      .middle(mouse_middle),
      .right(mouse_right),
      .new_event(mouse_new_event),
      .value(value_reg),
      .setx(1'b0),
      .sety(1'b0),
      .setmax_x(setmax_x_reg),
      .setmax_y(setmax_y_reg)
  );

  // Clamp and scale to OLED dimensions
  assign mouse_x = (mouse_x_internal >= `DISP_W) ? (`DISP_W - 1) : mouse_x_internal[6:0];
  assign mouse_y = (mouse_y_internal >= `DISP_H) ? (`DISP_H - 1) : mouse_y_internal[5:0];

endmodule
