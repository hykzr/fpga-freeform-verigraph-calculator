`timescale 1ns / 1ps
`include "constants.vh"
// ------------------------------------------------------------
// MAX_DATA == MAX_EXPR  → rx_bus feeds evaluator directly.
// On CMD_COMPUTE: evaluate & reply with CMD_RESULT (ASCII decimal).
// On evaluator error: reply "ERR".
// ------------------------------------------------------------
module student_compute #(
    parameter integer CLK_HZ    = 100_000_000,
    parameter integer BAUD_RATE = 115200,
    parameter integer MAX_DATA  = 32            // also evaluator MAX_EXPR
) (
    input wire clk,
    input wire rst,
    input wire rx,
    output wire tx,
    output wire [15:0] debug_led
);
  // ---------- UART RX ----------
  wire fr_valid, chk_ok;
  wire [7:0] rx_cmd;
  wire [7:0] rx_len;
  wire [8*MAX_DATA-1:0] rx_bus;

  proto_rx #(
      .CLK_FREQ (CLK_HZ),
      .BAUD_RATE(BAUD_RATE),
      .MAX_DATA (MAX_DATA)
  ) RX (
      .clk(clk),
      .rst(rst),
      .rx(rx),
      .frame_valid(fr_valid),
      .chk_ok(chk_ok),
      .cmd(rx_cmd),
      .data_len(rx_len),
      .data_bus(rx_bus)
  );

  // ---------- Evaluator ----------
  localparam integer ILW = $clog2(MAX_DATA + 1);
  reg                eval_start;
  wire               eval_done;
  wire signed [31:0] eval_result;
  wire        [ 7:0] eval_errors;

  recv_eval_core_ns_synth #(
      .MAX_EXPR  (MAX_DATA),
      .MAX_TOKENS(32)
  ) EVAL (
      .clk(clk),
      .rst(rst),
      .start(eval_start),
      .in_str(rx_bus),
      .in_len(rx_len[ILW-1:0]),
      .done(eval_done),
      .result(eval_result),
      .errors(eval_errors)
  );

  // ---------- Int → ASCII ----------
  localparam integer ASC_CAP = (MAX_DATA < 12) ? 12 : MAX_DATA;
  reg                  asc_start;
  wire                 asc_done;
  wire [          7:0] asc_len;
  wire [8*ASC_CAP-1:0] asc_bus;

  int32_to_ascii #(
      .MAX_LEN(ASC_CAP)
  ) I2A (
      .clk(clk),
      .rst(rst),
      .start(asc_start),
      .value(eval_result),
      .done(asc_done),
      .out_len(asc_len),
      .out_bus(asc_bus)
  );

  // ---------- UART TX ----------
  reg                   tx_start;
  reg  [           7:0] tx_cmd;
  reg  [           7:0] tx_len;
  reg  [8*MAX_DATA-1:0] tx_bus;
  wire                  tx_busy;

  proto_tx #(
      .CLK_FREQ (CLK_HZ),
      .BAUD_RATE(BAUD_RATE),
      .MAX_DATA (MAX_DATA)
  ) TX (
      .clk(clk),
      .rst(rst),
      .start(tx_start),
      .cmd(tx_cmd),
      .data_len(tx_len),
      .data_bus(tx_bus),
      .busy(tx_busy),
      .tx(tx)
  );

  // ---------- FSM ----------
  localparam S_IDLE = 3'd0, S_EVAL = 3'd1, S_ASC = 3'd2, S_SEND = 3'd3, S_WAIT = 3'd4;
  reg [2:0] st;
  integer i;

  // ---------- Debug (sticky) ----------
  reg dbg_eval_active, dbg_eval_done, dbg_asc_active, dbg_asc_done, dbg_tx_started;

  // helper: clear sticky flags at start of a new valid request
  wire rx_is_compute = (rx_cmd == `CMD_COMPUTE);
  wire rx_len_nz = (rx_len != 8'd0);
  wire accept_request = (fr_valid && chk_ok && rx_is_compute);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      st <= S_IDLE;
      eval_start <= 1'b0;
      asc_start <= 1'b0;
      tx_start <= 1'b0;
      tx_cmd <= 8'h00;
      tx_len <= 8'd0;
      tx_bus <= {8 * MAX_DATA{8'h00}};
      dbg_eval_active <= 1'b0;
      dbg_eval_done <= 1'b0;
      dbg_asc_active <= 1'b0;
      dbg_asc_done <= 1'b0;
      dbg_tx_started <= 1'b0;
    end else begin
      eval_start <= 1'b0;
      asc_start  <= 1'b0;
      tx_start   <= 1'b0;

      // Clear debug latches on a new accepted COMPUTE request
      if (accept_request) begin
        dbg_eval_active <= 1'b0;
        dbg_eval_done <= 1'b0;
        dbg_asc_active <= 1'b0;
        dbg_asc_done <= 1'b0;
        dbg_tx_started <= 1'b0;
      end

      case (st)
        S_IDLE: begin
          if (accept_request) begin
            eval_start      <= 1'b1;
            dbg_eval_active <= 1'b1;
            st              <= S_EVAL;
          end
        end

        S_EVAL: begin
          if (eval_done) begin
            dbg_eval_active <= 1'b0;
            dbg_eval_done   <= 1'b1;
            if (eval_errors != 8'd0) begin
              // reply "ERR"
              tx_cmd <= `CMD_RESULT;
              tx_len <= (3 > MAX_DATA[7:0]) ? MAX_DATA[7:0] : 8'd3;
              tx_bus <= {8 * MAX_DATA{8'h00}};
              tx_bus[8*0+:8] <= 8'h45;  // 'E'
              if (MAX_DATA > 1) tx_bus[8*1+:8] <= 8'h52;  // 'R'
              if (MAX_DATA > 2) tx_bus[8*2+:8] <= 8'h52;  // 'R'
              st <= S_SEND;
            end else begin
              asc_start      <= 1'b1;
              dbg_asc_active <= 1'b1;
              st             <= S_ASC;
            end
          end
        end

        S_ASC: begin
          if (asc_done) begin
            dbg_asc_active <= 1'b0;
            dbg_asc_done <= 1'b1;
            tx_cmd <= `CMD_RESULT;
            tx_len <= (asc_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : asc_len;
            tx_bus <= {8 * MAX_DATA{8'h00}};
            for (i = 0; i < MAX_DATA; i = i + 1) if (i < tx_len) tx_bus[8*i+:8] <= asc_bus[8*i+:8];
            st <= S_SEND;
          end
        end

        S_SEND: begin
          if (!tx_busy) begin
            tx_start       <= 1'b1;
            dbg_tx_started <= 1'b1;
            st             <= S_WAIT;
          end
        end

        S_WAIT: begin
          // wait until UART completes (busy goes high then low)
          if (!tx_busy) begin
            st <= S_IDLE;
          end
        end

        default: st <= S_IDLE;
      endcase
    end
  end

  // ---------- Debug LED mapping ----------
  assign debug_led[7:0]  = asc_bus[7:0];
  assign debug_led[15:8] = asc_bus[8*ASC_CAP-1:8*ASC_CAP-8];
endmodule
