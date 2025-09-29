`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 29.09.2025 09:20:14
// Design Name: 
// Module Name: clock_devider
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


module clock_devider(
    input clock,
    output reg clk6p25m = 0
    );
    reg [2:0] counter = 0;
    always @(posedge clock) begin
        if (counter == 3'd7) begin
            clk6p25m <= ~clk6p25m; // toggle every 8 cycles
            counter <= 3'd0;
        end else begin
            counter <= counter + 1'b1;
        end
    end
endmodule
