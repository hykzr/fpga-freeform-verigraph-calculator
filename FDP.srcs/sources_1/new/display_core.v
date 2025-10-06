`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: EE2026 iFDP Group
// Engineer: Member C
//
// Description: Display and output subsystem
//   Receives computed result and displays it
//   For BASIC functionality: display numbers from -9 to 18
//////////////////////////////////////////////////////////////////////////////////
module display_core(
    input        clk_fast,       // 100 MHz
    input        clk_6p25M,      // for OLED
    input  signed [4:0] result,  // Computed result: -9 to 18
    input        result_valid,   // High when result is ready to display
    output [15:0] led,
    output [6:0]  seg,
    output [3:0]  an,
    output [7:0]  JA             // OLED pins
);

    //-------------------------------------
    // LED feedback - show result
    //-------------------------------------
    // Display result value and validity on LEDs
    assign led[4:0]  = result;        // Show result value (5 bits for signed)
    assign led[5]    = result[4];     // Show sign bit separately
    assign led[6]    = result_valid;  // Show when result is valid
    assign led[15:7] = 9'b0;          // Unused LEDs off

    //-------------------------------------
    // Seven-segment display for result
    // Shows signed result (-9 to 18)
    //-------------------------------------
    wire [3:0] left_digit;   
    wire [3:0] right_digit;  
    wire is_negative;
    wire show_left;
    
    // Convert signed result to display format
    assign is_negative = result[4] && result_valid;  // Negative and valid
    
    // Calculate digits
    wire [4:0] abs_result = is_negative ? -result : result;
    assign right_digit = abs_result % 10;
    assign left_digit = is_negative ? 4'd10 :              // 10 = minus sign
                        (abs_result >= 10) ? abs_result / 10 : 4'd15; // 15 = blank
    assign show_left = is_negative || (abs_result >= 10);
    
    // Multiplex between two digits
    reg [16:0] refresh_counter = 0;
    
    always @(posedge clk_fast) begin
        refresh_counter <= refresh_counter + 1;
    end
    
    wire refresh_clk = refresh_counter[16]; // ~762Hz
    
    reg digit_select = 0;
    always @(posedge refresh_clk) begin
        digit_select <= ~digit_select;
    end
    
    reg [3:0] current_digit;
    reg [6:0] seg_temp;
    reg [3:0] an_temp;
    
    // 7-segment decoder function
    function [6:0] digit_to_seg;
        input [3:0] digit;
        begin
            case(digit)
                4'd0: digit_to_seg = 7'b1000000; // 0
                4'd1: digit_to_seg = 7'b1111001; // 1
                4'd2: digit_to_seg = 7'b0100100; // 2
                4'd3: digit_to_seg = 7'b0110000; // 3
                4'd4: digit_to_seg = 7'b0011001; // 4
                4'd5: digit_to_seg = 7'b0010010; // 5
                4'd6: digit_to_seg = 7'b0000010; // 6
                4'd7: digit_to_seg = 7'b1111000; // 7
                4'd8: digit_to_seg = 7'b0000000; // 8
                4'd9: digit_to_seg = 7'b0010000; // 9
                4'd10: digit_to_seg = 7'b0111111; // minus (-)
                default: digit_to_seg = 7'b1111111; // blank
            endcase
        end
    endfunction
    
    always @(*) begin
        if (!result_valid) begin
            // No result yet: show dashes
            seg_temp = 7'b0111111;  // minus sign/dash
            an_temp = 4'b1100;       // Light up rightmost 2 digits
        end else begin
            if (digit_select == 0) begin
                // Right digit (ones place)
                current_digit = right_digit;
                seg_temp = digit_to_seg(right_digit);
                an_temp = 4'b1110;  // Rightmost digit
            end else begin
                // Left digit (tens or minus sign)
                current_digit = left_digit;
                seg_temp = digit_to_seg(left_digit);
                an_temp = 4'b1101;  // Second from right
            end
        end
    end
    
    assign seg = seg_temp;
    assign an = an_temp;

    //-------------------------------------
    // OLED display - Show the result number
    //-------------------------------------
    wire [12:0] pixel_index;
    wire [6:0] x = pixel_index % 96;
    wire [5:0] y = pixel_index / 96;
    
    reg [15:0] oled_colour;
    
    // Color definitions (RGB565)
    parameter BLACK  = 16'h0000;
    parameter GREEN  = 16'h07E0;
    parameter RED    = 16'hF800;
    parameter YELLOW = 16'hFFE0;
    parameter CYAN   = 16'h07FF;
    
    // Draw large digit on OLED (centered)
    // For now: simple bar graph representation showing result magnitude
    // Positive results: green bar, Negative results: red bar
    
    wire signed [5:0] display_value = result_valid ? result : 0;
    wire is_neg = display_value[5];
    wire [5:0] magnitude = is_neg ? -display_value : display_value;
    
    // Bar graph: centered at x=48, grows left (negative) or right (positive)
    // Each unit = 4 pixels wide
    wire [6:0] bar_width = magnitude * 4;
    wire in_bar;
    
    always @(*) begin
        oled_colour = BLACK;
        
        if (result_valid) begin
            // Center line (neutral position) - white
            if (x >= 47 && x <= 48 && y >= 20 && y <= 44) begin
                oled_colour = YELLOW;
            end
            // Result bar
            else if (y >= 20 && y <= 44) begin
                if (is_neg) begin
                    // Negative: bar extends left from center
                    if (x >= (48 - bar_width) && x <= 47) begin
                        oled_colour = RED;
                    end
                end else begin
                    // Positive: bar extends right from center
                    if (x >= 49 && x <= (48 + bar_width)) begin
                        oled_colour = GREEN;
                    end
                end
            end
            
            // Show actual number as text (simplified - just show if result exists)
            // Title area
            if (y >= 5 && y <= 15 && x >= 30 && x <= 65) begin
                oled_colour = CYAN;
            end
        end else begin
            // No result yet - show waiting indicator
            if (x >= 38 && x <= 57 && y >= 27 && y <= 36) begin
                oled_colour = YELLOW;
            end
        end
    end
    
    Oled_Display oled0(
        .clk(clk_6p25M),
        .reset(1'b0),
        .frame_begin(),
        .sending_pixels(),
        .sample_pixel(),
        .pixel_index(pixel_index),
        .pixel_data(oled_colour),
        .cs(JA[0]), 
        .sdin(JA[1]), 
        .sclk(JA[3]),
        .d_cn(JA[4]),
        .resn(JA[5]),
        .vccen(JA[6]),
        .pmoden(JA[7])
    );

endmodule