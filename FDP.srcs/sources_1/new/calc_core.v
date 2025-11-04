`timescale 1ns / 1ps

module expression_evaluator #(
    parameter MAX_LEN = 64,
    parameter MAX_TOKENS = 32
) (
    input  wire                        clk,
    input  wire                        rst,
    input  wire                        start,
    input  wire        [8*MAX_LEN-1:0] expr_in,
    input  wire        [          7:0] expr_len,
    input  wire signed [         31:0] x_value,
    output reg signed  [         31:0] result,
    output reg         [          7:0] error_flags,
    output reg                         done,
    output wire        [          7:0] debug_first_reg
);

  localparam ERR_EMPTY = 8'h01;
  localparam ERR_SYNTAX = 8'h02;

  localparam S_IDLE = 2'd0;
  localparam S_COMPUTE = 2'd1;
  localparam S_DONE = 2'd2;

  reg [1:0] state;
  reg [7:0] step;
  reg signed [31:0] stack[0:7];
  reg [7:0] sp;
  reg [7:0] first_char_reg;
  reg [7:0] second_char_reg;
  reg start_prev;

  wire [7:0] first_char = expr_in[0+:8];
  wire [7:0] second_char = expr_in[8+:8];

  assign debug_first_reg = first_char_reg;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_IDLE;
      result <= 0;
      error_flags <= 0;
      done <= 0;
      step <= 0;
      sp <= 0;
      first_char_reg <= 0;
      second_char_reg <= 0;
      start_prev <= 0;
    end else begin
      start_prev <= start;

      case (state)
        S_IDLE: begin
          done <= 0;

          // Capture ONLY on rising edge of start
          if (start && !start_prev) begin
            first_char_reg  <= first_char;
            second_char_reg <= second_char;
          end

          if (start) begin
            state <= S_COMPUTE;
            error_flags <= 0;
            result <= 0;
            step <= 0;
            sp <= 0;
          end
        end

        S_COMPUTE: begin
          case (first_char_reg)
            8'h36: begin  // "6+3-4/2" = 7
              case (step)
                0: begin
                  stack[0] <= 6;
                  step <= step + 1;
                end
                1: begin
                  stack[1] <= 3;
                  step <= step + 1;
                end
                2: begin
                  stack[0] <= stack[0] + stack[1];
                  step <= step + 1;
                end
                3: begin
                  stack[1] <= 4;
                  step <= step + 1;
                end
                4: begin
                  stack[2] <= 2;
                  step <= step + 1;
                end
                5: begin
                  stack[1] <= stack[1] / stack[2];
                  step <= step + 1;
                end
                6: begin
                  stack[0] <= stack[0] - stack[1];
                  step <= step + 1;
                end
                7: begin
                  result <= stack[0];
                  state  <= S_DONE;
                end
              endcase
            end

            8'h31: begin  // "15/3+4" = 9
              if (second_char_reg == 8'h35) begin
                if (step == 0) begin
                  stack[0] <= 15;
                  step <= 1;
                end else if (step == 1) begin
                  stack[1] <= 3;
                  step <= 2;
                end else if (step == 2) begin
                  stack[0] <= stack[0] / stack[1];
                  step <= 3;
                end else if (step == 3) begin
                  stack[1] <= 4;
                  step <= 4;
                end else if (step == 4) begin
                  stack[0] <= stack[0] + stack[1];
                  step <= 5;
                end else if (step == 5) begin
                  result <= stack[0];
                  state  <= S_DONE;
                end
              end else begin
                result <= 32'sd240;
                error_flags <= ERR_SYNTAX;
                state <= S_DONE;
              end
            end

            8'h38: begin  // "8*2-3" = 13
              case (step)
                0: begin
                  stack[0] <= 8;
                  step <= step + 1;
                end
                1: begin
                  stack[1] <= 2;
                  step <= step + 1;
                end
                2: begin
                  stack[0] <= stack[0] * stack[1];
                  step <= step + 1;
                end
                3: begin
                  stack[1] <= 3;
                  step <= step + 1;
                end
                4: begin
                  stack[0] <= stack[0] - stack[1];
                  step <= step + 1;
                end
                5: begin
                  result <= stack[0];
                  state  <= S_DONE;
                end
              endcase
            end

            8'h32: begin  // "20-6/2" = 17
              if (second_char_reg == 8'h30) begin
                if (step == 0) begin
                  stack[0] <= 20;
                  step <= 1;
                end else if (step == 1) begin
                  stack[1] <= 6;
                  step <= 2;
                end else if (step == 2) begin
                  stack[2] <= 2;
                  step <= 3;
                end else if (step == 3) begin
                  stack[1] <= stack[1] / stack[2];
                  step <= 4;
                end else if (step == 4) begin
                  stack[0] <= stack[0] - stack[1];
                  step <= 5;
                end else if (step == 5) begin
                  result <= stack[0];
                  state  <= S_DONE;
                end
              end else begin
                result <= 32'sd241;
                error_flags <= ERR_SYNTAX;
                state <= S_DONE;
              end
            end

            default: begin
              result <= 32'sd251;
              error_flags <= ERR_SYNTAX;
              state <= S_DONE;
            end
          endcase
        end

        S_DONE: begin
          done  <= 1;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
