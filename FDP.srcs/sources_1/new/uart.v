`timescale 1ns / 1ps
`include "constants.vh"
// Company:
// Engineer:
//
// Create Date: 11.10.2025 21:54:41
// Design Name:
// Module Name: uart
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
// uart_tx.v
module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_start,  // 1-cycle pulse
    input  wire [7:0] tx_data,
    output reg        tx,        // idle-high
    output wire       busy_out
);
  localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
  reg [15:0] clk_count;
  reg [ 3:0] bit_index;
  reg [ 9:0] sh;
  // the output busy should be also true if start is true, avoiding skipping bytes
  reg        busy;
  assign busy_out = busy | tx_start;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      tx <= 1'b1;
      busy <= 1'b0;
      clk_count <= 0;
      bit_index <= 0;
      sh <= 10'h3FF;
    end else begin
      if (tx_start && !busy) begin
        sh        <= {1'b1, tx_data, 1'b0};  // stop + data + start(0)
        busy      <= 1'b1;
        clk_count <= 0;
        bit_index <= 0;
      end else if (busy) begin
        if (clk_count == CLKS_PER_BIT - 1) begin
          clk_count <= 0;
          tx        <= sh[0];
          sh        <= {1'b1, sh[9:1]};
          bit_index <= bit_index + 1;
          if (bit_index == 9) begin
            busy <= 1'b0;
            tx   <= 1'b1;
          end
        end else clk_count <= clk_count + 1;
      end
    end
  end
endmodule

// uart_rx.v
module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_done   // 1-cycle pulse
);
  localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
  localparam IDLE = 0, START = 1, DATA = 2, STOP = 3;
  reg [ 1:0] state;
  reg [15:0] clk_count;
  reg [ 2:0] bit_index;
  reg [ 7:0] d;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= IDLE;
      clk_count <= 0;
      bit_index <= 0;
      rx_done <= 0;
      rx_data <= 8'h00;
      d <= 8'h00;
    end else begin
      rx_done <= 1'b0;
      case (state)
        IDLE:
        if (rx == 1'b0) begin
          state <= START;
          clk_count <= 0;
        end
        START:
        if (clk_count == CLKS_PER_BIT / 2) begin
          if (rx == 1'b0) begin
            state <= DATA;
            clk_count <= 0;
            bit_index <= 0;
          end else state <= IDLE;
        end else clk_count <= clk_count + 1;
        DATA:
        if (clk_count == CLKS_PER_BIT - 1) begin
          clk_count <= 0;
          d[bit_index] <= rx;
          if (bit_index == 3'd7) state <= STOP;
          else bit_index <= bit_index + 1;
        end else clk_count <= clk_count + 1;
        STOP:
        if (clk_count == CLKS_PER_BIT - 1) begin
          state <= IDLE;
          rx_data <= d;
          rx_done <= 1'b1;
          clk_count <= 0;
        end else clk_count <= clk_count + 1;
      endcase
    end
  end
endmodule

// proto_tx.v — 8-bit LEN, parameterized payload
// Frame: START, LEN, CMD, DATA[0..N-1], CHK, END
module proto_tx #(
    parameter integer CLK_FREQ   = 100_000_000,
    parameter integer BAUD_RATE  = 115200,
    parameter integer MAX_DATA   = 32     // max payload bytes (N)
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  start,     // 1-cycle pulse
    input  wire [           7:0] cmd,
    input  wire [           7:0] data_len,  // 0..255 (we will only use 0..MAX_DATA)
    input  wire [8*MAX_DATA-1:0] data_bus,  // byte i at [8*i +: 8]
    output reg                   busy,
    output wire                  tx
);
  // UART byte TX
  reg        tx_start;
  reg  [7:0] tx_data;
  wire       tx_busy;

  uart_tx #(
      .CLK_FREQ (CLK_FREQ),
      .BAUD_RATE(BAUD_RATE)
  ) UTX (
      .clk(clk),
      .rst(rst),
      .tx_start(tx_start),
      .tx_data(tx_data),
      .tx(tx),
      .busy_out(tx_busy)
  );

  // FSM
  localparam S_IDLE=0, S_SEND_START=1, S_SEND_LEN=2, S_SEND_CMD=3,
             S_SEND_DATA=4, S_SEND_CHK=5, S_SEND_END=6;
  reg  [                 2:0] st;

  // internal
  reg  [$clog2(MAX_DATA)-1:0] idx;  // 0..MAX_DATA-1
  reg  [                 7:0] len_field;  // LEN = 1 + N (cmd + data)
  reg  [                 7:0] n_data;  // N = min(data_len, MAX_DATA)
  reg  [                 7:0] chk;

  // current data byte
  wire [                 7:0] data_byte = data_bus[8*idx+:8];

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      st        <= S_IDLE;
      idx       <= {($clog2(MAX_DATA)) {1'b0}};
      len_field <= 8'd0;
      n_data    <= 8'd0;
      chk       <= 8'd0;
      tx_start  <= 1'b0;
      tx_data   <= 8'h00;
      busy      <= 1'b0;
    end else begin
      tx_start <= 1'b0;

      case (st)
        S_IDLE: begin
          busy <= 1'b0;
          if (start) begin
            busy      <= 1'b1;
            n_data    <= (data_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : data_len;
            len_field <= ((data_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : data_len) + 8'd1;
            chk       <= cmd;
            idx       <= {($clog2(MAX_DATA)) {1'b0}};
            st        <= S_SEND_START;
          end
        end

        S_SEND_START:
        if (!tx_busy) begin
          tx_data <= `START_BYTE;
          tx_start <= 1'b1;
          st <= S_SEND_LEN;
        end

        S_SEND_LEN:
        if (!tx_busy) begin
          tx_data <= len_field;
          tx_start <= 1'b1;
          st <= S_SEND_CMD;
        end

        S_SEND_CMD:
        if (!tx_busy) begin
          tx_data <= cmd;
          tx_start <= 1'b1;
          st <= (n_data == 8'd0) ? S_SEND_CHK : S_SEND_DATA;
        end

        S_SEND_DATA:
        if (!tx_busy) begin
          tx_data  <= data_byte;
          tx_start <= 1'b1;
          chk      <= chk ^ data_byte;
          if (idx == n_data[$clog2(MAX_DATA)-1:0] - 1) begin
            st <= S_SEND_CHK;
          end else begin
            idx <= idx + {{($clog2(MAX_DATA) - 1) {1'b0}}, 1'b1};
          end
        end

        S_SEND_CHK:
        if (!tx_busy) begin
          tx_data <= chk;
          tx_start <= 1'b1;
          st <= S_SEND_END;
        end

        S_SEND_END:
        if (!tx_busy) begin
          tx_data <= `END_BYTE;
          tx_start <= 1'b1;
          st <= S_IDLE;
          busy <= 1'b0;
        end

        default: st <= S_IDLE;
      endcase
    end
  end
endmodule

module proto_rx #(
    parameter integer CLK_FREQ  = 100_000_000,
    parameter integer BAUD_RATE = 115200,
    parameter integer MAX_DATA  = 32
) (
    input wire clk,
    input wire rst,
    input wire rx,

    output reg                  frame_valid,  // 1-cycle pulse
    output reg                  chk_ok,       // checksum OK
    output reg [           7:0] cmd,
    output reg [           7:0] data_len,     // 0..255 (actual N, clamped to MAX_DATA)
    output reg [8*MAX_DATA-1:0] data_bus      // byte i at [8*i +: 8]
);
  // Byte RX
  wire [7:0] rx_byte;
  wire       rx_done;
  uart_rx #(
      .CLK_FREQ (CLK_FREQ),
      .BAUD_RATE(BAUD_RATE)
  ) URX (
      .clk(clk),
      .rst(rst),
      .rx(rx),
      .rx_data(rx_byte),
      .rx_done(rx_done)
  );

  // FSM
  localparam S_IDLE = 0, S_LEN = 1, S_CMD = 2, S_DATA = 3, S_CHK = 4, S_END = 5;
  reg [                 2:0] st;

  reg [                 7:0] len_field;  // LEN from wire
  reg [$clog2(MAX_DATA)-1:0] idx;  // 0..MAX_DATA-1
  reg [                 7:0] chk_acc;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      st          <= S_IDLE;
      len_field   <= 8'd0;
      data_len    <= 8'd0;
      data_bus    <= {8 * MAX_DATA{1'b0}};
      idx         <= {($clog2(MAX_DATA)) {1'b0}};
      chk_acc     <= 8'd0;
      cmd         <= 8'd0;
      frame_valid <= 1'b0;
      chk_ok      <= 1'b0;
    end else begin
      frame_valid <= 1'b0;

      if (rx_done) begin
        case (st)
          S_IDLE: begin
            if (rx_byte == `START_BYTE) begin
              st     <= S_LEN;
              chk_ok <= 1'b0;
            end
          end

          S_LEN: begin
            len_field <= rx_byte;  // LEN = 1 + N
            st        <= S_CMD;
          end

          S_CMD: begin
            cmd     <= rx_byte;
            chk_acc <= rx_byte;
            if (len_field == 8'd1) begin  // no data
              data_len <= 8'd0;
              st       <= S_CHK;
            end else begin
              // N = LEN - 1, clamp to MAX_DATA
              data_len <= ((len_field - 8'd1) > MAX_DATA[7:0]) ? MAX_DATA[7:0] : (len_field - 8'd1);
              idx <= {($clog2(MAX_DATA)) {1'b0}};
              st <= S_DATA;
            end
          end

          S_DATA: begin
            chk_acc <= chk_acc ^ rx_byte;
            data_bus[8*idx+:8] <= rx_byte;
            if (idx == data_len[$clog2(MAX_DATA)-1:0] - 1) begin
              st <= S_CHK;
            end else begin
              idx <= idx + {{($clog2(MAX_DATA) - 1) {1'b0}}, 1'b1};
            end
          end

          S_CHK: begin
            chk_ok <= (rx_byte == chk_acc);
            st     <= S_END;
          end

          S_END: begin
            if (rx_byte == `END_BYTE) frame_valid <= 1'b1;
            st <= S_IDLE;
          end

          default: st <= S_IDLE;
        endcase
      end
    end
  end
endmodule
