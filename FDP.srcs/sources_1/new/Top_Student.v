`timescale 1ns / 1ps
`include "constants.vh"

//////////////////////////////////////////////////////////////////////////////////
//
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME:
//  STUDENT B NAME:
//  STUDENT C NAME:
//
//////////////////////////////////////////////////////////////////////////////////

module Top_Student (
    input  wire        clk,
    input  wire        btnL,
    btnU,
    btnD,
    btnR,
    btnC,
    input  wire [15:0] sw,
    output wire [15:0] led,

    // UART on JA header (separate pins for clarity)
    output wire JA0_TX,  // connect to JA[0] in XDC
    input  wire JA1_RX,  // connect to JA[1] in XDC

    // PMODs / display
    output wire [7:0] JB,
    output wire [7:0] JC,

    // 7-seg
    output wire [6:0] seg,
    output wire [3:0] an,
    output wire       dp
);
  // ---------------- Clocks ----------------
  wire clk_25M, clk_6p25M, clk_1k;
  clock_divider clkgen (
      .clk100M(clk),
      .clk_25M(clk_25M),
      .clk_6p25M(clk_6p25M),
      .clk_1k(clk_1k)
  );

  // ---------------- Reset & Mode ----------------
  wire        rst = sw[15];
  wire        mode_out = sw[14];  // 0 = sender (input role), 1 = receiver (output role)

  // ---------------- INPUT ROLE (sender) ----------------
  wire [ 7:0] oled_bus_in;
  wire        tx_from_input;
  wire [15:0] led_input_dbg;

  localparam BAUD_RATE = 9600;

  student_input #(
      .CLK_HZ(100_000_000),
      .BUF_DEPTH(32),
      .BAUD_RATE(BAUD_RATE),
      .MAX_DATA(32)
  ) U_INPUT (
      .clk(clk),
      .rst(rst),
      .btnU(btnU),
      .btnD(btnD),
      .btnL(btnL),
      .btnR(btnR),
      .btnC(btnC),
      .clk_pix(clk_6p25M),
      .oled_out(oled_bus_in),
      .tx(tx_from_input),
      .debug_led(led_input_dbg)
  );

  // ---------------- OUTPUT ROLE (receiver) ----------------
  wire [15:0] led_from_output;

  student_output #(
      .CLK_HZ(100_000_000),
      .BAUD_RATE(BAUD_RATE),
      .MAX_DATA(32)
  ) U_OUTPUT (
      .clk(clk),
      .rst(rst),
      .rx (JA1_RX),          // RX comes from JA1 pin
      .led(led_from_output)
  );

  // ---------------- Routing / MUX ----------------
  // UART TX pin: drive from sender in input mode; idle-high otherwise
  assign JA0_TX = (mode_out == 1'b0) ? tx_from_input : 1'b1;

  // OLED only in input role; otherwise drive low
  assign JC[7:0] = (mode_out == 1'b0) ? oled_bus_in : 8'h00;

  // LEDs: show sender debug vs receiver view
  assign led = (mode_out == 1'b0) ? led_input_dbg : led_from_output;

  // Unused PMOD JB idle
  assign JB = 8'h00;

  // 7-seg off
  assign seg = 7'b111_1111;
  assign an = 4'b1111;
  assign dp = 1'b1;

endmodule
