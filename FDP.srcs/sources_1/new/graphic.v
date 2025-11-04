`include "constants.vh"

module viewport_ctrl (
    input  wire               clk,
    input  wire               rst,
    input  wire               pulse_left,
    pulse_right,
    input  wire               pulse_up,
    pulse_down,
    input  wire               pulse_zoom_in,
    pulse_zoom_out,
    input  wire               drag_active,
    input  wire signed [ 7:0] drag_delta_x_px,
    input  wire signed [ 6:0] drag_delta_y_px,
    output reg signed  [ 3:0] zoom_exp,
    output reg signed  [31:0] offset_x_q16_16,
    output reg signed  [31:0] offset_y_q16_16
);
  localparam signed [31:0] PAN_STEP_PIX_Q = `TO_Q16_16(2);

  wire signed [31:0] pan_step_world_q16_pos;
  wire signed [31:0] pan_step_world_q16_neg;
  wire        [ 3:0] zoom_exp_neg = -zoom_exp[3:0];

  assign pan_step_world_q16_pos = PAN_STEP_PIX_Q >>> zoom_exp;
  assign pan_step_world_q16_neg = PAN_STEP_PIX_Q <<< zoom_exp_neg;

  wire signed [31:0] pan_step_world_q16 =
      (zoom_exp >= 0) ? pan_step_world_q16_pos : pan_step_world_q16_neg;

  // Convert drag deltas from screen pixels to world coordinates
  wire signed [31:0] drag_dx_q16 = $signed(drag_delta_x_px) << 16;
  wire signed [31:0] drag_dy_q16 = $signed(drag_delta_y_px) << 16;
  wire signed [31:0] drag_world_dx_q16 = (zoom_exp >= 0) ? 
                                          (drag_dx_q16 >>> zoom_exp) : 
                                          (drag_dx_q16 <<< zoom_exp_neg);
  wire signed [31:0] drag_world_dy_q16 = (zoom_exp >= 0) ? 
                                          (drag_dy_q16 >>> zoom_exp) : 
                                          (drag_dy_q16 <<< zoom_exp_neg);

  always @(posedge clk) begin
    if (rst) begin
      zoom_exp        <= 4'sd0;
      offset_x_q16_16 <= 32'sd0;
      offset_y_q16_16 <= 32'sd0;
    end else begin
      if (pulse_zoom_in && (zoom_exp < 4'sd4) && !pulse_zoom_out) begin
        zoom_exp        <= zoom_exp + 4'sd1;
        offset_x_q16_16 <= offset_x_q16_16 >>> 1;
        offset_y_q16_16 <= offset_y_q16_16 >>> 1;
      end else if (pulse_zoom_out && (zoom_exp > -4'sd3) && !pulse_zoom_in) begin
        zoom_exp        <= zoom_exp - 4'sd1;
        offset_x_q16_16 <= offset_x_q16_16 <<< 1;
        offset_y_q16_16 <= offset_y_q16_16 <<< 1;
      end else if (drag_active && (drag_delta_x_px != 0 || drag_delta_y_px != 0)) begin
        // Apply drag: move graph opposite to mouse movement
        offset_x_q16_16 <= offset_x_q16_16 - drag_world_dx_q16;
        offset_y_q16_16 <= offset_y_q16_16 + drag_world_dy_q16;
      end else begin
        // Button-based pan
        if (pulse_left) offset_x_q16_16 <= offset_x_q16_16 - pan_step_world_q16;
        if (pulse_right) offset_x_q16_16 <= offset_x_q16_16 + pan_step_world_q16;
        if (pulse_up) offset_y_q16_16 <= offset_y_q16_16 + pan_step_world_q16;
        if (pulse_down) offset_y_q16_16 <= offset_y_q16_16 - pan_step_world_q16;
      end
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
    if (zoom_exp >= 0) x_start_q16_16 = (neg_cx_q >>> zoom_exp) - offset_x_q16_16;
    else x_start_q16_16 = (neg_cx_q <<< e_neg) - offset_x_q16_16;
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
    input wire               y_valid,
    input wire signed [31:0] x_q16_16,
    input wire signed [31:0] y_q16_16,

    // clear
    input wire clear_curves,

    // OLED sampling
    input  wire [12:0] pixel_index,
    output wire [15:0] pixel_colour
);
  localparam SCREEN_W = `DISP_W;
  localparam SCREEN_H = `DISP_H;
  localparam CENTER_X = (`DISP_W / 2);
  localparam CENTER_Y = (`DISP_H / 2);
  localparam VRAM_SIZE = (`DISP_W * `DISP_H);

  // Colors (RGB565)
  localparam [15:0] COL_BG = 16'h0000;  // black
  localparam [15:0] COL_AXES = 16'h07E0;  // green
  localparam [15:0] COL_CURVE = 16'hFFFF;  // white
  localparam [15:0] COL_ORIGIN = 16'hFFE0;  // yellow
  localparam [15:0] COL_UNIT = 16'hF800;  // red

  reg [6 * SCREEN_W - 1 : 0] curve_y;
  reg [SCREEN_W - 1 : 0] curve_y_valid;

  wire [3:0] e_neg = -zoom_exp[3:0];

  wire signed [31:0] dx_q16 = x_q16_16 + offset_x_q16_16;
  wire signed [31:0] dy_q16 = y_q16_16 + offset_y_q16_16;
  wire signed [31:0] xs_q16 = (zoom_exp >= 0) ? (dx_q16 <<< zoom_exp) : (dx_q16 >>> e_neg);
  wire signed [31:0] ys_q16 = (zoom_exp >= 0) ? (dy_q16 <<< zoom_exp) : (dy_q16 >>> e_neg);
  wire signed [31:0] xs_cen_q16 = xs_q16 + (CENTER_X <<< 16);
  wire signed [31:0] ys_cen_q16 = (CENTER_Y <<< 16) - ys_q16;
  wire signed [15:0] px_samp = xs_cen_q16 >>> 16;
  wire signed [15:0] py_samp = ys_cen_q16 >>> 16;
  wire px_samp_in = (px_samp >= 0) && (px_samp < SCREEN_W);
  wire py_samp_in = (py_samp >= 0) && (py_samp < SCREEN_H);

  // ---------- map origin (0,0) ----------
  wire signed [31:0] dx_o_q16 = offset_x_q16_16;  // 0 - offset_x
  wire signed [31:0] dy_o_q16 = offset_y_q16_16;  // 0 - offset_y
  wire signed [31:0] xo_q16 = (zoom_exp >= 0) ? (dx_o_q16 <<< zoom_exp) : (dx_o_q16 >>> e_neg);
  wire signed [31:0] yo_q16 = (zoom_exp >= 0) ? (dy_o_q16 <<< zoom_exp) : (dy_o_q16 >>> e_neg);
  wire signed [31:0] xo_c_q16 = xo_q16 + (CENTER_X <<< 16);
  wire signed [31:0] yo_c_q16 = (CENTER_Y <<< 16) - yo_q16;
  wire signed [15:0] px_org = xo_c_q16 >>> 16;  // origin column
  wire signed [15:0] py_org = yo_c_q16 >>> 16;  // origin row
  wire px_org_in = (px_org >= 0) && (px_org < SCREEN_W);
  wire py_org_in = (py_org >= 0) && (py_org < SCREEN_H);

  // ---------- map unit point (4,0) ----------
  wire signed [31:0] dx_u_q16 = (32'sd4 <<< 16) + offset_x_q16_16;
  wire signed [31:0] xu_q16 = (zoom_exp >= 0) ? (dx_u_q16 <<< zoom_exp) : (dx_u_q16 >>> e_neg);
  wire signed [31:0] xu_c_q16 = xu_q16 + (CENTER_X <<< 16);
  wire signed [15:0] px_unit = xu_c_q16 >>> 16;
  wire signed [15:0] py_unit = py_org;
  wire unit_inb = (px_unit >= 0) && (px_unit < SCREEN_W) && py_org_in;

  // ---------- write holdoff after clear ----------
  reg [1:0] holdoff;
  always @(posedge clk) begin
    if (rst) holdoff <= 2'b00;
    else if (clear_curves) holdoff <= 2'b11;  // mask writes for 2 cycles
    else holdoff <= {1'b0, holdoff[1]};
  end
  wire we = start && px_samp_in && (holdoff == 2'b00);

  // ---------- VRAM write / clear ----------
  integer j, k;
  always @(posedge clk) begin
    if (rst || clear_curves) begin
      curve_y_valid <= 0;
      curve_y <= 0;
    end else if (we) begin
      curve_y_valid[px_samp] <= y_valid & py_samp_in;
      if (y_valid) begin
        for (k = 0; k < 6; k = k + 1) curve_y[px_samp*6+k] = py_samp[k];
      end
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
  wire on_curve = curve_y_valid[sx] && curve_y[sx*6] == sy[0] 
                  && curve_y[sx*6+1] == sy[1]
                  && curve_y[sx*6+2] == sy[2]
                  && curve_y[sx*6+3] == sy[3]
                  && curve_y[sx*6+4] == sy[4]
                  && curve_y[sx*6+5] == sy[5];

  // priority: curve > origin > unit > axes > bg
  assign pixel_colour =
      on_curve  ? COL_CURVE  :
      on_origin ? COL_ORIGIN :
      on_unit   ? COL_UNIT   :
      on_axes   ? COL_AXES   :
                  COL_BG;

endmodule

module mouse_drag_ctrl (
    input wire clk,
    input wire rst,
    input wire [6:0] mouse_x,
    input wire [5:0] mouse_y,
    input wire mouse_left,
    input wire mouse_middle,
    output reg drag_active,
    output reg signed [7:0] drag_delta_x,
    output reg signed [6:0] drag_delta_y,
    output reg zoom_in,
    output reg zoom_out
);
  reg [6:0] drag_start_x;
  reg [5:0] drag_start_y;
  reg [6:0] last_x;
  reg [5:0] last_y;
  reg drag_was_active;

  // Scroll wheel zoom detection
  reg [19:0] zoom_counter;
  wire zoom_tick = (zoom_counter == 0);

  always @(posedge clk) begin
    if (rst) begin
      drag_active <= 0;
      drag_delta_x <= 0;
      drag_delta_y <= 0;
      drag_start_x <= 0;
      drag_start_y <= 0;
      last_x <= 0;
      last_y <= 0;
      drag_was_active <= 0;
      zoom_in <= 0;
      zoom_out <= 0;
      zoom_counter <= 0;
    end else begin
      // Zoom counter for rate limiting
      if (zoom_counter == 20_000_000) zoom_counter <= 0;
      else zoom_counter <= zoom_counter + 1;

      // Middle button zoom (hold middle + move up/down)
      if (zoom_tick) begin
        zoom_in  <= mouse_middle && (mouse_y < 20);
        zoom_out <= mouse_middle && (mouse_y > 44);
      end else begin
        zoom_in  <= 0;
        zoom_out <= 0;
      end

      // Drag detection and delta calculation
      if (!drag_was_active && mouse_left) begin
        // Start drag
        drag_active <= 1;
        drag_start_x <= mouse_x;
        drag_start_y <= mouse_y;
        last_x <= mouse_x;
        last_y <= mouse_y;
        drag_delta_x <= 0;
        drag_delta_y <= 0;
      end else if (drag_was_active && mouse_left) begin
        // Continue drag - output delta since last frame
        drag_active <= 1;
        drag_delta_x <= $signed({1'b0, mouse_x}) - $signed({1'b0, last_x});
        drag_delta_y <= $signed({1'b0, mouse_y}) - $signed({1'b0, last_y});
        last_x <= mouse_x;
        last_y <= mouse_y;
      end else begin
        // End drag or not dragging
        drag_active  <= 0;
        drag_delta_x <= 0;
        drag_delta_y <= 0;
      end

      drag_was_active <= mouse_left;
    end
  end
endmodule

module graph_plotter_core (
    input wire clk_100,
    input wire clk_pix,
    input wire rst,
    input wire up_p,
    down_p,
    left_p,
    right_p,
    confirm_p,
    input wire mode_zoom,

    // Mouse inputs
    input wire [6:0] mouse_x,
    input wire [5:0] mouse_y,
    input wire       mouse_left,
    input wire       mouse_middle,

    output reg                start_calc = 0,
    output wire signed [31:0] x_q16_16,
    input  wire               y_ready,
    y_valid,
    input  wire signed [31:0] y_q16_16,
    output wire        [ 7:0] oled_out
);
  // Mouse drag controller
  wire drag_active;
  wire signed [7:0] drag_delta_x;
  wire signed [6:0] drag_delta_y;
  wire mouse_zoom_in, mouse_zoom_out;

  mouse_drag_ctrl drag_ctrl (
      .clk(clk_100),
      .rst(rst),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_left(mouse_left),
      .mouse_middle(mouse_middle),
      .drag_active(drag_active),
      .drag_delta_x(drag_delta_x),
      .drag_delta_y(drag_delta_y),
      .zoom_in(mouse_zoom_in),
      .zoom_out(mouse_zoom_out)
  );

  wire zoom_in_p = (mode_zoom & up_p) | mouse_zoom_in;
  wire zoom_out_p = (mode_zoom & down_p) | mouse_zoom_out;

  wire move_up = up_p & ~mode_zoom;
  wire move_down = down_p & ~mode_zoom;
  wire move_left = left_p;
  wire move_right = right_p;

  wire need_clear = up_p | down_p | left_p | right_p | confirm_p | drag_active;

  wire signed [3:0] zoom_exp;
  wire signed [31:0] offset_x_q16_16;
  wire signed [31:0] offset_y_q16_16;

  viewport_ctrl u_vp (
      .clk(clk_100),
      .rst(rst),
      .pulse_left(move_left),
      .pulse_right(move_right),
      .pulse_up(move_up),
      .pulse_down(move_down),
      .pulse_zoom_in(zoom_in_p),
      .pulse_zoom_out(zoom_out_p),
      .drag_active(drag_active),
      .drag_delta_x_px(drag_delta_x),
      .drag_delta_y_px(drag_delta_y),
      .zoom_exp(zoom_exp),
      .offset_x_q16_16(offset_x_q16_16),
      .offset_y_q16_16(offset_y_q16_16)
  );

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
    if (rst | need_clear) begin
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

  wire [12:0] pixel_index;
  wire [15:0] graph_pixel;
  wire [15:0] pixel_colour;

  mapper_plot_points u_plot (
      .clk(clk_100),
      .rst(rst),
      .zoom_exp(zoom_exp),
      .offset_x_q16_16(offset_x_q16_16),
      .offset_y_q16_16(offset_y_q16_16),
      .start(y_ready),
      .y_valid(y_valid),
      .x_q16_16(x_q16_16),
      .y_q16_16(y_q16_16),
      .clear_curves(need_clear),
      .pixel_index(pixel_index),
      .pixel_colour(graph_pixel)
  );

  wire cursor_active;
  wire [15:0] cursor_colour;
  cursor_display cursor (
      .clk(clk_pix),
      .pixel_index(pixel_index),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_clicked(mouse_left),
      .cursor_colour(cursor_colour),
      .cursor_active(cursor_active)
  );

  assign pixel_colour = cursor_active ? cursor_colour : graph_pixel;

  oled u_oled_graph (
      .clk_6p25m(clk_pix),
      .rst(rst),
      .pixel_color(pixel_colour),
      .oled_out(oled_out),
      .pixel_index(pixel_index)
  );
endmodule
