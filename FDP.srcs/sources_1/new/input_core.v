`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: EE2026 iFDP Group
// Engineer: Member A
// 
// Description: Input / Control subsystem
//   - Debounces buttons
//   - Reads switches for operands
//   - Outputs stable control signals to calculator core
//////////////////////////////////////////////////////////////////////////////////
module input_core(
    input        clk_1k,          // 1 kHz clock for debounce
    input        clk_fast,        // 100 MHz for logic timing
    input  [15:0] sw,
    input  [4:0]  btn,
    output reg [3:0] operand_a,
    output reg [3:0] operand_b,
    output reg [1:0] op_sel,      // 00:add, 01:sub
    output reg        valid,
    output reg        reset_req,
    output reg [2:0]  mode
);

    // --- Debounce example structure ---
    reg [4:0] btn_sync, btn_prev;
    always @(posedge clk_1k) begin
        btn_sync <= btn;
        btn_prev <= btn_sync;
    end

    wire btn_rise_center = (btn_sync[2] & ~btn_prev[2]);
    wire btn_rise_left   = (btn_sync[1] & ~btn_prev[1]);
    wire btn_rise_right  = (btn_sync[3] & ~btn_prev[3]);

    always @(posedge clk_fast) begin
        operand_a <= sw[3:0];
        operand_b <= sw[7:4];
        op_sel    <= btn_rise_left  ? 2'b00 :     // left  = add
                      btn_rise_right ? 2'b01 : op_sel;
        valid     <= (btn_rise_center);           // center = evaluate
        reset_req <= btn[0];                      // BTNU as soft reset
        mode      <= sw[15:13];                   // mode selection for later use
    end

endmodule

