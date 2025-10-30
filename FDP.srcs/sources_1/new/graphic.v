`include "constants.vh"

module viewport_ctrl_pow2 (
    input  wire              clk,
    input  wire              rst,
    input  wire              mode_zoom,        // 1=zoom mode, 0=pan mode
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
  localparam signed [31:0] PAN_STEP_PIX_Q = `TO_Q16_16(8);

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

      // pan (when not in zoom mode)
      if (!mode_zoom) begin
        if (pulse_left) offset_x_q16_16 <= offset_x_q16_16 - pan_step_world_q16;
        if (pulse_right) offset_x_q16_16 <= offset_x_q16_16 + pan_step_world_q16;
        if (pulse_up) offset_y_q16_16 <= offset_y_q16_16 + pan_step_world_q16;
        if (pulse_down) offset_y_q16_16 <= offset_y_q16_16 - pan_step_world_q16;
      end
    end
  end
endmodule

module range_planner_comb_pow2 (
    input  wire signed [ 3:0] zoom_exp,         // uniform zoom exponent
    input  wire signed [31:0] offset_x_q16_16,
    output reg signed  [31:0] x_start_q16_16,
    output reg signed  [31:0] x_step_q16_16,
    output wire        [ 7:0] sample_count
);
  localparam integer SCREEN_W = `DISP_W;
  localparam integer CENTER_X = (`DISP_W / 2);

  // precomputed constants
  wire signed [31:0] neg_cx_q = -(`TO_Q16_16(CENTER_X));
  wire        [ 3:0] e_neg = -zoom_exp[3:0];

  assign sample_count = SCREEN_W[7:0];

  always @* begin
    // x_start = ( -CX <<16 ) / 2^exp + offset
    if (zoom_exp >= 0) x_start_q16_16 = (neg_cx_q >>> zoom_exp) + offset_x_q16_16;
    else x_start_q16_16 = (neg_cx_q <<< e_neg) + offset_x_q16_16;

    // x_step = (1<<16) / 2^exp  in Q16.16
    if (zoom_exp >= 0) x_step_q16_16 = (`Q16_16_ONE >>> zoom_exp);
    else x_step_q16_16 = (`Q16_16_ONE <<< e_neg);
  end
endmodule

module mapper_plot_points_plain (
    input wire clk,
    input wire rst,

    // viewport (uniform zoom via exponent)
    input wire signed [ 3:0] zoom_exp,
    input wire signed [31:0] offset_x_q16_16,
    input wire signed [31:0] offset_y_q16_16,

    // streamed points (Q16.16)
    input  wire               y_valid,
    input  wire signed [31:0] x_q16_16,
    input  wire signed [31:0] y_q16_16,
    output wire               y_ready,   // always ready

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

  // 1bpp framebuffer
  reg               vram                   [0:VRAM_SIZE-1];

  // temporaries (declared at module scope)
  reg signed [31:0] dx_q16;
  reg signed [31:0] dy_q16;
  wire       [ 3:0] e_neg = -zoom_exp[3:0];

  reg signed [31:0] xs_q16;
  reg signed [31:0] ys_q16;
  reg signed [31:0] xs_cen_q16;
  reg signed [31:0] ys_cen_q16;

  integer           px;
  integer           py;

  integer           j;  // loop for clear

  // always ready to take a point per cycle
  assign y_ready = 1'b1;

  // write path
  always @(posedge clk) begin
    if (rst || clear_curves) begin
      for (j = 0; j < VRAM_SIZE; j = j + 1) begin
        vram[j] <= 1'b0;
      end
    end else begin
      if (y_valid) begin
        // world delta
        dx_q16 <= x_q16_16 - offset_x_q16_16;
        dy_q16 <= y_q16_16 - offset_y_q16_16;

        // scale by 2^exp using shifts (uniform zoom)
        if (zoom_exp >= 0) begin
          xs_q16 <= (dx_q16 <<< zoom_exp);
          ys_q16 <= (dy_q16 <<< zoom_exp);
        end else begin
          xs_q16 <= (dx_q16 >>> e_neg);
          ys_q16 <= (dy_q16 >>> e_neg);
        end

        // add screen center (in Q16.16)
        xs_cen_q16 <= xs_q16 + `TO_Q16_16(CENTER_X);
        ys_cen_q16 <= `TO_Q16_16(CENTER_Y) - ys_q16;

        // to integer pixels
        px <= xs_cen_q16 >>> 16;
        py <= ys_cen_q16 >>> 16;

        // set pixel
        if (px >= 0 && px < SCREEN_W && py >= 0 && py < SCREEN_H) begin
          vram[py*SCREEN_W+px] <= 1'b1;
        end
      end
    end
  end

  // read path (axes + vram)
  wire [6:0] sx = pixel_index % SCREEN_W;
  wire [5:0] sy = pixel_index / SCREEN_W;
  wire       on_axes = (sy == (CENTER_Y[5:0])) || (sx == (CENTER_X[6:0]));
  wire       on_curve = vram[sy*SCREEN_W+sx];

  assign pixel_colour = on_curve ? 16'hFFFF : on_axes ? 16'h07E0 : 16'h0000;

endmodule

module graph_plotter_core_ext (
    input wire clk_100,
    input wire clk_pix_6p25,  // kept for your OLED path
    input wire rst,

    // controls
    input wire mode_zoom,
    input wire p_left,
    p_right,
    p_up,
    p_down,
    input wire p_zoom_in,
    p_zoom_out,
    input wire p_clear_curves,

    // OLED fetch
    input  wire [12:0] pixel_index,
    output wire [15:0] pixel_colour,

    // external compute interface
    output wire               ext_x_valid,
    output wire signed [31:0] ext_x_q16_16,
    input  wire               ext_x_ready,
    input  wire               ext_y_valid,
    input  wire signed [31:0] ext_y_q16_16,
    output wire               ext_y_ready
);
  // 1) viewport (pan/zoom)
  wire signed [ 3:0] zoom_exp;
  wire signed [31:0] offset_x_q16_16;
  wire signed [31:0] offset_y_q16_16;
  viewport_ctrl_pow2 u_vp (
      .clk(clk_100),
      .rst(rst),
      .mode_zoom(mode_zoom),
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
  range_planner_comb_pow2 u_rng (
      .zoom_exp(zoom_exp),
      .offset_x_q16_16(offset_x_q16_16),
      .x_start_q16_16(x_start_q16_16),
      .x_step_q16_16(x_step_q16_16),
      .sample_count(sample_count)
  );

  // 3) sweep x across the screen width
  reg               active;
  reg        [ 7:0] idx;
  reg signed [31:0] x_cur;

  assign ext_x_valid  = active;
  assign ext_x_q16_16 = x_cur;

  always @(posedge clk_100) begin
    if (rst) begin
      active <= 1'b0;
      idx    <= 8'd0;
      x_cur  <= 32'sd0;
    end else begin
      if (!active) begin
        active <= 1'b1;
        idx    <= 8'd0;
        x_cur  <= x_start_q16_16;
      end else if (ext_x_valid && ext_x_ready) begin
        if (idx == (sample_count - 1)) begin
          active <= 1'b0;  // next cycle will re-arm
        end else begin
          idx   <= idx + 8'd1;
          x_cur <= x_cur + x_step_q16_16;
        end
      end
    end
  end

  // 4) plot received points (always ready to take one per cycle)
  mapper_plot_points_plain u_plot (
      .clk(clk_100),
      .rst(rst),
      .zoom_exp(zoom_exp),
      .offset_x_q16_16(offset_x_q16_16),
      .offset_y_q16_16(offset_y_q16_16),
      .y_valid(ext_y_valid),
      .x_q16_16(ext_x_q16_16),
      .y_q16_16(ext_y_q16_16),
      .y_ready(ext_y_ready),
      .clear_curves(p_clear_curves),
      .pixel_index(pixel_index),
      .pixel_colour(pixel_colour)
  );
endmodule

`include "constants.vh"

module compute_2x_plus_1_dummy (
    input  wire               clk,
    input  wire               rst,
    input  wire               x_valid,
    input  wire signed [31:0] x_q16_16,
    output wire               x_ready,
    output reg                y_valid,
    output reg signed  [31:0] y_q16_16,
    input  wire               y_ready
);
  // single-entry buffer (no local decls in always)
  reg pending;

  assign x_ready = (!pending) || (pending && y_ready);

  always @(posedge clk) begin
    if (rst) begin
      pending  <= 1'b0;
      y_valid  <= 1'b0;
      y_q16_16 <= 32'sd0;
    end else begin
      // accept x
      if (x_valid && x_ready) begin
        y_q16_16 <= (x_q16_16 <<< 1) + `Q16_16_ONE;  // y = 2x + 1
        pending  <= 1'b1;
      end
      // produce y
      y_valid <= pending;
      if (y_ready && pending) begin
        pending <= 1'b0;
      end
    end
  end
endmodule


module graph_plotter_top_demo2x1 (
    input wire clk_100,
    input wire clk_pix_6p25,
    input wire rst,

    input wire mode_zoom,
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
  wire ext_x_valid, ext_x_ready;
  wire signed [31:0] ext_x_q16_16;
  wire ext_y_valid, ext_y_ready;
  wire signed [31:0] ext_y_q16_16;

  graph_plotter_core_ext u_core (
      .clk_100(clk_100),
      .clk_pix_6p25(clk_pix_6p25),
      .rst(rst),
      .mode_zoom(mode_zoom),
      .p_left(p_left),
      .p_right(p_right),
      .p_up(p_up),
      .p_down(p_down),
      .p_zoom_in(p_zoom_in),
      .p_zoom_out(p_zoom_out),
      .p_clear_curves(p_clear_curves),
      .pixel_index(pixel_index),
      .pixel_colour(pixel_colour),
      .ext_x_valid(ext_x_valid),
      .ext_x_q16_16(ext_x_q16_16),
      .ext_x_ready(ext_x_ready),
      .ext_y_valid(ext_y_valid),
      .ext_y_q16_16(ext_y_q16_16),
      .ext_y_ready(ext_y_ready)
  );

  compute_2x_plus_1_dummy u_dummy (
      .clk(clk_100),
      .rst(rst),
      .x_valid(ext_x_valid),
      .x_q16_16(ext_x_q16_16),
      .x_ready(ext_x_ready),
      .y_valid(ext_y_valid),
      .y_q16_16(ext_y_q16_16),
      .y_ready(ext_y_ready)
  );
endmodule
