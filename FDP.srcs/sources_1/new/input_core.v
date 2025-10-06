`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: EE2026 iFDP Group
// Engineer: Member A
//
// Module: input_core
// Description:
//   Handles all user inputs: switches + five pushbuttons
//   Provides stable control signals and debounced press detection.
//
//   - SW[3:0]  : Operand A
//   - SW[7:4]  : Operand B
//   - btnL     : Select ADD operation
//   - btnR     : Select SUB operation
//   - btnC     : Evaluate (valid trigger)
//   - btnU     : Soft reset (reset_req)
//   - btnD     : Reserved (can be used for mode toggle or future features)
//   - SW[15:13]: Mode select bits (for expansion)
//////////////////////////////////////////////////////////////////////////////////
module input_core(
    input        clk_1k,       // slow clock for debounce (1 kHz)
    input        clk_fast,     // main system clock (100 MHz)
    input  [15:0] sw,
    input        btnL,
    input        btnU,
    input        btnD,
    input        btnR,
    input        btnC,
    output reg [3:0] operand_a,
    output reg [3:0] operand_b,
    output reg [1:0] op_sel,      // 00 = add, 01 = sub
    output reg        valid,      // rising edge = evaluate
    output reg        reset_req,  // soft reset pulse
    output reg [2:0]  mode        // calculator mode bits
);
    //--------------------------------------------------
    // Debounce button signals (1 ms sampling)
    //--------------------------------------------------
    reg [4:0] btn_sync;    // sampled values
    reg [4:0] btn_prev;
    wire [4:0] btn_raw = {btnC, btnR, btnD, btnU, btnL}; // packed order (for easy handling)

    always @(posedge clk_1k)
    begin
        btn_sync <= btn_raw;
        btn_prev <= btn_sync;
    end

    // Rising-edge detect on each button
    wire pressL = (btn_sync[0] & ~btn_prev[0]);
    wire pressU = (btn_sync[1] & ~btn_prev[1]);
    wire pressD = (btn_sync[2] & ~btn_prev[2]);
    wire pressR = (btn_sync[3] & ~btn_prev[3]);
    wire pressC = (btn_sync[4] & ~btn_prev[4]);

    //--------------------------------------------------
    // Capture operands and control
    //--------------------------------------------------
    always @(posedge clk_fast)
    begin
        operand_a <= sw[3:0];
        operand_b <= sw[7:4];
        mode      <= sw[15:13];

        // Operation selection
        if (pressL)
        op_sel <= 2'b00;  // ADD
        else if (pressR)
        op_sel <= 2'b01;  // SUB

        // Evaluate signal (single-pulse valid)
        valid <= pressC;

        // Reset request (soft reset pulse)
        reset_req <= pressU;

        // Optionally, you can assign down-button for special mode
        // e.g., if (pressD) mode <= mode + 1;
    end

endmodule
