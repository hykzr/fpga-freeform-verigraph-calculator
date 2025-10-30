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

module student_output #(
    parameter integer CLK_HZ     = 100_000_000,
    parameter integer BAUD_RATE  = 115200,
    parameter integer MAX_DATA   = 32,
    parameter integer FONT_SCALE = 2,            // pass through to renderer
    parameter integer H_SP       = 2,
    parameter integer V_SP       = 2
) (
    input wire clk,
    input wire rst,
    input wire rx,   // UART RX pin

    // OLED
    input  wire       clk_pix,  // 6.25 MHz pixel clock
    output wire [7:0] oled_out

    // (add optional debug LED outputs here if you still want them)
);

  // ---- Receive & hold latest text ----
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

  // ---- Per-pixel renderer ----
  wire [12:0] pixel_index;
  wire [15:0] pixel_color;

  text_grid_renderer #(
      .FONT_SCALE(FONT_SCALE),
      .H_SP(H_SP),
      .V_SP(V_SP),
      .MAX_DATA(MAX_DATA)
  ) rend (
      .pixel_index(pixel_index),
      .text_len(text_len),
      .text_bus(text_bus),
      .pixel_color(pixel_color)
  );

  // ---- OLED driver ----
  oled u_oled (
      .clk_6p25m  (clk_pix),
      .rst        (rst),
      .pixel_color(pixel_color),
      .oled_out   (oled_out),
      .pixel_index(pixel_index)
  );

endmodule
