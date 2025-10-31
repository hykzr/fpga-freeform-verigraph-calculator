`timescale 1ns / 1ps
`include "constants.vh"
// text_buffer.v  — supports append (<=4 bytes) and replace (<=MAX_DATA)
module text_buffer #(
    parameter integer MAX_DATA = 32
) (
    input wire clk,
    input wire rst,
    input wire clear,

    // ===== append path (keypad emit) =====
    input wire        append,      // 1-cycle pulse
    input wire [ 2:0] append_len,  // 0..4
    input wire [31:0] append_bus,  // byte i at [8*i +: 8], LSB-first

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
    end else if (append && (append_len != 0) && (len < MAX_DATA[7:0])) begin
      // Append: clamp to capacity
      for (j = 0; j < 4; j = j + 1) begin
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
    parameter [8*16-1:0] KB0_LAYOUT = 0,  // Change in student_input
    parameter [8*16-1:0] KB1_LAYOUT = 0  // Change in student_input
) (
    input wire clk,
    input wire rst,

    input wire up_p,
    down_p,
    left_p,
    right_p,
    confirm_p,
    input wire kb_sel,

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

  wire [15:0] col0, col1;
  wire ap0, ap1;  // append pulse
  wire [2:0] al0, al1;  // append len
  wire [31:0] ab0, ab1;  // append bus
  wire cl0, cl1;  // clear pulse
  wire eq0, eq1;  // equals pulse

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
      .clk_pix(clk_pix),
      .oled_out(oled_out_0),
      .tb_append(ap0),
      .tb_append_len(al0),
      .tb_append_bus(ab0),
      .tb_clear(cl0),
      .is_equal(eq0),
      .focus_row(),
      .focus_col()
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
      .clk_pix(clk_pix),
      .oled_out(oled_out_1),
      .tb_append(ap1),
      .tb_append_len(al1),
      .tb_append_bus(ab1),
      .tb_clear(cl1),
      .is_equal(eq1),
      .focus_row(),
      .focus_col()
  );
  wire        tb_append = kb_sel ? ap1 : ap0;
  wire [ 2:0] tb_append_len = kb_sel ? al1 : al0;
  wire [31:0] tb_append_bus = kb_sel ? ab1 : ab0;
  wire        tb_clear_i = kb_sel ? cl1 : cl0;
  assign is_equal = kb_sel ? eq1 : eq0;
  assign is_clear = tb_clear_i;
  assign oled_out = kb_sel ? oled_out_1 : oled_out_0;

  text_buffer #(
      .MAX_DATA(MAX_DATA)
  ) tb (
      .clk(clk),
      .rst(rst),
      .clear(tb_clear_i),
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
    parameter integer CLK_HZ    = 100_000_000,
    parameter integer BAUD_RATE = 115200,
    parameter integer MAX_DATA  = 32
) (
    input wire clk,
    input wire rst,

    // Triggers from input_core
    input wire                  is_equal,  // 1-cycle
    input wire                  is_clear,  // 1-cycle
    input wire [           7:0] expr_len,  // 0..MAX_DATA
    input wire [8*MAX_DATA-1:0] expr_bus,  // ASCII payload

    // UART
    input  wire rx,
    output wire tx,

    // To text_buffer (bulk load of RESULT)
    output reg                  load_buf,  // 1-cycle pulse
    output reg [           7:0] load_len,
    output reg [8*MAX_DATA-1:0] load_bus,

    // optional status
    output wire tx_busy,
    output wire rx_frame_valid,
    output wire rx_chk_ok
);
  // ---------------- TX ----------------
  reg                   ptx_start;
  reg  [           7:0] ptx_cmd;
  reg  [           7:0] ptx_len;  // N
  reg  [8*MAX_DATA-1:0] ptx_bus;
  wire                  ptx_busy;

  proto_tx #(
      .CLK_FREQ (CLK_HZ),
      .BAUD_RATE(BAUD_RATE),
      .MAX_DATA (MAX_DATA)
  ) TX (
      .clk(clk),
      .rst(rst),
      .start(ptx_start),
      .cmd(ptx_cmd),
      .data_len(ptx_len),
      .data_bus(ptx_bus),
      .busy(ptx_busy),
      .tx(tx)
  );
  assign tx_busy = ptx_busy;

  // ---------------- RX ----------------
  wire prx_valid, prx_chk;
  wire [7:0] prx_cmd;
  wire [7:0] prx_len;
  wire [8*MAX_DATA-1:0] prx_bus;

  proto_rx #(
      .CLK_FREQ (CLK_HZ),
      .BAUD_RATE(BAUD_RATE),
      .MAX_DATA (MAX_DATA)
  ) RX (
      .clk(clk),
      .rst(rst),
      .rx(rx),
      .frame_valid(prx_valid),
      .chk_ok(prx_chk),
      .cmd(prx_cmd),
      .data_len(prx_len),
      .data_bus(prx_bus)
  );
  assign rx_frame_valid = prx_valid;
  assign rx_chk_ok      = prx_chk;

  // ---------------- Scheduler ----------------
  // Queue '=' and 'C' while TX is busy. CLEAR has priority.
  reg pending_clear, pending_compute;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      ptx_start       <= 1'b0;
      ptx_cmd         <= 8'h00;
      ptx_len         <= 8'd0;
      ptx_bus         <= {8 * MAX_DATA{1'b0}};
      pending_clear   <= 1'b0;
      pending_compute <= 1'b0;
      load_buf        <= 1'b0;
      load_len        <= 8'd0;
      load_bus        <= {8 * MAX_DATA{1'b0}};
    end else begin
      ptx_start <= 1'b0;
      load_buf  <= 1'b0;

      // latch triggers
      if (is_clear) pending_clear <= 1'b1;
      if (is_equal) pending_compute <= 1'b1;

      // launch when free
      if (!ptx_busy) begin
        if (pending_clear) begin
          ptx_cmd <= `CMD_CLEAR;
          ptx_len <= 8'd0;
          ptx_bus <= {8 * MAX_DATA{1'b0}};
          ptx_start <= 1'b1;
          pending_clear <= 1'b0;
        end else if (pending_compute) begin
          ptx_cmd <= `CMD_COMPUTE;
          ptx_len <= (expr_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : expr_len;
          ptx_bus <= expr_bus;
          ptx_start <= 1'b1;
          pending_compute <= 1'b0;
        end
      end

      // apply RESULT
      if (prx_valid && prx_chk && (prx_cmd == `CMD_RESULT)) begin
        load_len <= (prx_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : prx_len;
        load_bus <= prx_bus;
        load_buf <= 1'b1;
      end
    end
  end
endmodule

module student_input #(
    parameter integer CLK_HZ     = 100_000_000,
    parameter integer BAUD_RATE  = 115200,
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
    input wire kb_sel,

    input  wire rx,
    output wire tx,

    input  wire       clk_pix,          // 6.25 MHz
    output wire [7:0] oled_keypad_out,
    output wire [7:0] oled_text_out,

    output wire [15:0] debug_led
);
  localparam [8*16-1:0] KB0_LAYOUT = {"/=0C", "*987", "-654", "+321"};
  localparam [8*16-1:0] KB1_LAYOUT = {
    `TAN_KEY, `COS_KEY, `SIN_KEY, "C", `SQRT_KEY, `LN_KEY, `LOG_KEY, `PI_KEY, "^&|~", ".)(e"
  };

  wire [8*MAX_DATA-1:0] buffer_flat;
  wire [           7:0] buffer_len8;
  wire is_clear, is_equal;

  // external result load from compute_link
  wire                  load_buf;
  wire [           7:0] load_len;
  wire [8*MAX_DATA-1:0] load_bus;

  input_core #(
      .CLK_HZ(CLK_HZ),
      .DEBOUNCE_MS(20),
      .REPEAT_START_MS(500),
      .REPEAT_INTERVAL_MS(60),
      .MAX_DATA(MAX_DATA),
      .FONT_SCALE(1),
      .KB0_LAYOUT(KB0_LAYOUT),
      .KB1_LAYOUT(KB1_LAYOUT)
  ) core (
      .clk(clk),
      .rst(rst),
      .up_p(up_p),
      .down_p(down_p),
      .left_p(left_p),
      .right_p(right_p),
      .confirm_p(confirm_p),
      .kb_sel(kb_sel),

      .buf_load(load_buf),
      .buf_load_len(load_len),
      .buf_load_bus(load_bus),

      .buffer_flat(buffer_flat),
      .buffer_len(buffer_len8),
      .is_clear(is_clear),
      .is_equal(is_equal),

      .clk_pix (clk_pix),
      .oled_out(oled_keypad_out)
  );

  // ---------- compute_link ----------
  compute_link #(
      .CLK_HZ(CLK_HZ),
      .BAUD_RATE(BAUD_RATE),
      .MAX_DATA(MAX_DATA)
  ) link (
      .clk(clk),
      .rst(rst),
      .is_equal(is_equal),
      .is_clear(is_clear),
      .expr_len(buffer_len8),
      .expr_bus(buffer_flat),
      .rx(rx),
      .tx(tx),
      .load_buf(load_buf),
      .load_len(load_len),
      .load_bus(load_bus),
      .tx_busy(),
      .rx_frame_valid(),
      .rx_chk_ok()
  );

  // ---------- OLED #2: Text buffer ----------
  wire [12:0] txt_pix_idx;
  wire [15:0] txt_pix_col;

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

  // ---------- debug LEDs ----------
  assign debug_led[15]   = 1'b0;
  assign debug_led[14:9] = buffer_len8[5:0];
  assign debug_led[8]    = kb_sel;
  assign debug_led[7:2]  = 6'b0;
  assign debug_led[1]    = is_clear;
  assign debug_led[0]    = is_equal;
endmodule
