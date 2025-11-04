`timescale 1ns / 1ps
`include "constants.vh"
// text_buffer.v  — supports append (<=6 bytes now) and replace (<=MAX_DATA)
module text_buffer #(
    parameter integer MAX_DATA = 32
) (
    input wire clk,
    input wire rst,
    input wire clear,
    input wire backspace, // Delete last char

    // ===== append path (keypad emit) =====
    input wire        append,      // 1-cycle pulse
    input wire [ 2:0] append_len,  // 0..6
    input wire [47:0] append_bus,  // byte i at [8*i +: 8], LSB-first

    // ===== Replace path (external bulk load) =====
    input wire                  load,      // 1-cycle pulse
    input wire [           7:0] load_len,  // 0..MAX_DATA
    input wire [8*MAX_DATA-1:0] load_bus,  // byte i at [8*i +: 8], LSB-first

    // ===== Outputs =====
    output reg [           7:0] len,  // current used length
    output reg [8*MAX_DATA-1:0] mem   // byte i at [8*i +: 8], LSB-first
);
  integer i, j;
  wire [7:0] cap_len = (load_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : load_len;
  wire [2:0] a_len_eff = (append_len > (MAX_DATA[7:0] - len)) ? (MAX_DATA[7:0] - len) : append_len;

  always @(posedge clk) begin
    if (rst || clear) begin
      len <= 8'd0;
      mem <= 0;
    end else if (load) begin
      // Replace: copy first cap_len bytes, clear the rest
      for (i = 0; i < MAX_DATA; i = i + 1) begin
        if (i < cap_len) mem[8*i+:8] <= load_bus[8*i+:8];
        else mem[8*i+:8] <= 8'h00;
      end
      len <= cap_len;
    end else if (backspace && (len > 0)) begin
      // Delete last character
      len <= len - 8'd1;
      mem[8*(len-1)+:8] <= 8'h00;
    end else if (append && (append_len != 0) && (len < MAX_DATA[7:0])) begin
      // Append: clamp to capacity
      for (j = 0; j < 6; j = j + 1) begin  // Changed from 4 to 6
        if (j < a_len_eff) mem[8*(len+j)+:8] <= append_bus[8*j+:8];
      end
      len <= len + a_len_eff;
    end
  end
endmodule

module input_core #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer REPEAT_START_MS = 500,
    parameter integer REPEAT_INTERVAL_MS = 60,
    parameter integer MAX_DATA = 32,
    parameter integer FONT_SCALE = 2,
    parameter [8*16-1:0] KB0_LAYOUT = 0,  // 4x4 layout
    parameter [8*16-1:0] KB1_LAYOUT = 0,  // 4x4 layout
    parameter [8*12-1:0] KB2_LAYOUT = 0  // 4x3 layout
) (
    input wire clk,
    input wire rst,

    input wire up_p,
    down_p,
    left_p,
    right_p,
    confirm_p,
    input wire [1:0] kb_sel,  // Changed to 2 bits for 3 pages

    // Mouse input
    input wire [6:0] mouse_x,
    input wire [5:0] mouse_y,
    input wire       mouse_left,

    // external bulk load (replace buffer)
    input wire                  buf_load,
    input wire [           7:0] buf_load_len,
    input wire [8*MAX_DATA-1:0] buf_load_bus,

    // buffer out (to compute / text renderer)
    output wire [8*MAX_DATA-1:0] buffer_flat,
    output wire [           7:0] buffer_len,

    // strobes (1-cycle pulses)
    output wire is_clear,
    output wire is_equal,

    input  wire       clk_pix,
    output wire [7:0] oled_out
);
  wire [7:0] oled_out_0;
  wire [7:0] oled_out_1;
  wire [7:0] oled_out_2;

  wire ap0, ap1, ap2;  // append pulse
  wire [2:0] al0, al1, al2;  // append len
  wire [47:0] ab0, ab1, ab2;  // append bus (now 48 bits)
  wire cl0, cl1, cl2;  // clear pulse
  wire bk0, bk1, bk2;  // back pulse
  wire eq0, eq1, eq2;  // equals pulse

  // Page 0: 4x4 basic operations
  keypad_widget #(
      .FONT_SCALE(FONT_SCALE),
      .GRID_ROWS (4),
      .GRID_COLS (4),
      .KB_LAYOUT (KB0_LAYOUT)
  ) kb0 (
      .clk(clk),
      .rst(rst),
      .up_p(up_p),
      .down_p(down_p),
      .left_p(left_p),
      .right_p(right_p),
      .confirm_p(confirm_p),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_left(mouse_left),
      .clk_pix(clk_pix),
      .oled_out(oled_out_0),
      .tb_append(ap0),
      .tb_append_len(al0),
      .tb_append_bus(ab0),
      .tb_clear(cl0),
      .tb_back(bk0),
      .is_equal(eq0),
      .focus_row(),
      .focus_col()
  );

  // Page 1: 4x4 trig and advanced functions
  keypad_widget #(
      .FONT_SCALE(FONT_SCALE),
      .GRID_ROWS (4),
      .GRID_COLS (4),
      .KB_LAYOUT (KB1_LAYOUT)
  ) kb1 (
      .clk(clk),
      .rst(rst),
      .up_p(up_p),
      .down_p(down_p),
      .left_p(left_p),
      .right_p(right_p),
      .confirm_p(confirm_p),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_left(mouse_left),
      .clk_pix(clk_pix),
      .oled_out(oled_out_1),
      .tb_append(ap1),
      .tb_append_len(al1),
      .tb_append_bus(ab1),
      .tb_clear(cl1),
      .tb_back(bk1),
      .is_equal(eq1),
      .focus_row(),
      .focus_col()
  );

  // Page 2: 4x3 math.h-style functions
  keypad_widget #(
      .FONT_SCALE(FONT_SCALE),
      .GRID_ROWS (4),
      .GRID_COLS (3),
      .KB_LAYOUT (KB2_LAYOUT)
  ) kb2 (
      .clk(clk),
      .rst(rst),
      .up_p(up_p),
      .down_p(down_p),
      .left_p(left_p),
      .right_p(right_p),
      .confirm_p(confirm_p),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_left(mouse_left),
      .clk_pix(clk_pix),
      .oled_out(oled_out_2),
      .tb_append(ap2),
      .tb_append_len(al2),
      .tb_append_bus(ab2),
      .tb_clear(cl2),
      .tb_back(bk2),
      .is_equal(eq2),
      .focus_row(),
      .focus_col()
  );

  // Mux outputs based on kb_sel
  wire        tb_append = (kb_sel == 2'd0) ? ap0 : (kb_sel == 2'd1) ? ap1 : ap2;
  wire [ 2:0] tb_append_len = (kb_sel == 2'd0) ? al0 : (kb_sel == 2'd1) ? al1 : al2;
  wire [47:0] tb_append_bus = (kb_sel == 2'd0) ? ab0 : (kb_sel == 2'd1) ? ab1 : ab2;
  wire        tb_clear_i = (kb_sel == 2'd0) ? cl0 : (kb_sel == 2'd1) ? cl1 : cl2;
  wire        tb_back_i = (kb_sel == 2'd0) ? bk0 : (kb_sel == 2'd1) ? bk1 : bk2;
  assign is_equal = (kb_sel == 2'd0) ? eq0 : (kb_sel == 2'd1) ? eq1 : eq2;
  assign is_clear = tb_clear_i;
  assign oled_out = (kb_sel == 2'd0) ? oled_out_0 : (kb_sel == 2'd1) ? oled_out_1 : oled_out_2;

  text_buffer #(
      .MAX_DATA(MAX_DATA)
  ) tb (
      .clk(clk),
      .rst(rst),
      .clear(tb_clear_i),
      .backspace(tb_back_i),
      .append(tb_append),
      .append_len(tb_append_len),
      .append_bus(tb_append_bus),
      .load(buf_load),
      .load_len(buf_load_len),
      .load_bus(buf_load_bus),
      .len(buffer_len),
      .mem(buffer_flat)
  );

endmodule

module compute_link #(
    parameter integer CLK_HZ   = 100_000_000,
    parameter integer MAX_DATA = 32
) (
    input wire clk,
    input wire rst,

    // From input_core
    input wire                  is_equal,
    input wire                  is_clear,
    input wire [           7:0] expr_len,
    input wire [8*MAX_DATA-1:0] expr_bus,

    // To text_buffer
    output reg                  load_buf,
    output reg [           7:0] load_len,
    output reg [8*MAX_DATA-1:0] load_bus,

    // Graph interface
    input  wire               graph_start,
    input  wire signed [31:0] graph_x_q16_16,
    output reg signed  [31:0] graph_y_q16_16,
    output reg                graph_y_valid,
    output wire               graph_y_ready,
    output reg                graph_mode,

    // Debug outputs
    output wire [7:0] debug_state,
    output wire [7:0] debug_req_count
);

  reg         [           7:0] stored_expr_len;
  reg         [8*MAX_DATA-1:0] stored_expr_bus;

  // Expression evaluator
  reg                          eval_start;
  wire signed [          31:0] eval_result;
  wire        [           7:0] eval_error;
  wire                         eval_done;

  expression_evaluator #(
      .MAX_LEN(MAX_DATA),
      .MAX_TOKENS(32)
  ) evaluator (
      .clk(clk),
      .rst(rst),
      .start(eval_start),
      .expr_in(stored_expr_bus),
      .expr_len(stored_expr_len),
      .x_value(graph_x_q16_16),
      .result(eval_result),
      .error_flags(eval_error),
      .done(eval_done),
      .debug_first_reg()
  );

  // Integer to ASCII converter
  reg conv_start;
  wire conv_done;
  wire [7:0] conv_len;
  wire [8*MAX_DATA-1:0] conv_bus;

  int32_to_ascii #(
      .MAX_LEN(MAX_DATA)
  ) converter (
      .clk(clk),
      .rst(rst),
      .start(conv_start),
      .value(eval_result),
      .done(conv_done),
      .out_len(conv_len),
      .out_bus(conv_bus)
  );

  localparam S_IDLE = 3'd0;
  localparam S_WAIT_EVAL = 3'd1;
  localparam S_CONVERT = 3'd2;
  localparam S_WAIT_CONV = 3'd3;

  reg [2:0] state;
  reg pending_clear, pending_compute;
  reg [7:0] req_count;
  reg graph_y_ready_internal;

  assign graph_y_ready = graph_y_ready_internal & ~graph_start;
  assign debug_state = {5'd0, state};
  assign debug_req_count = req_count;

  integer i;

  always @(posedge clk) begin
    if (rst) begin
      state <= S_IDLE;
      eval_start <= 1'b0;
      conv_start <= 1'b0;
      pending_clear <= 1'b0;
      pending_compute <= 1'b0;
      load_buf <= 1'b0;
      load_len <= 8'd0;
      load_bus <= 0;
      graph_mode <= 1'b0;
      stored_expr_len <= 8'd0;
      stored_expr_bus <= 0;
      graph_y_q16_16 <= 32'sd0;
      graph_y_valid <= 1'b0;
      graph_y_ready_internal <= 1'b0;
      req_count <= 8'd0;
    end else begin
      eval_start <= 1'b0;
      conv_start <= 1'b0;
      load_buf <= 1'b0;
      graph_y_valid <= 1'b0;

      if (is_clear) begin
        pending_clear <= 1'b1;
        graph_mode <= 1'b0;
        state <= S_IDLE;
      end
      if (is_equal) pending_compute <= 1'b1;

      case (state)
        S_IDLE: begin
          if (graph_mode) begin
            graph_y_ready_internal <= 1'b1;
            if (graph_start) begin
              eval_start <= 1'b1;
              req_count <= req_count + 8'd1;
              graph_y_ready_internal <= 1'b0;
              state <= S_WAIT_EVAL;
            end
          end else if (pending_clear) begin
            pending_clear <= 1'b0;
          end else if (pending_compute) begin
            graph_mode <= 1'b1;
            stored_expr_len <= (expr_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : expr_len;
            stored_expr_bus <= expr_bus;
            pending_compute <= 1'b0;
            req_count <= 8'd0;
            graph_y_ready_internal <= 1'b1;
            // Evaluate once for display
            eval_start <= 1'b1;
            state <= S_CONVERT;
          end
        end

        S_WAIT_EVAL: begin
          if (eval_done) begin
            graph_y_q16_16 <= eval_result << 16;  // Integer to Q16.16
            graph_y_valid <= 1'b1;
            graph_y_ready_internal <= 1'b1;
            state <= S_IDLE;
          end
        end

        S_CONVERT: begin
          if (eval_done) begin
            conv_start <= 1'b1;
            state <= S_WAIT_CONV;
          end
        end

        S_WAIT_CONV: begin
          if (conv_done) begin
            load_buf <= 1'b1;
            load_len <= conv_len;
            load_bus <= conv_bus;
            state <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end
endmodule

module student_input #(
    parameter integer CLK_HZ     = 100_000_000,
    parameter integer MAX_DATA   = 32,
    parameter integer FONT_SCALE = 2
) (
    input wire clk,
    input wire rst,
    input wire up_p,
    down_p,
    left_p,
    right_p,
    confirm_p,
    input wire [1:0] kb_sel,

    // Mouse input
    input wire [6:0] mouse_x,
    input wire [5:0] mouse_y,
    input wire       mouse_left,

    // Graph interface
    input  wire               graph_start,
    input  wire signed [31:0] graph_x_q16_16,
    output wire signed [31:0] graph_y_q16_16,
    output wire               graph_y_valid,
    output wire               graph_y_ready,
    output wire               graph_mode,

    input  wire        clk_pix,
    output wire [ 7:0] oled_keypad_out,
    output wire [ 7:0] oled_text_out,
    output wire [15:0] debug_led
);
  localparam [8*16-1:0] KB0_LAYOUT = {"/=0C", "*987", "-654", "+321"};

  localparam [8*16-1:0] KB1_LAYOUT = {
    `TAN_KEY, `COS_KEY, `SIN_KEY, `BACK_KEY, "%><", `PI_KEY, "^&|~", ".)(x"
  };

  localparam [8*12-1:0] KB2_LAYOUT = {
    `CEIL_KEY,
    `FLOOR_KEY,
    `BACK_KEY,
    `ROUND_KEY,
    `MAX_KEY,
    `MIN_KEY,
    `POW_KEY,
    `SQRT_KEY,
    `ABS_KEY,
    "e",
    `LN_KEY,
    `LOG_KEY
  };

  wire [8*MAX_DATA-1:0] buffer_flat;
  wire [           7:0] buffer_len8;
  wire is_clear, is_equal;
  wire                  load_buf;
  wire [           7:0] load_len;
  wire [8*MAX_DATA-1:0] load_bus;
  wire [           7:0] debug_state;
  wire [           7:0] debug_req_count;

  input_core #(
      .CLK_HZ(CLK_HZ),
      .MAX_DATA(MAX_DATA),
      .FONT_SCALE(1),
      .KB0_LAYOUT(KB0_LAYOUT),
      .KB1_LAYOUT(KB1_LAYOUT),
      .KB2_LAYOUT(KB2_LAYOUT)
  ) core (
      .clk(clk),
      .rst(rst),
      .up_p(up_p),
      .down_p(down_p),
      .left_p(left_p),
      .right_p(right_p),
      .confirm_p(confirm_p),
      .kb_sel(kb_sel),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_left(mouse_left),
      .buf_load(load_buf),
      .buf_load_len(load_len),
      .buf_load_bus(load_bus),
      .buffer_flat(buffer_flat),
      .buffer_len(buffer_len8),
      .is_clear(is_clear),
      .is_equal(is_equal),
      .clk_pix(clk_pix),
      .oled_out(oled_keypad_out)
  );

  compute_link #(
      .CLK_HZ  (CLK_HZ),
      .MAX_DATA(MAX_DATA)
  ) link (
      .clk(clk),
      .rst(rst),
      .is_equal(is_equal),
      .is_clear(is_clear),
      .expr_len(buffer_len8),
      .expr_bus(buffer_flat),
      .load_buf(load_buf),
      .load_len(load_len),
      .load_bus(load_bus),
      .graph_start(graph_start),
      .graph_x_q16_16(graph_x_q16_16),
      .graph_y_q16_16(graph_y_q16_16),
      .graph_y_valid(graph_y_valid),
      .graph_y_ready(graph_y_ready),
      .graph_mode(graph_mode),
      .debug_state(debug_state),
      .debug_req_count(debug_req_count)
  );

  text_oled #(
      .FONT_SCALE(FONT_SCALE),
      .MAX_DATA  (MAX_DATA)
  ) tgr (
      .clk_pix(clk_pix),
      .rst(rst),
      .oled_out(oled_text_out),
      .text_len(buffer_len8),
      .text_bus(buffer_flat)
  );

  assign debug_led[15]   = graph_mode;
  assign debug_led[14]   = graph_y_ready;
  assign debug_led[13]   = graph_y_valid;
  assign debug_led[12]   = graph_start;
  assign debug_led[11]   = 1'b0;
  assign debug_led[10:9] = debug_state[1:0];
  assign debug_led[8:7]  = kb_sel;
  assign debug_led[6:0]  = debug_req_count[6:0];
endmodule
