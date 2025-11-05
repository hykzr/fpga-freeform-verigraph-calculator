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
    output reg                         done
);

  localparam ERR_EMPTY = 8'h01;
  localparam ERR_SYNTAX = 8'h02;
  localparam ERR_DIV_ZERO = 8'h04;

  // States
  localparam S_IDLE = 4'd0;
  localparam S_PARSE = 4'd1;
  localparam S_PARSE_WAIT = 4'd2;
  localparam S_EVAL_PASS1_SCAN = 4'd3;
  localparam S_EVAL_PASS1_CALC = 4'd4;
  localparam S_EVAL_PASS1_SHIFT = 4'd5;
  localparam S_EVAL_PASS1_SHIFT_WAIT = 4'd10;
  localparam S_EVAL_PASS2_SCAN = 4'd6;
  localparam S_EVAL_PASS2_CALC = 4'd7;
  localparam S_EVAL_PASS2_SHIFT = 4'd8;
  localparam S_DONE = 4'd9;

  reg [3:0] state, next_state;
  reg [7:0] char_pos;
  reg [7:0] current_char;

  // Storage - using fixed size arrays
  reg signed [31:0] nums[0:MAX_TOKENS-1];
  reg [7:0] ops[0:MAX_TOKENS-1];
  reg [4:0] num_cnt;
  reg [4:0] op_cnt;
  reg signed [31:0] temp_num;
  reg building_number;
  reg temp_neg;

  // Evaluation
  reg [4:0] eval_pos;
  reg signed [31:0] op_result;
  reg [4:0] shift_cnt;
  reg need_shift;

  reg start_prev;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_IDLE;
      result <= 0;
      error_flags <= 0;
      done <= 0;
      char_pos <= 0;
      num_cnt <= 0;
      op_cnt <= 0;
      temp_num <= 0;
      building_number <= 0;
      temp_neg <= 0;
      eval_pos <= 0;
      op_result <= 0;
      shift_cnt <= 0;
      need_shift <= 0;
      start_prev <= 0;
      current_char <= 0;
      next_state <= S_IDLE;
    end else begin
      start_prev <= start;

      case (state)
        S_IDLE: begin
          done <= 0;
          if (start && !start_prev) begin
            if (expr_len == 0) begin
              error_flags <= ERR_EMPTY;
              result <= 0;
              done <= 1;
            end else begin
              state <= S_PARSE;
              char_pos <= 0;
              num_cnt <= 0;
              op_cnt <= 0;
              temp_num <= 0;
              building_number <= 0;
              temp_neg <= 0;
              error_flags <= 0;
            end
          end
        end

        S_PARSE: begin
          if (char_pos < expr_len) begin
            current_char <= expr_in[8*(MAX_LEN-1-char_pos)+:8];
            state <= S_PARSE_WAIT;
          end else begin
            // End of parsing
            if (building_number) begin
              nums[num_cnt] <= temp_neg ? -temp_num : temp_num;
              num_cnt <= num_cnt + 1;
            end

            if (num_cnt == 0 && !building_number) begin
              error_flags <= ERR_SYNTAX;
              done <= 1;
              state <= S_IDLE;
            end else begin
              eval_pos <= 0;
              state <= S_EVAL_PASS1_SCAN;
            end
          end
        end

        S_PARSE_WAIT: begin
          if (current_char >= 8'h30 && current_char <= 8'h39) begin
            // Digit
            temp_num <= temp_num * 10 + (current_char - 8'h30);
            building_number <= 1;
            char_pos <= char_pos + 1;
            state <= S_PARSE;
          end else if (current_char == 8'h2B || current_char == 8'h2D || 
                                 current_char == 8'h2A || current_char == 8'h2F) begin
            // Operator
            if (building_number) begin
              nums[num_cnt] <= temp_neg ? -temp_num : temp_num;
              num_cnt <= num_cnt + 1;
              temp_num <= 0;
              temp_neg <= 0;
              building_number <= 0;
              ops[op_cnt] <= current_char;
              op_cnt <= op_cnt + 1;
            end else if (current_char == 8'h2D && num_cnt == 0) begin
              temp_neg <= 1;
            end else begin
              error_flags <= ERR_SYNTAX;
              done <= 1;
              state <= S_IDLE;
            end
            char_pos <= char_pos + 1;
            state <= S_PARSE;
          end else if (current_char == 8'h20 || current_char == 8'h00) begin
            // Space/null
            if (building_number) begin
              nums[num_cnt] <= temp_neg ? -temp_num : temp_num;
              num_cnt <= num_cnt + 1;
              temp_num <= 0;
              temp_neg <= 0;
              building_number <= 0;
            end
            char_pos <= char_pos + 1;
            state <= S_PARSE;
          end else begin
            error_flags <= ERR_SYNTAX;
            done <= 1;
            state <= S_IDLE;
          end
        end

        // PASS 1: Handle * and /
        S_EVAL_PASS1_SCAN: begin
          if (eval_pos < op_cnt) begin
            if (ops[eval_pos] == 8'h2A || ops[eval_pos] == 8'h2F) begin
              // Found high precedence operator
              state <= S_EVAL_PASS1_CALC;
            end else begin
              eval_pos <= eval_pos + 1;
            end
          end else begin
            // Pass 1 complete, start pass 2
            eval_pos <= 0;
            state <= S_EVAL_PASS2_SCAN;
          end
        end

        S_EVAL_PASS1_CALC: begin
          if (ops[eval_pos] == 8'h2A) begin
            op_result <= nums[eval_pos] * nums[eval_pos+1];
            need_shift <= 1;
            shift_cnt <= 0;
            state <= S_EVAL_PASS1_SHIFT;
          end else if (ops[eval_pos] == 8'h2F) begin
            if (nums[eval_pos+1] == 0) begin
              error_flags <= ERR_DIV_ZERO;
              done <= 1;
              state <= S_IDLE;
            end else begin
              // Perform signed division
              op_result <= $signed(nums[eval_pos]) / $signed(nums[eval_pos+1]);
              need_shift <= 1;
              shift_cnt <= 0;
              state <= S_EVAL_PASS1_SHIFT;
            end
          end else begin
            // Should not reach here, but handle gracefully
            error_flags <= ERR_SYNTAX;
            done <= 1;
            state <= S_IDLE;
          end
        end

        S_EVAL_PASS1_SHIFT: begin
          if (shift_cnt == 0) begin
            // Store result
            nums[eval_pos] <= op_result;
            shift_cnt <= eval_pos + 1;
          end else if (shift_cnt < MAX_TOKENS - 1) begin
            // Shift arrays
            nums[shift_cnt] <= nums[shift_cnt+1];
            ops[shift_cnt-1] <= ops[shift_cnt];
            shift_cnt <= shift_cnt + 1;
          end else begin
            // Shift complete
            num_cnt <= num_cnt - 1;
            op_cnt <= op_cnt - 1;
            need_shift <= 0;
            state <= S_EVAL_PASS1_SCAN;
          end
        end

        // PASS 2: Handle + and -
        S_EVAL_PASS2_SCAN: begin
          if (eval_pos < op_cnt) begin
            if (ops[eval_pos] == 8'h2B || ops[eval_pos] == 8'h2D) begin
              state <= S_EVAL_PASS2_CALC;
            end else begin
              eval_pos <= eval_pos + 1;
            end
          end else begin
            // Done
            result <= nums[0];
            done   <= 1;
            state  <= S_DONE;
          end
        end

        S_EVAL_PASS2_CALC: begin
          if (ops[eval_pos] == 8'h2B) begin
            op_result <= nums[eval_pos] + nums[eval_pos+1];
          end else begin
            op_result <= nums[eval_pos] - nums[eval_pos+1];
          end
          need_shift <= 1;
          shift_cnt <= 0;
          state <= S_EVAL_PASS2_SHIFT;
        end

        S_EVAL_PASS2_SHIFT: begin
          if (shift_cnt == 0) begin
            nums[eval_pos] <= op_result;
            shift_cnt <= eval_pos + 1;
          end else if (shift_cnt < MAX_TOKENS - 1) begin
            nums[shift_cnt] <= nums[shift_cnt+1];
            ops[shift_cnt-1] <= ops[shift_cnt];
            shift_cnt <= shift_cnt + 1;
          end else begin
            num_cnt <= num_cnt - 1;
            op_cnt <= op_cnt - 1;
            need_shift <= 0;
            state <= S_EVAL_PASS2_SCAN;
          end
        end

        S_DONE: begin
          if (!start) begin
            state <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
