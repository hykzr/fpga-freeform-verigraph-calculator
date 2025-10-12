`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME:
//  STUDENT B NAME:
//  STUDENT C NAME:
//
//////////////////////////////////////////////////////////////////////////////////

module Top_Student (
    input clk,
    input btnL, btnU, btnD, btnR, btnC,
    input RsRx, RsTx,
    input [15:0] sw,
    output [15:0] led,
    output [7:0] JA,
    output [7:0] JB,
    output [7:0] JC,
    output [6:0] seg,
    output [3:0] an,
    output dp
  );
  // Shared Clock
  wire clk_25M, clk_6p25M, clk_1k;
  clock_divider clkgen(
                  .clk100M(clk),
                  .clk_25M(clk_25M),
                  .clk_6p25M(clk_6p25M),
                  .clk_1k(clk_1k)
                );

  wire [3:0] a, b;
  wire [1:0] op_sel;
  wire       valid, reset_req;
  wire [2:0] mode;

  input_core u_in(
               .clk_1k(clk_1k),
               .clk_fast(clk),
               .sw(sw),
               .btnL(btnL),
               .btnU(btnU),
               .btnD(btnD),
               .btnR(btnR),
               .btnC(btnC),
               .operand_a(a),
               .operand_b(b),
               .op_sel(op_sel),
               .valid(valid),
               .reset_req(reset_req),
               .mode(mode)
             );

  wire [7:0] result;
  wire carry, overflow, done;

  calc_core u_calc(
              .clk(clk),
              .operand_a(a),
              .operand_b(b),
              .op_sel(op_sel),
              .valid(valid),
              .reset(reset_req),
              .result(result),
              .carry_flag(carry),
              .overflow_flag(overflow),
              .done(done)
            );

  display_core u_disp(
                 .clk_fast(clk),
                 .clk_6p25M(clk_6p25M),
                 .result(result [4:0]),
                 .result_valid(done),
                 .led(led),
                 .seg(seg),
                 .an(an),
                 .JA(JA)
               );
  uart u_uart(
         .clk(clk),
         .rst(btnC),
         .rx(RsRx),
         .tx(RsTx)
       );
endmodule
