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

module cursor_display (
    input clk,
    input [12:0] pixel_index,
    input [6:0] mouse_x,
    input [5:0] mouse_y,
    input mouse_clicked,
    output reg [15:0] cursor_colour,
    output reg cursor_active
);
  localparam SCREEN_WIDTH = 96;
  // Current pixel coordinates - calculated in combinational block
  reg [6:0] pixel_x;
  reg [5:0] pixel_y;
  // Relative position from cursor origin
  reg signed [7:0] rel_x;
  reg signed [6:0] rel_y;
  // Calculate pixel coordinates and relative positions
  always @(*) begin
    pixel_x = pixel_index % SCREEN_WIDTH;
    pixel_y = pixel_index / SCREEN_WIDTH;
    rel_x   = $signed({1'b0, pixel_x}) - $signed({1'b0, mouse_x});
    rel_y   = $signed({1'b0, pixel_y}) - $signed({1'b0, mouse_y});
  end
  // Arrow cursor pattern (11x18 pixels) - IMPROVED
  // Better arrow with connected tail
  always @(*) begin
    cursor_active = 0;
    cursor_colour = 16'hFFFF;  // White cursor

    if (mouse_clicked) begin
      // GRAB HAND CURSOR (8x10 pixels)
      // Closed fist shape
      if (rel_x >= 0 && rel_x < 8 && rel_y >= 0 && rel_y < 10) begin
        case (rel_y)
          // Top of fingers
          0: cursor_active = (rel_x >= 2 && rel_x <= 5);
          1: cursor_active = (rel_x >= 1 && rel_x <= 6);
          // Finger joints
          2: cursor_active = (rel_x >= 1 && rel_x <= 6);
          3: cursor_active = (rel_x >= 1 && rel_x <= 6);
          // Palm area
          4: cursor_active = (rel_x >= 0 && rel_x <= 6);
          5: cursor_active = (rel_x >= 0 && rel_x <= 6);
          6: cursor_active = (rel_x >= 0 && rel_x <= 6);
          // Bottom palm
          7: cursor_active = (rel_x >= 1 && rel_x <= 5);
          8: cursor_active = (rel_x >= 2 && rel_x <= 4);
          9: cursor_active = (rel_x == 3);
          default: cursor_active = 0;
        endcase

        if (cursor_active) begin
          cursor_colour = 16'hFDA0;  // Light orange/skin tone
        end
      end
    end else begin
      // ARROW CURSOR (11x18 pixels) - IMPROVED DESIGN
      if (rel_x >= 0 && rel_x < 11 && rel_y >= 0 && rel_y < 18) begin
        case (rel_y)
          // Arrow head pointing up-left
          0: cursor_active = (rel_x == 0);
          1: cursor_active = (rel_x <= 1);
          2: cursor_active = (rel_x <= 2);
          3: cursor_active = (rel_x <= 3);
          4: cursor_active = (rel_x <= 4);
          5: cursor_active = (rel_x <= 5);
          6: cursor_active = (rel_x <= 6);
          7: cursor_active = (rel_x <= 7);
          8: cursor_active = (rel_x <= 8);
          9: cursor_active = (rel_x <= 9);
          10: cursor_active = (rel_x <= 10);
          // Transition to tail - connected properly
          11: cursor_active = (rel_x >= 5 && rel_x <= 7);
          12: cursor_active = (rel_x >= 5 && rel_x <= 7);
          13: cursor_active = (rel_x >= 6 && rel_x <= 7);
          14: cursor_active = (rel_x >= 6 && rel_x <= 8);
          15: cursor_active = (rel_x >= 7 && rel_x <= 8);
          16: cursor_active = (rel_x >= 7 && rel_x <= 9);
          17: cursor_active = (rel_x >= 8 && rel_x <= 9);
          default: cursor_active = 0;
        endcase

        if (cursor_active) begin
          // Black outline on edges, white fill inside
          if (rel_x == 0 ||  // Left edge
              (rel_y <= 10 && rel_x == rel_y) ||  // Diagonal edge
              (rel_y == 10) ||  // Bottom of triangle
              (rel_y == 11 && (rel_x == 5 || rel_x == 7)) ||  // Tail sides
              (rel_y == 12 && (rel_x == 5 || rel_x == 7)) ||
                        (rel_y == 13 && (rel_x == 6 || rel_x == 7)) ||
                        (rel_y == 14 && (rel_x == 6 || rel_x == 8)) ||
                        (rel_y == 15 && (rel_x == 7 || rel_x == 8)) ||
                        (rel_y == 16 && (rel_x == 7 || rel_x == 9)) ||
                        (rel_y == 17 && (rel_x == 8 || rel_x == 9))) begin
            cursor_colour = 16'h0000;  // Black outline
          end else begin
            cursor_colour = 16'hFFFF;  // White fill
          end
        end
      end
    end
  end

endmodule
