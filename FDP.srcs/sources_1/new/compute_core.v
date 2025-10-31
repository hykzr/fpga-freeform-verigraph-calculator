`timescale 1ns / 1ps
`include "constants.vh"

// ------------------------------------------------------------
// MODIFIED: Direct port connection instead of UART
// MAX_DATA == MAX_EXPR  → input bus feeds evaluator directly.
// On compute_start: evaluate & reply with result_valid (ASCII decimal).
// On evaluator error: reply "ERR".
// ------------------------------------------------------------
module student_compute_direct #(
    parameter integer CLK_HZ   = 100_000_000,
    parameter integer MAX_DATA = 32            // also evaluator MAX_EXPR
) (
    input wire clk,
    input wire rst,

    // MODIFIED: Direct interface replacing UART
    input wire compute_start,  // 1-cycle pulse to start
    input wire compute_clear,  // 1-cycle pulse to clear (optional, not used in compute)
    input wire [7:0] compute_len,
    input wire [8*MAX_DATA-1:0] compute_bus,

    output reg                  result_valid,  // 1-cycle pulse when done
    output reg [           7:0] result_len,
    output reg [8*MAX_DATA-1:0] result_bus,

    output wire [15:0] debug_led
);

  // ---------- Input Latching ----------
  // Latch input when compute_start is triggered
  reg [7:0] rx_len_latched;
  reg [8*MAX_DATA-1:0] rx_bus_latched;
  reg compute_triggered;

  always @(posedge clk) begin
    if (rst) begin
      rx_len_latched <= 8'd0;
      rx_bus_latched <= {8 * MAX_DATA{1'b0}};
      compute_triggered <= 1'b0;
    end else begin
      if (compute_start) begin
        rx_len_latched <= compute_len;
        rx_bus_latched <= compute_bus;
        compute_triggered <= 1'b1;
      end else if (compute_triggered && eval_start) begin
        compute_triggered <= 1'b0;  // Clear after we've started evaluation
      end
    end
  end

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
      .in_str(rx_bus_latched),
      .in_len(rx_len_latched[ILW-1:0]),
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

  // ---------- FSM ----------
  localparam S_IDLE = 3'd0, S_EVAL = 3'd1, S_ASC = 3'd2, S_RESULT = 3'd3;
  reg [2:0] st;
  integer i;

  // ---------- Debug (sticky) ----------
  reg dbg_eval_active, dbg_eval_done, dbg_asc_active, dbg_asc_done, dbg_result_sent;

  always @(posedge clk) begin
    if (rst) begin
      st <= S_IDLE;
      eval_start <= 1'b0;
      asc_start <= 1'b0;
      result_valid <= 1'b0;
      result_len <= 8'd0;
      result_bus <= {8 * MAX_DATA{8'h00}};
      dbg_eval_active <= 1'b0;
      dbg_eval_done <= 1'b0;
      dbg_asc_active <= 1'b0;
      dbg_asc_done <= 1'b0;
      dbg_result_sent <= 1'b0;
    end else begin
      eval_start <= 1'b0;
      asc_start <= 1'b0;
      result_valid <= 1'b0;

      // Clear debug latches on a new compute request
      if (compute_triggered && st == S_IDLE) begin
        dbg_eval_active <= 1'b0;
        dbg_eval_done <= 1'b0;
        dbg_asc_active <= 1'b0;
        dbg_asc_done <= 1'b0;
        dbg_result_sent <= 1'b0;
      end

      case (st)
        S_IDLE: begin
          if (compute_triggered) begin
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
              // Set result to "ERR"
              result_len <= (3 > MAX_DATA[7:0]) ? MAX_DATA[7:0] : 8'd3;
              result_bus <= {8 * MAX_DATA{8'h00}};
              result_bus[8*0+:8] <= 8'h45;  // 'E'
              if (MAX_DATA > 1) result_bus[8*1+:8] <= 8'h52;  // 'R'
              if (MAX_DATA > 2) result_bus[8*2+:8] <= 8'h52;  // 'R'
              st <= S_RESULT;
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
            result_len <= (asc_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : asc_len;
            result_bus <= {8 * MAX_DATA{8'h00}};
            for (i = 0; i < MAX_DATA; i = i + 1)
            if (i < result_len) result_bus[8*i+:8] <= asc_bus[8*i+:8];
            st <= S_RESULT;
          end
        end

        S_RESULT: begin
          // Send result as 1-cycle pulse
          result_valid <= 1'b1;
          dbg_result_sent <= 1'b1;
          st <= S_IDLE;
        end

        default: st <= S_IDLE;
      endcase
    end
  end

  // ---------- Debug LED mapping ----------
  assign debug_led[7:0]  = asc_bus[7:0];
  assign debug_led[15:8] = asc_bus[8*ASC_CAP-1:8*ASC_CAP-8];
endmodule
