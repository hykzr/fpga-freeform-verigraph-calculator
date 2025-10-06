`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: EE2026 iFDP Group
// Engineer: Member B
//
// Description: Basic ALU core
//   Performs 4-bit add/sub, outputs 8-bit result and flags
//////////////////////////////////////////////////////////////////////////////////
module calc_core(
    input        clk,
    input  [3:0] operand_a,
    input  [3:0] operand_b,
    input  [1:0] op_sel,       // 00:add, 01:sub
    input        valid,
    input        reset,
    output reg [7:0] result,
    output reg       carry_flag,
    output reg       overflow_flag,
    output reg       done
);
    reg [7:0] temp;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            result        <= 8'd0;
            carry_flag    <= 0;
            overflow_flag <= 0;
            done          <= 0;
        end else if (valid) begin
            case(op_sel)
                2'b00: {carry_flag, temp} = operand_a + operand_b;
                2'b01: {carry_flag, temp} = operand_a - operand_b;
                default: {carry_flag, temp} = {1'b0, 8'd0};
            endcase
            result        <= temp;
            overflow_flag <= (temp > 8'd15);
            done          <= 1;
        end else begin
            done <= 0;
        end
    end
endmodule

