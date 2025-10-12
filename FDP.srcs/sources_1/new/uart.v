`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
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

module uart_tx #(
    parameter CLK_FREQ = 100_000_000,  // Basys3 system clock
    parameter BAUD_RATE = 9600
  )(
    input  wire clk,
    input  wire rst,
    input  wire tx_start,       // start transmission pulse
    input  wire [7:0] tx_data,  // data byte to send
    output reg  tx,             // serial output line
    output reg  busy            // high while transmitting
  );
  localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
  reg [15:0] clk_count = 0;
  reg [3:0]  bit_index = 0;
  reg [9:0]  tx_shift  = 10'b1111111111; // start(0) + 8 data + stop(1)

  always @(posedge clk or posedge rst)
  begin
    if (rst)
    begin
      tx        <= 1'b1;  // idle high
      busy      <= 1'b0;
      clk_count <= 0;
      bit_index <= 0;
      tx_shift  <= 10'b1111111111;
    end
    else
    begin
      if (tx_start && !busy)
      begin
        // Load frame: start bit, data bits, stop bit
        tx_shift  <= {1'b1, tx_data, 1'b0};
        busy      <= 1'b1;
        clk_count <= 0;
        bit_index <= 0;
      end
      else if (busy)
      begin
        if (clk_count < CLKS_PER_BIT - 1)
        begin
          clk_count <= clk_count + 1;
        end
        else
        begin
          clk_count <= 0;
          tx        <= tx_shift[0];
          tx_shift  <= {1'b1, tx_shift[9:1]}; // shift right with idle 1
          bit_index <= bit_index + 1;

          if (bit_index == 9)
          begin
            busy <= 1'b0;
            tx   <= 1'b1; // stop bit
          end
        end
      end
    end
  end
endmodule
module uart_rx #(
    parameter CLK_FREQ = 100_000_000,  // Basys3 system clock
    parameter BAUD_RATE = 9600
  )(
    input  wire clk,
    input  wire rst,
    input  wire rx,          // serial input line
    output reg  [7:0] rx_data,
    output reg  rx_done      // 1-clock pulse when data ready
  );

  localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

  reg [15:0] clk_count = 0;
  reg [3:0]  bit_index = 0;
  reg [7:0]  data_buf  = 0;
  reg [2:0]  state     = 0;

  localparam IDLE  = 0,
             START = 1,
             DATA  = 2,
             STOP  = 3,
             DONE  = 4;

  always @(posedge clk or posedge rst)
  begin
    if (rst)
    begin
      state     <= IDLE;
      rx_data   <= 8'b0;
      rx_done   <= 1'b0;
      clk_count <= 0;
      bit_index <= 0;
    end
    else
    begin
      case (state)
        IDLE:
        begin
          rx_done <= 1'b0;
          if (rx == 1'b0)
          begin
            state     <= START;
            clk_count <= 0;
          end
        end

        START:
        begin
          if (clk_count == (CLKS_PER_BIT/2))
          begin
            if (rx == 1'b0)
            begin
              state     <= DATA;
              clk_count <= 0;
              bit_index <= 0;
            end
            else
              state <= IDLE;
          end
          else
            clk_count <= clk_count + 1;
        end

        DATA:
        begin
          if (clk_count == CLKS_PER_BIT - 1)
          begin
            clk_count         <= 0;
            data_buf[bit_index] <= rx;
            if (bit_index < 7)
              bit_index <= bit_index + 1;
            else
              state <= STOP;
          end
          else
            clk_count <= clk_count + 1;
        end

        STOP:
        begin
          if (clk_count == CLKS_PER_BIT - 1)
          begin
            state     <= DONE;
            rx_data   <= data_buf;
            rx_done   <= 1'b1;
            clk_count <= 0;
          end
          else
            clk_count <= clk_count + 1;
        end

        DONE:
        begin
          state   <= IDLE;
          rx_done <= 1'b0;
        end
      endcase
    end
  end
endmodule


module uart(
    input clk,      // 100 MHz clock
    input rst,
    input rx,       // from USB-UART
    output tx
  );
  wire [7:0] data_rx;
  wire rx_done, tx_busy;
  reg  tx_start = 0;
  reg  [7:0] data_tx = 0;

  uart_rx uart_rx0 (
            .clk(clk),
            .rst(rst),
            .rx(rx),
            .rx_data(data_rx),
            .rx_done(rx_done)
          );

  uart_tx uart_tx0 (
            .clk(clk),
            .rst(rst),
            .tx_start(tx_start),
            .tx_data(data_tx),
            .tx(tx),
            .busy(tx_busy)
          );

  // Simple echo logic: when a byte received, send it back
  always @(posedge clk)
  begin
    if (rx_done && !tx_busy)
    begin
      data_tx  <= data_rx;
      tx_start <= 1;
    end
    else
    begin
      tx_start <= 0;
    end
  end
endmodule
