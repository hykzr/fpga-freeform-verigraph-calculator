`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: EE2026 iFDP Group
// Engineer: Member C
//
// Description: Display and output subsystem
//   Drives LEDs, seven-segment display, and OLED background
//////////////////////////////////////////////////////////////////////////////////
module display_core(
    input        clk_fast,       // 100 MHz
    input        clk_25M,        // for OLED
    input        clk_6p25M,      // for OLED
    input  [7:0] result,
    input  [3:0] operand_a,
    input  [3:0] operand_b,
    input  [1:0] op_sel,
    input        carry_flag,
    input        overflow_flag,
    output [15:0] led,
    output [6:0]  seg,
    output [3:0]  an,
    output [7:0]  JA             // OLED pins (use one OLED first)
);

    //-------------------------------------
    // LED feedback
    //-------------------------------------
    assign led[7:0]  = result;
    assign led[8]    = carry_flag;
    assign led[9]    = overflow_flag;
    assign led[15:10]= 0;

    //-------------------------------------
    // Seven-seg display
    //-------------------------------------
    wire [15:0] seg_data;
    assign seg_data[3:0]   = operand_a;
    assign seg_data[7:4]   = operand_b;
    assign seg_data[11:8]  = result[3:0];
    assign seg_data[15:12] = 4'hE;   // = sign or mode indicator

    ss_display seg_driver(
        .clk(clk_fast),
        .data(seg_data),
        .seg(seg),
        .an(an)
    );

    //-------------------------------------
    // OLED display (basic background)
    //-------------------------------------
    wire [12:0] pixel_index;
    wire [15:0] pixel_data;
    reg  [15:0] oled_colour;

    always @(*) begin
        // Simple colour switch: blue for add, red for sub
        case(op_sel)
            2'b00: oled_colour = 16'h001F;
            2'b01: oled_colour = 16'hF800;
            default: oled_colour = 16'h07E0;
        endcase
    end

    Oled_Display oled0(
        .clk(clk_6p25M),
        .reset(1'b0),
        .frame_begin(),
        .sending_pixels(),
        .sample_pixel(),
        .pixel_index(pixel_index),
        .pixel_data(oled_colour),
        .cs(JA[0]), .sdin(JA[1]), .sclk(JA[2]),
        .d_cn(JA[3]), .resn(JA[4]), .vccen(JA[5]), .pmoden(JA[6])
    );

endmodule

