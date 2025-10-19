`include "constants.vh"

module text_uart_sink #(
    parameter integer CLK_FREQ  = 100_000_000,
    parameter integer BAUD_RATE = 115200,
    parameter integer MAX_DATA  = 32
) (
    input wire clk,
    input wire rst,
    input wire rx,   // UART RX pin

    output reg                   text_valid,       // 1-cycle when new TEXT applied
    output reg                   cleared,          // 1-cycle when CLEAR applied
    output reg  [           7:0] text_len,         // 0..MAX_DATA (clamped)
    output reg  [8*MAX_DATA-1:0] text_bus,         // packed bytes [8*i +: 8]
    output wire                  chk_ok_last,      // pass-through last frame's checksum result
    output wire                  frame_valid_last  // pass-through last frame_valid
);
  // RX
  wire                  frame_valid;
  wire                  chk_ok;
  wire [           7:0] cmd;
  wire [           7:0] data_len;
  wire [8*MAX_DATA-1:0] data_bus;

  proto_rx #(
      .CLK_FREQ (CLK_FREQ),
      .BAUD_RATE(BAUD_RATE),
      .MAX_DATA (MAX_DATA)
  ) RX (
      .clk(clk),
      .rst(rst),
      .rx(rx),
      .frame_valid(frame_valid),
      .chk_ok(chk_ok),
      .cmd(cmd),
      .data_len(data_len),
      .data_bus(data_bus)
  );

  assign chk_ok_last      = chk_ok;
  assign frame_valid_last = frame_valid;

  // State: hold latest text
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      text_valid <= 1'b0;
      cleared    <= 1'b0;
      text_len   <= 8'd0;
      text_bus   <= {8*MAX_DATA{1'b0}};
    end else begin
      text_valid <= 1'b0;
      cleared    <= 1'b0;

      if (frame_valid && chk_ok) begin
        if (cmd == `CMD_CLEAR) begin
          text_len <= 8'd0;
          text_bus <= {8 * MAX_DATA{1'b0}};
          cleared  <= 1'b1;
        end else if (cmd == `CMD_TEXT) begin
          text_len   <= (data_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : data_len;
          text_bus   <= data_bus;  // already clamped inside proto_rx
          text_valid <= 1'b1;
        end
      end
    end
  end
endmodule

// student_output.v
module student_output #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD_RATE = 115200,
    parameter integer MAX_DATA = 32
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        rx,   // UART RX pin
    output wire [15:0] led   // simple visualization on LEDs
);
  wire text_valid, cleared, chk_ok, fr_valid;
  wire [7:0] text_len;
  wire [8*MAX_DATA-1:0] text_bus;

  text_uart_sink #(
      .CLK_FREQ (CLK_HZ),
      .BAUD_RATE(BAUD_RATE),
      .MAX_DATA (MAX_DATA)
  ) sink (
      .clk(clk),
      .rst(rst),
      .rx(rx),
      .text_valid(text_valid),
      .cleared(cleared),
      .text_len(text_len),
      .text_bus(text_bus),
      .chk_ok_last(chk_ok),
      .frame_valid_last(fr_valid)
  );

  wire [7:0] first_byte = text_bus[7:0];

  wire rx_tog, fr_valid_tog, chk_ok_tog;

  toggle_on_pulse tfr (
      .clk(clk),
      .rst(rst),
      .pulse_in(fr_valid),
      .toggle_out(fr_valid_tog)
  );
  toggle_on_pulse tchk (
      .clk(clk),
      .rst(rst),
      .pulse_in(chk_ok),
      .toggle_out(chk_ok_tog)
  );
  toggle_on_pulse trx (
      .clk(clk),
      .rst(rst),
      .pulse_in(rx),
      .toggle_out(rx_tog)
  );
  assign led[15] = fr_valid_tog;
  assign led[14] = chk_ok_tog;
  assign led[13] = rx_tog;
  assign led[12:6] = text_len[6:0];
  assign led[5:1] = first_byte[4:0];
  assign led[0] = 1'b1;
endmodule
