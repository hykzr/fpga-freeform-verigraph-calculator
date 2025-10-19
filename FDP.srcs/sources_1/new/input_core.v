`timescale 1ns / 1ps
`include "constants.vh"
module text_uart_sync #(
    parameter integer CLK_FREQ = 100_000_000,
    parameter integer BAUD_RATE = 115200,
    parameter integer BUF_DEPTH = 32,  // width of buffer_flat (bytes)
    parameter integer MAX_DATA = 32  // max bytes we will send in one frame (<= 254 ideally)
) (
    input wire clk,
    input wire rst,

    // From input_core
    input wire [8*BUF_DEPTH-1:0] buffer_flat,  // byte i at [8*i +: 8]
    input wire [            7:0] buffer_len,   // widen to 8-bit at source (zero-extend)
    input wire                   is_clear,     // 1-cycle strobe

    // UART out
    output wire tx,
    output wire busy  // proto busy (so top can know when link’s occupied)
);

  // ------------------------------------------------------------
  // Internal snapshot & change detection
  // ------------------------------------------------------------
  // We keep a snapshot of the last-sent data (len + data[0..MAX_DATA-1]).
  reg     [           7:0] prev_len;  // last N sent (capped at MAX_DATA)
  reg     [8*MAX_DATA-1:0] prev_bus;  // last payload sent (only first prev_len bytes meaningful)

  // Current capped length N = min(buffer_len, MAX_DATA)
  wire    [           7:0] n_cur = (buffer_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : buffer_len;

  // Build a capped/padded view of the buffer (first N bytes; rest zero)
  reg     [8*MAX_DATA-1:0] cur_bus;
  integer                  i;
  always @* begin
    // default zero
    cur_bus = {8 * MAX_DATA{1'b0}};
    // copy first N bytes from buffer_flat
    for (i = 0; i < MAX_DATA; i = i + 1) begin
      if (i < n_cur) cur_bus[8*i+:8] = buffer_flat[8*i+:8];
      // else keep zero
    end
  end

  // Has content changed vs the last sent snapshot?
  wire                  changed = (n_cur != prev_len) || (cur_bus != prev_bus);

  // Latch any activity while TX is busy
  reg                   pending_text;
  reg                   pending_clear;

  // ------------------------------------------------------------
  // proto_tx instance
  // ------------------------------------------------------------
  reg                   ptx_start;
  reg  [           7:0] ptx_cmd;
  reg  [           7:0] ptx_len;  // N (data count)
  reg  [8*MAX_DATA-1:0] ptx_bus;
  wire                  ptx_busy;

  proto_tx #(
      .CLK_FREQ (CLK_FREQ),
      .BAUD_RATE(BAUD_RATE),
      .MAX_DATA (MAX_DATA)
  ) UTX (
      .clk     (clk),
      .rst     (rst),
      .start   (ptx_start),
      .cmd     (ptx_cmd),
      .data_len(ptx_len),    // NOTE: this is N; proto sends LEN=(1+N)
      .data_bus(ptx_bus),
      .busy    (ptx_busy),
      .tx      (tx)
  );

  assign busy = ptx_busy;

  // ------------------------------------------------------------
  // Small scheduler: CLEAR has priority over TEXT.
  // Coalesce multiple edits while transmitter is busy.
  // ------------------------------------------------------------
  localparam ST_IDLE = 2'd0, ST_FIRE = 2'd1, ST_WAIT = 2'd2;
  reg [1:0] st;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      prev_len      <= 8'd0;
      prev_bus      <= {8 * MAX_DATA{1'b0}};
      pending_text  <= 1'b0;
      pending_clear <= 1'b0;
      ptx_start     <= 1'b0;
      ptx_cmd       <= 8'h00;
      ptx_len       <= 8'd0;
      ptx_bus       <= {8 * MAX_DATA{1'b0}};
      st            <= ST_IDLE;
    end else begin
      ptx_start <= 1'b0;  // default

      // collect events
      if (is_clear) pending_clear <= 1'b1;
      if (changed) pending_text <= 1'b1;

      case (st)
        ST_IDLE: begin
          // If TX line is free, emit pending events (CLEAR > TEXT)
          if (!ptx_busy) begin
            if (pending_clear) begin
              // send CLEAR (no data)
              ptx_cmd       <= `CMD_CLEAR;
              ptx_len       <= 8'd0;
              ptx_bus       <= {8 * MAX_DATA{1'b0}};
              ptx_start     <= 1'b1;
              st            <= ST_WAIT;
              // consume CLEAR now; we'll also let TEXT send afterwards if still pending
              pending_clear <= 1'b0;
            end else if (pending_text) begin
              // send TEXT (N bytes)
              ptx_cmd      <= `CMD_TEXT;
              ptx_len      <= n_cur;
              ptx_bus      <= cur_bus;
              ptx_start    <= 1'b1;
              st           <= ST_WAIT;

              // update snapshot NOW to latest contents (coalesce edits while busy)
              prev_len     <= n_cur;
              prev_bus     <= cur_bus;
              pending_text <= 1'b0;
            end
          end
        end

        ST_WAIT: begin
          // Wait until proto finishes the byte stream, then return to IDLE.
          if (!ptx_busy) begin
            st <= ST_IDLE;
          end
        end

        default: st <= ST_IDLE;
      endcase

      // If we’re idle and TX free, also refresh snapshot when buffer changed
      // (covers the case where we didn’t send yet because both pending flags were empty)
      if (st == ST_IDLE && !ptx_busy && changed && !pending_text && !pending_clear) begin
        prev_len <= n_cur;
        prev_bus <= cur_bus;
      end
    end
  end

endmodule

module text_buffer #(
    parameter integer DEPTH = 32
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               push,
    input  wire [        7:0] din,
    input  wire               clear,
    output reg  [        5:0] len,
    // NOTE: packed bus: byte i lives at mem[8*i +: 8]
    output reg  [8*DEPTH-1:0] mem
);

  always @(posedge clk) begin
    if (rst || clear) begin
      len <= 6'd0;
      mem <= 0;  // fill with 0
    end else begin
      if (push && (len < DEPTH)) begin
        // write next byte into packed bus slice
        mem[8*len+:8] <= din;
        len           <= len + 6'd1;
      end
    end
  end
endmodule

module input_core #(
    parameter integer CLK_HZ             = 100_000_000,
    parameter integer DEBOUNCE_MS        = 20,
    parameter integer REPEAT_START_MS    = 500,
    parameter integer REPEAT_INTERVAL_MS = 60,
    parameter integer BUF_DEPTH          = 32,
    parameter integer OPERAND_W          = 32
) (
    input wire clk,
    input wire rst,
    input wire btnU,
    input wire btnD,
    input wire btnL,
    input wire btnR,
    input wire btnC,

    output wire [8*BUF_DEPTH-1:0] buffer_flat,  // pass-through of internal packed buffer
    output wire [            5:0] buffer_len,
    output wire [            2:0] op_code,
    output wire [  OPERAND_W-1:0] op_a,
    op_b,
    output wire [            3:0] input_error,
    output reg                    is_clear,
    output reg                    is_equal,
    output wire                   is_valid,

    output wire [2:0] focus_row,
    output wire [2:0] focus_col
);

  // Buttons → pulses
  wire up_p, down_p, left_p, right_p, confirm_p;
  nav_keys #(
      .CLK_HZ(CLK_HZ),
      .DB_MS(DEBOUNCE_MS),
      .RPT_START_MS(REPEAT_START_MS),
      .RPT_MS(REPEAT_INTERVAL_MS)
  ) ukeys (
      .clk(clk),
      .rst(rst),
      .btnU(btnU),
      .btnD(btnD),
      .btnL(btnL),
      .btnR(btnR),
      .btnC(btnC),
      .up_p(up_p),
      .down_p(down_p),
      .left_p(left_p),
      .right_p(right_p),
      .confirm_p(confirm_p)
  );

  // Focus
  wire [2:0] f_row, f_col;
  assign focus_row = f_row;
  assign focus_col = f_col;

  wire select_pulse;
  focus_grid #(
      .ROWS(5),
      .COLS(4)
  ) nav (
      .clk(clk),
      .rst(rst),
      .up_p(up_p),
      .down_p(down_p),
      .left_p(left_p),
      .right_p(right_p),
      .confirm_p(confirm_p),
      .row(f_row),
      .col(f_col),
      .select_pulse(select_pulse)
  );

  // Map key
  wire [7:0] k_ascii;
  wire k_is_eq, k_is_clr;
  keypad_map km (
      .row(f_row),
      .col(f_col),
      .ascii(k_ascii),
      .is_equals(k_is_eq),
      .is_clear(k_is_clr)
  );

  // Buffer control
  wire buf_push = select_pulse && (!k_is_eq) && (!k_is_clr);
  wire [7:0] buf_din = k_ascii;
  wire buf_clear = select_pulse && k_is_clr;

  // Text buffer (packed bus)
  wire [8*BUF_DEPTH-1:0] mem_bus;
  text_buffer #(
      .DEPTH(BUF_DEPTH)
  ) tb (
      .clk  (clk),
      .rst  (rst),
      .push (buf_push),
      .din  (buf_din),
      .clear(buf_clear),
      .len  (buffer_len),
      .mem  (mem_bus)
  );
  assign buffer_flat = mem_bus;

  // Parse
  wire [3:0] parse_errors;
  wire has_a, has_b;
  expr_parser #(
      .DEPTH(BUF_DEPTH),
      .W(OPERAND_W)
  ) parser (
      .mem_bus(mem_bus),
      .len(buffer_len),
      .op_code(op_code),
      .op_a(op_a),
      .op_b(op_b),
      .has_a(has_a),
      .has_b(has_b),
      .errors(parse_errors)
  );
  assign input_error = parse_errors;

  // Strobes
  always @(posedge clk) begin
    if (rst) begin
      is_clear <= 1'b0;
      is_equal <= 1'b0;
    end else begin
      is_clear <= (select_pulse && k_is_clr);
      is_equal <= (select_pulse && k_is_eq);
    end
  end

  // Validity rule
  wire empty_buf = (buffer_len == 0);
  wire op_is_none = (op_code == `OP_NONE);
  wire has_err = (input_error != `ERR_NONE);

  assign is_valid =
         is_equal &&
         !empty_buf &&
         !has_err &&
         ( ( op_is_none && has_a && !has_b ) ||
           ( !op_is_none && has_a && has_b ) );

endmodule

module student_input #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BUF_DEPTH = 32,
    parameter integer BAUD_RATE = 115200,
    parameter integer MAX_DATA = 32
) (
    input wire clk,
    input wire rst,
    // Buttons
    input wire btnU,
    input wire btnD,
    input wire btnL,
    input wire btnR,
    input wire btnC,
    // Pixel clock + OLED
    input wire clk_pix,
    output wire [7:0] oled_out,
    // UART TX out
    output wire tx,
    // (optional) debug
    output wire [15:0] debug_led
);
  wire [8*BUF_DEPTH-1:0] buf_flat;
  wire [            5:0] buf_len6;
  wire [            2:0] op_code;
  wire [31:0] op_a, op_b;
  wire [3:0] in_err;
  wire is_clear, is_equal, is_valid;
  wire [2:0] f_row, f_col;
  reg  dbg1;
  wire uart_out;
  assign tx = uart_out;
  input_core #(
      .CLK_HZ(CLK_HZ),
      .DEBOUNCE_MS(20),
      .REPEAT_START_MS(500),
      .REPEAT_INTERVAL_MS(60),
      .BUF_DEPTH(BUF_DEPTH),
      .OPERAND_W(32)
  ) u_in (
      .clk(clk),
      .rst(rst),
      .btnU(btnU),
      .btnD(btnD),
      .btnL(btnL),
      .btnR(btnR),
      .btnC(btnC),
      .buffer_flat(buf_flat),
      .buffer_len(buf_len6),
      .op_code(op_code),
      .op_a(op_a),
      .op_b(op_b),
      .input_error(in_err),
      .is_clear(is_clear),
      .is_equal(is_equal),
      .is_valid(is_valid),
      .focus_row(f_row),
      .focus_col(f_col)
  );

  render_keypad #(
      .FONT_SCALE(2),
      .GRID_ROWS (4),
      .GRID_COLS (4),
      .KB_LAYOUT ({"0C=+", "123-", "456*", "789/"})
  ) u_out (
      .clk_pix(clk_pix),
      .rst(rst),
      .focus_row(f_row),
      .focus_col(f_col),
      .oled_out(oled_out)
  );

  always @(negedge uart_out, posedge rst) begin
    dbg1 = rst ? 0 : ~dbg1;
  end

  // Send whenever buffer changes or is cleared
  wire [7:0] buf_len8 = {2'b00, buf_len6};
  wire busy;

  text_uart_sync #(
      .CLK_FREQ (CLK_HZ),
      .BAUD_RATE(BAUD_RATE),
      .BUF_DEPTH(BUF_DEPTH),
      .MAX_DATA (MAX_DATA)
  ) bridge (
      .clk(clk),
      .rst(rst),
      .buffer_flat(buf_flat),
      .buffer_len(buf_len8),
      .is_clear(is_clear),
      .tx(uart_out),
      .busy(busy)  // unused
  );

  // Optional debug LED mapping (same as before)
  assign debug_led[13:9] = buf_len6[4:0];
  assign debug_led[8:6]  = op_code;
  assign debug_led[5:3]  = in_err[2:0];
  assign debug_led[2]    = is_valid;
  assign debug_led[1]    = is_clear;
  assign debug_led[0]    = is_equal;
  assign debug_led[15]   = dbg1;
  assign debug_led[14] = busy;
endmodule
