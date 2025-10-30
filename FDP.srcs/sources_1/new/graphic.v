`include "constants.vh"

module viewport_ctrl (
    input  wire              clk,
    input  wire              rst,
    input  wire              pulse_left,
    pulse_right,
    input  wire              pulse_up,
    pulse_down,
    input  wire              pulse_zoom_in,
    pulse_zoom_out,
    output reg signed [ 3:0] zoom_exp,         // range [-3 .. +4]
    output reg signed [31:0] offset_x_q16_16,
    output reg signed [31:0] offset_y_q16_16
);
  // pan step = 8 pixels (converted to world by >> zoom_exp)
  localparam signed [31:0] PAN_STEP_PIX_Q = `TO_Q16_16(2);

  // combinational pan step in world (depends only on zoom_exp)
  wire signed [31:0] pan_step_world_q16_pos;
  wire signed [31:0] pan_step_world_q16_neg;
  wire        [ 3:0] zoom_exp_neg = -zoom_exp[3:0];

  assign pan_step_world_q16_pos = PAN_STEP_PIX_Q >>> zoom_exp;  // exp >= 0
  assign pan_step_world_q16_neg = PAN_STEP_PIX_Q <<< zoom_exp_neg;  // exp <  0

  wire signed [31:0] pan_step_world_q16 =
      (zoom_exp >= 0) ? pan_step_world_q16_pos : pan_step_world_q16_neg;

  // sequential state updates
  always @(posedge clk) begin
    if (rst) begin
      zoom_exp        <= 4'sd0;  // 2^0 = 1x
      offset_x_q16_16 <= 32'sd0;
      offset_y_q16_16 <= 32'sd0;
    end else begin
      // zoom (uniform)
      if (pulse_zoom_in && (zoom_exp < 4'sd4)) zoom_exp <= zoom_exp + 4'sd1;  // up to 16x
      if (pulse_zoom_out && (zoom_exp > -4'sd3)) zoom_exp <= zoom_exp - 4'sd1;  // down to 0.125x
      if (pulse_left) offset_x_q16_16 <= offset_x_q16_16 - pan_step_world_q16;
      if (pulse_right) offset_x_q16_16 <= offset_x_q16_16 + pan_step_world_q16;
      if (pulse_up) offset_y_q16_16 <= offset_y_q16_16 + pan_step_world_q16;
      if (pulse_down) offset_y_q16_16 <= offset_y_q16_16 - pan_step_world_q16;
    end
  end
endmodule

module range_planner (
    input  wire signed [ 3:0] zoom_exp,         // uniform zoom exponent
    input  wire signed [31:0] offset_x_q16_16,
    output reg signed  [31:0] x_start_q16_16,
    output reg signed  [31:0] x_step_q16_16,
    output wire        [ 7:0] sample_count
);
  localparam integer SCREEN_W = `DISP_W;
  localparam integer CENTER_X = (`DISP_W / 2);
  wire signed [31:0] neg_cx_q = -(`TO_Q16_16(CENTER_X));
  wire        [ 3:0] e_neg = -zoom_exp[3:0];

  assign sample_count = SCREEN_W[7:0];

  always @* begin
    if (zoom_exp >= 0) x_start_q16_16 = (neg_cx_q >>> zoom_exp) + offset_x_q16_16;
    else x_start_q16_16 = (neg_cx_q <<< e_neg) + offset_x_q16_16;
    if (zoom_exp >= 0) x_step_q16_16 = (`Q16_16_ONE >>> zoom_exp);
    else x_step_q16_16 = (`Q16_16_ONE <<< e_neg);
  end
endmodule

module mapper_plot_points (
    input wire clk,
    input wire rst,

    // viewport (uniform zoom via exponent)
    input wire signed [ 3:0] zoom_exp,
    input wire signed [31:0] offset_x_q16_16,
    input wire signed [31:0] offset_y_q16_16,

    // streamed points (Q16.16)
    input wire               start,     // strobe: this (x,y) is valid this cycle
    input wire signed [31:0] x_q16_16,
    input wire signed [31:0] y_q16_16,

    // clear
    input wire clear_curves,

    // OLED sampling
    input  wire [12:0] pixel_index,
    output wire [15:0] pixel_colour
);
  localparam integer SCREEN_W = `DISP_W;
  localparam integer SCREEN_H = `DISP_H;
  localparam integer CENTER_X = (`DISP_W / 2);
  localparam integer CENTER_Y = (`DISP_H / 2);
  localparam integer VRAM_SIZE = (`DISP_W * `DISP_H);

  // Colors (RGB565)
  localparam [15:0] COL_BG = 16'h0000;  // black
  localparam [15:0] COL_AXES = 16'h07E0;  // green
  localparam [15:0] COL_CURVE = 16'hFFFF;  // white
  localparam [15:0] COL_ORIGIN = 16'hFFE0;  // yellow
  localparam [15:0] COL_UNIT = 16'hF800;  // red

  // 1bpp framebuffer for curve
  reg vram[0:VRAM_SIZE-1];

  // ---------- common helpers ----------
  wire [3:0] e_neg = -zoom_exp[3:0];

  // map any world (wx, wy) to integer pixel (px, py)
  // Using shifts only (zoom = 2^exp), then add screen center.
  // Comb wires for the streamed sample
  wire signed [31:0] dx_q16 = x_q16_16 - offset_x_q16_16;
  wire signed [31:0] dy_q16 = y_q16_16 - offset_y_q16_16;

  wire signed [31:0] xs_q16 = (zoom_exp >= 0) ? (dx_q16 <<< zoom_exp) : (dx_q16 >>> e_neg);
  wire signed [31:0] ys_q16 = (zoom_exp >= 0) ? (dy_q16 <<< zoom_exp) : (dy_q16 >>> e_neg);

  wire signed [31:0] xs_cen_q16 = xs_q16 + (CENTER_X <<< 16);
  wire signed [31:0] ys_cen_q16 = (CENTER_Y <<< 16) - ys_q16;

  wire signed [15:0] px_samp = xs_cen_q16 >>> 16;
  wire signed [15:0] py_samp = ys_cen_q16 >>> 16;

  wire inb_samp = (px_samp >= 0) && (px_samp < SCREEN_W) && (py_samp >= 0) && (py_samp < SCREEN_H);

  // ---------- map origin (0,0) ----------
  wire signed [31:0] dx_o_q16 = -offset_x_q16_16;  // 0 - offset_x
  wire signed [31:0] dy_o_q16 = -offset_y_q16_16;  // 0 - offset_y
  wire signed [31:0] xo_q16 = (zoom_exp >= 0) ? (dx_o_q16 <<< zoom_exp) : (dx_o_q16 >>> e_neg);
  wire signed [31:0] yo_q16 = (zoom_exp >= 0) ? (dy_o_q16 <<< zoom_exp) : (dy_o_q16 >>> e_neg);
  wire signed [31:0] xo_c_q16 = xo_q16 + (CENTER_X <<< 16);
  wire signed [31:0] yo_c_q16 = (CENTER_Y <<< 16) - yo_q16;
  wire signed [15:0] px_org = xo_c_q16 >>> 16;  // origin column
  wire signed [15:0] py_org = yo_c_q16 >>> 16;  // origin row
  wire px_org_in = (px_org >= 0) && (px_org < SCREEN_W);
  wire py_org_in = (py_org >= 0) && (py_org < SCREEN_H);

  // ---------- map unit point (4,0) ----------
  wire signed [31:0] four_q16 = 32'sd4 <<< 16;
  wire signed [31:0] dx_u_q16 = four_q16 - offset_x_q16_16;
  wire signed [31:0] dy_u_q16 = -offset_y_q16_16;
  wire signed [31:0] xu_q16 = (zoom_exp >= 0) ? (dx_u_q16 <<< zoom_exp) : (dx_u_q16 >>> e_neg);
  wire signed [31:0] yu_q16 = (zoom_exp >= 0) ? (dy_u_q16 <<< zoom_exp) : (dy_u_q16 >>> e_neg);
  wire signed [31:0] xu_c_q16 = xu_q16 + (CENTER_X <<< 16);
  wire signed [31:0] yu_c_q16 = (CENTER_Y <<< 16) - yu_q16;
  wire signed [15:0] px_unit = xu_c_q16 >>> 16;
  wire signed [15:0] py_unit = yu_c_q16 >>> 16;
  wire unit_inb = (px_unit >= 0) && (px_unit < SCREEN_W) && (py_unit >= 0) && (py_unit < SCREEN_H);

  // ---------- write holdoff after clear ----------
  reg [1:0] holdoff;
  always @(posedge clk) begin
    if (rst) holdoff <= 2'b00;
    else if (clear_curves) holdoff <= 2'b11;  // mask writes for 2 cycles
    else holdoff <= {1'b0, holdoff[1]};
  end
  wire we = start && inb_samp && (holdoff == 2'b00);

  // ---------- VRAM write / clear ----------
  integer j;
  always @(posedge clk) begin
    if (rst || clear_curves) begin
      for (j = 0; j < VRAM_SIZE; j = j + 1) vram[j] <= 1'b0;
    end else if (we) begin
      vram[py_samp*SCREEN_W+px_samp] <= 1'b1;
    end
  end

  // ---------- read path (compose curve + moving axes + markers) ----------
  wire [6:0] sx = pixel_index % SCREEN_W;  // column
  wire [5:0] sy = pixel_index / SCREEN_W;  // row

  // moving world axes at origin
  wire on_vaxis = px_org_in && (sx == px_org[6:0]);
  wire on_haxis = py_org_in && (sy == py_org[5:0]);
  wire on_axes = on_vaxis || on_haxis;

  // origin dot (single pixel)
  wire on_origin = px_org_in && py_org_in && (sx == px_org[6:0]) && (sy == py_org[5:0]);

  // unit dot at (4,0)
  wire on_unit = unit_inb && (sx == px_unit[6:0]) && (sy == py_unit[5:0]);

  // curve pixel
  wire on_curve = vram[sy*SCREEN_W+sx];

  // priority: curve > origin > unit > axes > bg
  assign pixel_colour =
      on_curve  ? COL_CURVE  :
      on_origin ? COL_ORIGIN :
      on_unit   ? COL_UNIT   :
      on_axes   ? COL_AXES   :
                  COL_BG;

endmodule

module graph_plotter_core (
    input wire clk_100,
    input wire rst,
    input wire p_left,
    p_right,
    p_up,
    p_down,
    input wire p_zoom_in,
    p_zoom_out,
    input wire p_clear_curves,

    input  wire [12:0] pixel_index,
    output wire [15:0] pixel_colour,

    output reg                start_calc = 0,
    output wire signed [31:0] x_q16_16,
    input  wire               y_ready,
    y_valid,
    input  wire signed [31:0] y_q16_16
);
  // 1) viewport (pan/zoom)
  wire signed [ 3:0] zoom_exp;
  wire signed [31:0] offset_x_q16_16;
  wire signed [31:0] offset_y_q16_16;
  viewport_ctrl u_vp (
      .clk(clk_100),
      .rst(rst),
      .pulse_left(p_left),
      .pulse_right(p_right),
      .pulse_up(p_up),
      .pulse_down(p_down),
      .pulse_zoom_in(p_zoom_in),
      .pulse_zoom_out(p_zoom_out),
      .zoom_exp(zoom_exp),
      .offset_x_q16_16(offset_x_q16_16),
      .offset_y_q16_16(offset_y_q16_16)
  );

  // 2) combinational range (per sweep)
  wire signed [31:0] x_start_q16_16;
  wire signed [31:0] x_step_q16_16;
  wire        [ 7:0] sample_count;
  range_planner u_rng (
      .zoom_exp(zoom_exp),
      .offset_x_q16_16(offset_x_q16_16),
      .x_start_q16_16(x_start_q16_16),
      .x_step_q16_16(x_step_q16_16),
      .sample_count(sample_count)
  );

  reg        [ 7:0] idx;
  reg signed [31:0] x_cur;

  assign x_q16_16 = x_cur;

  always @(posedge clk_100) begin
    if (rst | p_clear_curves) begin
      idx    <= 8'd0;
      x_cur  <= x_start_q16_16;
      start_calc <= 1'b0;
    end else begin
      if (y_ready) begin
        start_calc <= 1'b1;
        if (idx == (sample_count - 1)) begin
          idx   <= 8'd0;
          x_cur <= x_start_q16_16;
        end else begin
          idx   <= idx + 8'd1;
          x_cur <= x_cur + x_step_q16_16;
        end
      end else begin
        start_calc <= 1'b0;
      end
    end
  end

  // 4) plot received points (always ready to take one per cycle)
  wire need_clear = p_clear_curves | p_left | p_right | p_up | p_down | p_zoom_in | p_zoom_out;
  mapper_plot_points u_plot (
      .clk(clk_100),
      .rst(rst),
      .zoom_exp(zoom_exp),
      .offset_x_q16_16(offset_x_q16_16),
      .offset_y_q16_16(offset_y_q16_16),
      .start(y_ready & y_valid),
      .x_q16_16(x_q16_16),
      .y_q16_16(y_q16_16),
      .clear_curves(need_clear),
      .pixel_index(pixel_index),
      .pixel_colour(pixel_colour)
  );
endmodule

module compute_2x_plus_1_dummy (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire signed [31:0] x_q16_16,
    output reg                y_valid,
    output reg signed  [31:0] y_q16_16,
    output reg                ready
);
  always @(posedge clk) begin
    if (rst) begin
      y_valid = 0;
      y_q16_16 <= 0;
      ready <= 1'b1;
    end else begin
      y_valid <= 1'b1;
      y_q16_16 <= (x_q16_16 <<< 1) + `Q16_16_ONE;
      ready <= 1'b1;
    end
  end
endmodule


module graph_plotter_top_demo2x1 (
    input wire clk_100,
    input wire rst,

    input wire p_left,
    p_right,
    p_up,
    p_down,
    input wire p_zoom_in,
    p_zoom_out,
    input wire p_clear_curves,

    input  wire [12:0] pixel_index,
    output wire [15:0] pixel_colour
);
  wire start_calc;
  wire signed [31:0] x_q16_16;
  wire y_valid, y_ready;
  wire signed [31:0] y_q16_16;

  graph_plotter_core u_core (
      .clk_100(clk_100),
      .rst(rst),
      .p_left(p_left),
      .p_right(p_right),
      .p_up(p_up),
      .p_down(p_down),
      .p_zoom_in(p_zoom_in),
      .p_zoom_out(p_zoom_out),
      .p_clear_curves(p_clear_curves),
      .pixel_index(pixel_index),
      .pixel_colour(pixel_colour),
      .start_calc(start_calc),
      .x_q16_16(x_q16_16),
      .y_ready(y_ready),
      .y_valid(y_valid),
      .y_q16_16(y_q16_16)
  );

  compute_2x_plus_1_dummy u_dummy (
      .clk(clk_100),
      .rst(rst),
      .start(start_calc),
      .x_q16_16(x_q16_16),
      .y_valid(y_valid),
      .y_q16_16(y_q16_16),
      .ready(y_ready)
  );
endmodule
