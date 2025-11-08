`timescale 1ns / 1ps
`include "constants.vh"

module text_buffer #(
    parameter integer MAX_DATA = 32
) (
    input wire clk,
    input wire rst,
    input wire clear,
    input wire backspace,

    input wire       append,
    input wire [7:0] append_byte,

    input wire                  load,
    input wire [           7:0] load_len,
    input wire [8*MAX_DATA-1:0] load_bus,

    output reg [           7:0] len,
    output reg [8*MAX_DATA-1:0] mem
);
  integer i;
  wire [7:0] cap_len = (load_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : load_len;

  always @(posedge clk) begin
    if (rst || clear) begin
      len <= 8'd0;
      mem <= 0;
    end else if (load) begin
      for (i = 0; i < MAX_DATA; i = i + 1) begin
        if (i < cap_len) mem[8*i+:8] <= load_bus[8*i+:8];
        else mem[8*i+:8] <= 8'h00;
      end
      len <= cap_len;
    end else if (backspace && (len > 0)) begin
      len <= len - 8'd1;
      mem[8*(len-1)+:8] <= 8'h00;
    end else if (append && (len < MAX_DATA[7:0])) begin
      mem[8*len+:8] <= append_byte;
      len <= len + 8'd1;
    end
  end
endmodule

module token_to_ascii_decoder #(
    parameter integer MAX_DATA = 32
) (
    input wire clk,
    input wire rst,

    input wire [8*MAX_DATA-1:0] token_buf,
    input wire [           7:0] token_len,

    output reg [8*MAX_DATA-1:0] ascii_buf,
    output reg [           7:0] ascii_len
);
  // ----------------------------
  // Internal snapshot & workbuf
  // ----------------------------
  reg [8*MAX_DATA-1:0] tok_snap;  // snapshot of token_buf at start
  reg [8*MAX_DATA-1:0] ascii_work;  // build result here
  reg [           7:0] ascii_len_work;

  // ----------------------------
  // Control
  // ----------------------------
  localparam S_IDLE = 3'd0;
  localparam S_SNAP = 3'd1;
  localparam S_DECODE = 3'd2;
  localparam S_EMIT = 3'd3;
  localparam S_COMMIT = 3'd4;

  reg [2:0] state, state_n;

  reg [ 7:0] start_len;  // token_len latched at start
  reg [ 7:0] i_tok;  // token index (0..start_len-1)
  reg [ 2:0] j_emit;  // emitted chars for current token (0..exp_len-1)
  reg [ 7:0] out_idx;  // total output bytes written (0..MAX_DATA)

  // expansion of current token
  reg [ 7:0] tok;
  reg [ 2:0] exp_len;  // 0..5
  reg [39:0] exp_bytes;  // 5 bytes max, LSB-first = first to write

  // pending restart if token_len changed mid-run
  reg        pending_start;

  // ---------------------------------
  // Expansion dictionary (combinational)
  // ---------------------------------
  always @* begin
    tok       = tok_snap[8*i_tok+:8];
    exp_len   = 3'd1;
    exp_bytes = {32'h0000_0000, tok};  // default: passthrough

    case (tok)
      `SIN_KEY: begin
        exp_len   = 3'd3;
        exp_bytes = {16'h0000, "n", "i", "s"};
      end
      `COS_KEY: begin
        exp_len   = 3'd3;
        exp_bytes = {16'h0000, "s", "o", "c"};
      end
      `TAN_KEY: begin
        exp_len   = 3'd3;
        exp_bytes = {16'h0000, "n", "a", "t"};
      end
      `LN_KEY: begin
        exp_len   = 3'd2;
        exp_bytes = {24'h000000, "n", "l"};
      end
      `LOG_KEY: begin
        exp_len   = 3'd3;
        exp_bytes = {16'h0000, "g", "o", "l"};
      end
      `ABS_KEY: begin
        exp_len   = 3'd3;
        exp_bytes = {16'h0000, "s", "b", "a"};
      end
      `FLOOR_KEY: begin
        exp_len   = 3'd5;
        exp_bytes = {"r", "o", "o", "l", "f"};
      end
      `CEIL_KEY: begin
        exp_len   = 3'd4;
        exp_bytes = {8'h00, "l", "i", "e", "c"};
      end
      `ROUND_KEY: begin
        exp_len   = 3'd5;
        exp_bytes = {"d", "n", "u", "o", "r"};
      end
      `MIN_KEY: begin
        exp_len   = 3'd3;
        exp_bytes = {16'h0000, "n", "i", "m"};
      end
      `MAX_KEY: begin
        exp_len   = 3'd3;
        exp_bytes = {16'h0000, "x", "a", "m"};
      end
      `POW_KEY: begin
        exp_len   = 3'd3;
        exp_bytes = {16'h0000, "w", "o", "p"};
      end
      default: ;  // passthrough already set
    endcase
  end

  // ---------------------------------
  // Next-state logic
  // ---------------------------------
  always @* begin
    state_n = state;
    case (state)
      S_IDLE: if (token_len != start_len) state_n = S_SNAP;
      S_SNAP: state_n = S_DECODE;
      S_DECODE:
      if (i_tok >= start_len || out_idx >= MAX_DATA) state_n = S_COMMIT;
      else state_n = S_EMIT;
      S_EMIT: if (j_emit >= exp_len || out_idx >= MAX_DATA) state_n = S_DECODE;
      S_COMMIT: state_n = (pending_start ? S_SNAP : S_IDLE);
      default: state_n = S_IDLE;
    endcase
  end

  // ---------------------------------
  // State & datapath
  // ---------------------------------
  integer k;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state          <= S_IDLE;
      ascii_buf      <= {8 * MAX_DATA{1'b0}};
      ascii_len      <= 8'd0;
      ascii_work     <= {8 * MAX_DATA{1'b0}};
      ascii_len_work <= 8'd0;
      start_len      <= 8'd0;
      tok_snap       <= {8 * MAX_DATA{1'b0}};
      i_tok          <= 8'd0;
      j_emit         <= 3'd0;
      out_idx        <= 8'd0;
      pending_start  <= 1'b0;
    end else begin
      state <= state_n;

      // Detect changes during busy work; queue a restart
      if (state != S_IDLE && token_len != start_len) pending_start <= 1'b1;

      case (state)
        S_IDLE: begin
          // accept new start immediately from IDLE
          if (token_len != start_len) begin
            pending_start <= 1'b0;
          end
        end

        S_SNAP: begin
          // Snapshot inputs and reset work buffers
          tok_snap       <= token_buf;  // 256 FFs; keeps fanout small during decode
          start_len      <= token_len;
          ascii_work     <= {8 * MAX_DATA{1'b0}};
          ascii_len_work <= 8'd0;
          i_tok          <= 8'd0;
          j_emit         <= 3'd0;
          out_idx        <= 8'd0;
          // (Optional alternative behavior)
          // If you prefer "abort & restart immediately", you can also clear pending_start here:
          // pending_start   <= 1'b0;
        end

        S_DECODE: begin
          if (i_tok >= start_len || out_idx >= MAX_DATA) begin
            // fall through to COMMIT next
          end else begin
            // prepare to emit current token's bytes
            j_emit <= 3'd0;
          end
        end

        S_EMIT: begin
          if (j_emit < exp_len && out_idx < MAX_DATA) begin
            // Write one byte into work buffer at [out_idx]
            ascii_work[8*out_idx+:8] <= exp_bytes[8*j_emit+:8];
            out_idx                  <= out_idx + 1'b1;
            j_emit                   <= j_emit + 1'b1;
            ascii_len_work           <= out_idx + 1'b1;  // tracks number of bytes written
          end
          if (j_emit >= exp_len || out_idx >= MAX_DATA) begin
            i_tok <= i_tok + 1'b1;  // next token on next DECODE
          end
        end

        S_COMMIT: begin
          // Atomically publish new result at the end
          ascii_buf <= ascii_work;
          ascii_len <= ascii_len_work;

          // If a new length arrived mid-run, start next cycle; else go idle
          if (pending_start) begin
            // prepare for the next S_SNAP
            pending_start <= 1'b0;
          end
        end

        default: ;
      endcase
    end
  end

endmodule


module scroll_page_ctrl (
    input wire clk,
    input wire rst,
    input wire [3:0] mouse_z,
    input wire [1:0] num_pages,
    output reg [1:0] page_sel
);
  reg [3:0] last_z;
  wire signed [3:0] z_signed = $signed(mouse_z);
  wire signed [3:0] last_z_signed = $signed(last_z);
  wire z_scroll_up = (z_signed > 4'sd0) && (last_z_signed == 4'sd0);
  wire z_scroll_down = (z_signed < 4'sd0) && (last_z_signed == 4'sd0);

  always @(posedge clk) begin
    if (rst) begin
      page_sel <= 2'd0;
      last_z   <= 4'd0;
    end else begin
      last_z <= mouse_z;
      if (z_scroll_up && (page_sel < num_pages)) begin
        page_sel <= page_sel + 2'd1;
      end else if (z_scroll_down && (page_sel > 0)) begin
        page_sel <= page_sel - 2'd1;
      end
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
    parameter [8*16-1:0] KB0_LAYOUT = 0,
    parameter [8*16-1:0] KB1_LAYOUT = 0,
    parameter [8*12-1:0] KB2_LAYOUT = 0,
    parameter OLED_ROTATE_180 = 0
) (
    input wire clk,
    input wire rst,

    input wire up_p,
    down_p,
    left_p,
    right_p,
    confirm_p,

    input wire [6:0] mouse_x,
    input wire [5:0] mouse_y,
    input wire [3:0] mouse_z,
    input wire       mouse_left,
    input wire       mouse_active,

    input wire                  buf_load,
    input wire [           7:0] buf_load_len,
    input wire [8*MAX_DATA-1:0] buf_load_bus,

    output wire [8*MAX_DATA-1:0] buffer_flat,
    output wire [           7:0] buffer_len,

    output wire is_clear,
    output wire is_equal,

    input  wire       clk_pix,
    output wire [7:0] oled_out
);
  wire [1:0] kb_sel;
  scroll_page_ctrl scroll_ctrl (
      .clk(clk),
      .rst(rst),
      .mouse_z(mouse_z),
      .num_pages(2'd2),
      .page_sel(kb_sel)
  );

  wire [2:0] focus_row_0, focus_col_0;
  wire [2:0] focus_row_1, focus_col_1;
  wire [2:0] focus_row_2, focus_col_2;

  wire ap0, ap1, ap2;
  wire [7:0] ab0, ab1, ab2;
  wire cl0, cl1, cl2;
  wire bk0, bk1, bk2;
  wire eq0, eq1, eq2;

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
      .mouse_active(mouse_active),
      .tb_append(ap0),
      .tb_append_byte(ab0),
      .tb_clear(cl0),
      .tb_back(bk0),
      .is_equal(eq0),
      .focus_row(focus_row_0),
      .focus_col(focus_col_0)
  );

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
      .mouse_active(mouse_active),
      .tb_append(ap1),
      .tb_append_byte(ab1),
      .tb_clear(cl1),
      .tb_back(bk1),
      .is_equal(eq1),
      .focus_row(focus_row_1),
      .focus_col(focus_col_1)
  );

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
      .mouse_active(mouse_active),
      .tb_append(ap2),
      .tb_append_byte(ab2),
      .tb_clear(cl2),
      .tb_back(bk2),
      .is_equal(eq2),
      .focus_row(focus_row_2),
      .focus_col(focus_col_2)
  );

  wire       tb_append = (kb_sel == 2'd0) ? ap0 : (kb_sel == 2'd1) ? ap1 : ap2;
  wire [7:0] tb_append_byte = (kb_sel == 2'd0) ? ab0 : (kb_sel == 2'd1) ? ab1 : ab2;
  wire       tb_clear_i = (kb_sel == 2'd0) ? cl0 : (kb_sel == 2'd1) ? cl1 : cl2;
  wire       tb_back_i = (kb_sel == 2'd0) ? bk0 : (kb_sel == 2'd1) ? bk1 : bk2;
  assign is_equal = (kb_sel == 2'd0) ? eq0 : (kb_sel == 2'd1) ? eq1 : eq2;
  assign is_clear = tb_clear_i;

  wire [2:0] focus_row = (kb_sel == 2'd0) ? focus_row_0 : (kb_sel == 2'd1) ? focus_row_1 : focus_row_2;
  wire [2:0] focus_col = (kb_sel == 2'd0) ? focus_col_0 : (kb_sel == 2'd1) ? focus_col_1 : focus_col_2;

  wire [12:0] pixel_index;
  wire [12:0] actual_pixel_index;

  generate
    if (OLED_ROTATE_180) begin : gen_rotate
      assign actual_pixel_index = (`DISP_W * `DISP_H - 1) - pixel_index;
    end else begin : gen_no_rotate
      assign actual_pixel_index = pixel_index;
    end
  endgenerate

  wire [15:0] pixel_color_0;
  wire [15:0] pixel_color_1;
  wire [15:0] pixel_color_2;

  keypad_renderer #(
      .FONT_SCALE(FONT_SCALE),
      .GRID_ROWS (4),
      .GRID_COLS (4),
      .KB_LAYOUT (KB0_LAYOUT)
  ) rend0 (
      .pixel_index(actual_pixel_index),
      .focus_row(focus_row_0),
      .focus_col(focus_col_0),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_left(mouse_left),
      .mouse_active(mouse_active),
      .pixel_color(pixel_color_0)
  );

  keypad_renderer #(
      .FONT_SCALE(FONT_SCALE),
      .GRID_ROWS (4),
      .GRID_COLS (4),
      .KB_LAYOUT (KB1_LAYOUT)
  ) rend1 (
      .pixel_index(actual_pixel_index),
      .focus_row(focus_row_1),
      .focus_col(focus_col_1),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_left(mouse_left),
      .mouse_active(mouse_active),
      .pixel_color(pixel_color_1)
  );

  keypad_renderer #(
      .FONT_SCALE(FONT_SCALE),
      .GRID_ROWS (4),
      .GRID_COLS (3),
      .KB_LAYOUT (KB2_LAYOUT)
  ) rend2 (
      .pixel_index(actual_pixel_index),
      .focus_row(focus_row_2),
      .focus_col(focus_col_2),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_left(mouse_left),
      .mouse_active(mouse_active),
      .pixel_color(pixel_color_2)
  );

  wire [15:0] pixel_color = (kb_sel == 2'd0) ? pixel_color_0 : 
                            (kb_sel == 2'd1) ? pixel_color_1 : 
                            pixel_color_2;

  oled u_oled (
      .clk_6p25m  (clk_pix),
      .rst        (rst),
      .pixel_color(pixel_color),
      .oled_out   (oled_out),
      .pixel_index(pixel_index)
  );

  text_buffer #(
      .MAX_DATA(MAX_DATA)
  ) tb (
      .clk(clk),
      .rst(rst),
      .clear(tb_clear_i),
      .backspace(tb_back_i),
      .append(tb_append),
      .append_byte(tb_append_byte),
      .load(buf_load),
      .load_len(buf_load_len),
      .load_bus(buf_load_bus),
      .len(buffer_len),
      .mem(buffer_flat)
  );

endmodule

module student_input #(
    parameter integer CLK_HZ          = 100_000_000,
    parameter integer MAX_DATA        = 32,
    parameter integer FONT_SCALE      = 2,
    parameter         OLED_ROTATE_180 = 0
) (
    input wire clk,
    input wire rst,
    input wire up_p,
    down_p,
    left_p,
    right_p,
    confirm_p,

    input wire [6:0] mouse_x,
    input wire [5:0] mouse_y,
    input wire [3:0] mouse_z,
    input wire       mouse_left,
    input wire       mouse_active,

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
    `TAN_KEY, `COS_KEY, `SIN_KEY, `BACK_KEY, "><x", `PI_KEY, `XOR_KEY, "&|~", ".)(^"
  };

  localparam [8*12-1:0] KB2_LAYOUT = {
    `CEIL_KEY,
    `FLOOR_KEY,
    `BACK_KEY,
    `ROUND_KEY,
    `MAX_KEY,
    `MIN_KEY,
    ",",
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
  wire [           1:0] kb_sel;

  input_core #(
      .CLK_HZ(CLK_HZ),
      .MAX_DATA(MAX_DATA),
      .FONT_SCALE(1),
      .KB0_LAYOUT(KB0_LAYOUT),
      .KB1_LAYOUT(KB1_LAYOUT),
      .KB2_LAYOUT(KB2_LAYOUT),
      .OLED_ROTATE_180(OLED_ROTATE_180)
  ) core (
      .clk(clk),
      .rst(rst),
      .up_p(up_p),
      .down_p(down_p),
      .left_p(left_p),
      .right_p(right_p),
      .confirm_p(confirm_p),
      .mouse_x(mouse_x),
      .mouse_y(mouse_y),
      .mouse_z(mouse_z),
      .mouse_left(mouse_left),
      .mouse_active(mouse_active),
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

  wire [8*MAX_DATA-1:0] display_buf;
  wire [           7:0] display_len;
  token_to_ascii_decoder #(
      .MAX_DATA(MAX_DATA)
  ) decoder (
      .clk(clk),
      .rst(rst),
      .token_buf(buffer_flat),
      .token_len(buffer_len8),
      .ascii_buf(display_buf),
      .ascii_len(display_len)
  );

  text_oled #(
      .FONT_SCALE(FONT_SCALE),
      .MAX_DATA  (MAX_DATA)
  ) tgr (
      .clk_pix(clk_pix),
      .rst(rst),
      .oled_out(oled_text_out),
      .text_len(display_len),
      .text_bus(display_buf)
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
