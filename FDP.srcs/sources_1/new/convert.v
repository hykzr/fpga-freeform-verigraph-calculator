// Q16.16 decimal string parser (strtol-style, no-copy), timing-optimized.
// Fractional digits are split across two cycles via LUT + add.
// Errors: bit0 NO_DIGITS, bit1 OVERFLOW, bit2 UNEXPECTED
module str_to_q16_16 #(
    parameter MAX_LEN      = 64,
    parameter MAX_FRAC_DIG = 6
) (
    input wire clk,
    input wire rst,
    input wire start,

    input wire [8*MAX_LEN-1:0] expr_in,
    input wire [          7:0] expr_len,
    input wire [          7:0] base_idx,

    output reg signed [31:0] q_out,      // signed Q16.16
    output reg        [ 7:0] end_idx,    // first char AFTER parsed number
    output reg        [ 7:0] err_flags,  // see bits below
    output reg               done
);
  // -----------------------------
  // State machine
  // -----------------------------
  localparam [4:0]
        S_IDLE       = 5'd0,
        S_INIT       = 5'd1,
        S_SKIPWS     = 5'd2,
        S_SIGN       = 5'd3,
        S_INT        = 5'd4,
        S_FRAC       = 5'd5,
        S_FRAC_MUL   = 5'd6,   // new: LUT stage
  S_FRAC_ADD = 5'd7,  // new: add stage
  S_FIN_ROUND = 5'd8,  // new: rounding separated
  S_FIN_SIGN = 5'd9,  // new: sign separated
  S_DONE = 5'd10;

  // Error bits
  localparam [7:0] E_NONE = 8'h00, E_NO_DIGITS = 8'h01, E_OVERFLOW = 8'h02, E_UNEXPECTED = 8'h04;

  // ASCII
  localparam [7:0] CH_0 = "0";
  localparam [7:0] CH_9 = "9";
  localparam [7:0] CH_SP = " ";
  localparam [7:0] CH_TAB = 8'h09;
  localparam [7:0] CH_PLUS = "+";
  localparam [7:0] CH_MINUS = "-";
  localparam [7:0] CH_DOT = ".";

  // Q16.16 positive saturation (max positive)
  localparam [31:0] Q16_POS_MAX = 32'h7FFF_FFFF;

  // Rounding unit for the first dropped extra fractional digit (>= '5')
  // = 1 / 10^(MAX_FRAC_DIG) in Q16.16 (rounded)
  localparam [31:0] ROUND_UNIT_Q =
        (MAX_FRAC_DIG == 0) ? 32'h0000_0000 :
        (MAX_FRAC_DIG == 1) ? 32'd6554      : // 1/10
  (MAX_FRAC_DIG == 2) ? 32'd655 :  // 1/100
  (MAX_FRAC_DIG == 3) ? 32'd66 :  // 1/1000
  (MAX_FRAC_DIG == 4) ? 32'd7 :  // 1/10000
  (MAX_FRAC_DIG == 5) ? 32'd1 :  // 1/100000
  32'd0;  // 1/1000000 ~ 0 in Q16.16

  // -----------------------------
  // Registers
  // -----------------------------
  reg [4:0] state, state_n;

  reg [7:0] idx, idx_n;
  reg neg, neg_n;
  reg seen_digit, seen_digit_n;
  reg seen_dot, seen_dot_n;

  reg [2:0] frac_cnt, frac_cnt_n;  // number of fractional digits consumed (0..6)
  reg extra_round, extra_round_n;  // first dropped extra digit >= '5'

  reg [7:0] err, err_n;

  // magnitude accumulator (always non-negative here; sign applied at end)
  reg [31:0] acc_q, acc_q_n;

  // pipeline register for fractional LUT contribution (removes multiplier from path)
  reg [31:0] frac_mul_reg, frac_mul_reg_n;

  // Outputs next
  reg  [31:0] q_out_n;
  reg  [ 7:0] end_idx_n;
  reg  [ 7:0] err_flags_n;
  reg         done_n;

  // -----------------------------
  // Current character / classify
  // -----------------------------
  wire [ 7:0] cur_char = (idx < expr_len) ? expr_in[8*idx+:8] : 8'd0;

  wire        is_ws = (cur_char == CH_SP) || (cur_char == CH_TAB);
  wire        is_digit = (cur_char >= CH_0) && (cur_char <= CH_9);
  wire [ 7:0] ch_delta = cur_char - CH_0;
  wire [ 3:0] digit_val = is_digit ? ch_delta[3:0] : 4'd0;
  wire        is_plus = (cur_char == CH_PLUS);
  wire        is_minus = (cur_char == CH_MINUS);
  wire        is_dot = (cur_char == CH_DOT);

  // -----------------------------
  // Integer lane (single-cycle): acc = acc*10 + (digit<<16) with saturation
  // -----------------------------
  wire [33:0] acc_ext = {2'b00, acc_q};
  wire [33:0] acc_mul8 = acc_ext << 3;
  wire [33:0] acc_mul2 = acc_ext << 1;
  wire [33:0] acc_mul10 = acc_mul8 + acc_mul2;
  wire [31:0] int_add_q16 = {digit_val, 16'h0000};  // (digit << 16)
  wire [33:0] int_add_ext = {2'b00, int_add_q16};
  wire [33:0] int_sum_ext = acc_mul10 + int_add_ext;
  wire        int_overflow = (int_sum_ext > {2'b00, Q16_POS_MAX});
  wire [31:0] int_next_q = int_overflow ? Q16_POS_MAX : int_sum_ext[31:0];

  // -----------------------------
  // Fractional LUT (separate module) and add saturation
  // -----------------------------
  wire [31:0] frac_lut_q;
  frac_digit_lut_q16 lut_inst (
      .frac_idx(frac_cnt),   // 0 => 1st fractional digit (k=1)
      .digit   (digit_val),  // 0..9
      .value   (frac_lut_q)  // Q16.16
  );

  // add with saturation
  wire [32:0] frac_sum33 = {1'b0, acc_q} + {1'b0, frac_mul_reg};  // 33-bit for carry
  wire        frac_of = frac_sum33[32] || (frac_sum33[31:0] > Q16_POS_MAX);
  wire [31:0] frac_next_q = frac_of ? Q16_POS_MAX : frac_sum33[31:0];

  // Rounding add with saturation (at finish)
  wire [32:0] round_sum33 = {1'b0, acc_q} + {1'b0, ROUND_UNIT_Q};
  wire        round_of = round_sum33[32] || (round_sum33[31:0] > Q16_POS_MAX);
  wire [31:0] round_next = round_of ? Q16_POS_MAX : round_sum33[31:0];

  // -----------------------------
  // Next-state logic
  // -----------------------------
  always @* begin
    // defaults (hold)
    state_n        = state;
    idx_n          = idx;
    neg_n          = neg;
    seen_digit_n   = seen_digit;
    seen_dot_n     = seen_dot;
    frac_cnt_n     = frac_cnt;
    extra_round_n  = extra_round;
    acc_q_n        = acc_q;
    frac_mul_reg_n = frac_mul_reg;
    err_n          = err;

    q_out_n        = q_out;
    end_idx_n      = end_idx;
    err_flags_n    = err_flags;
    done_n         = 1'b0;

    case (state)
      S_IDLE: begin
        if (start) state_n = S_INIT;
      end

      S_INIT: begin
        idx_n          = base_idx;
        neg_n          = 1'b0;
        seen_digit_n   = 1'b0;
        seen_dot_n     = 1'b0;
        frac_cnt_n     = 3'd0;
        extra_round_n  = 1'b0;
        acc_q_n        = 32'd0;
        frac_mul_reg_n = 32'd0;
        err_n          = E_NONE;
        state_n        = S_SKIPWS;
      end

      S_SKIPWS: begin
        if (idx >= expr_len) begin
          err_n     = E_NO_DIGITS;
          q_out_n   = 32'sd0;
          end_idx_n = base_idx;
          state_n   = S_DONE;
        end else if (is_ws) begin
          idx_n = idx + 8'd1;
        end else begin
          state_n = S_SIGN;
        end
      end

      S_SIGN: begin
        if (idx >= expr_len) begin
          err_n     = E_NO_DIGITS;
          q_out_n   = 32'sd0;
          end_idx_n = base_idx;
          state_n   = S_DONE;
        end else if (is_plus) begin
          neg_n   = 1'b0;
          idx_n   = idx + 8'd1;
          state_n = S_INT;
        end else if (is_minus) begin
          neg_n   = 1'b1;
          idx_n   = idx + 8'd1;
          state_n = S_INT;
        end else if (is_digit) begin
          state_n = S_INT;  // consume digit right away
        end else if (is_dot) begin
          if (MAX_FRAC_DIG == 0) begin
            err_n     = E_UNEXPECTED | E_NO_DIGITS;
            q_out_n   = 32'sd0;
            end_idx_n = base_idx;
            state_n   = S_DONE;
          end else begin
            seen_dot_n = 1'b1;
            idx_n      = idx + 8'd1;
            state_n    = S_FRAC;
          end
        end else begin
          err_n     = E_NO_DIGITS;
          q_out_n   = 32'sd0;
          end_idx_n = base_idx;
          state_n   = S_DONE;
        end
      end

      // Integer lane stays single-cycle
      S_INT: begin
        if (idx < expr_len && is_digit) begin
          acc_q_n = int_next_q;
          if (int_overflow) err_n = err | E_OVERFLOW;
          seen_digit_n = 1'b1;
          idx_n        = idx + 8'd1;
        end else if (idx < expr_len && is_dot && (MAX_FRAC_DIG != 0) && !seen_dot) begin
          seen_dot_n = 1'b1;
          idx_n      = idx + 8'd1;
          state_n    = S_FRAC;
        end else begin
          // integer-only number ends here
          state_n = S_FIN_ROUND;
        end
      end

      // Control for fractional lane
      S_FRAC: begin
        if (MAX_FRAC_DIG == 0) begin
          state_n = S_FIN_ROUND;
        end else if (idx < expr_len && is_digit) begin
          if (frac_cnt < ((MAX_FRAC_DIG > 6) ? 3'd6 : MAX_FRAC_DIG[2:0])) begin
            // Stage 1: read LUT, latch next cycle
            state_n = S_FRAC_MUL;
          end else begin
            // beyond precision budget; only track first dropped >= '5' for rounding
            if (!extra_round && (cur_char >= ("0" + 5))) extra_round_n = 1'b1;
            idx_n   = idx + 8'd1;
            state_n = S_FRAC;
          end
        end else begin
          state_n = S_FIN_ROUND;
        end
      end

      // Stage 1: latch LUT output (short cone)
      S_FRAC_MUL: begin
        frac_mul_reg_n = frac_lut_q;  // from table
        state_n        = S_FRAC_ADD;
      end

      // Stage 2: add & saturate (short cone)
      S_FRAC_ADD: begin
        acc_q_n = frac_next_q;
        if (frac_of) err_n = err | E_OVERFLOW;
        frac_cnt_n   = frac_cnt + 3'd1;
        seen_digit_n = 1'b1;
        idx_n        = idx + 8'd1;
        state_n      = S_FRAC;
      end

      // Separate rounding (if needed)
      S_FIN_ROUND: begin
        if (seen_digit && extra_round && (ROUND_UNIT_Q != 32'd0)) begin
          acc_q_n = round_next;
          if (round_of) err_n = err | E_OVERFLOW;
        end
        state_n = S_FIN_SIGN;
      end

      // Separate sign
      S_FIN_SIGN: begin
        if (!seen_digit) begin
          err_n     = err | E_NO_DIGITS;
          q_out_n   = 32'sd0;
          end_idx_n = base_idx;
        end else begin
          q_out_n   = neg ? -$signed(acc_q) : $signed(acc_q);
          end_idx_n = idx;
        end
        state_n = S_DONE;
      end

      S_DONE: begin
        done_n      = 1'b1;
        err_flags_n = err;
        state_n     = S_IDLE;
      end

      default: state_n = S_IDLE;
    endcase
  end

  // -----------------------------
  // Sequential
  // -----------------------------
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state        <= S_IDLE;
      idx          <= 8'd0;
      neg          <= 1'b0;
      seen_digit   <= 1'b0;
      seen_dot     <= 1'b0;
      frac_cnt     <= 3'd0;
      extra_round  <= 1'b0;
      acc_q        <= 32'd0;
      frac_mul_reg <= 32'd0;
      err          <= E_NONE;
      q_out        <= 32'sd0;
      end_idx      <= 8'd0;
      err_flags    <= 8'd0;
      done         <= 1'b0;
    end else begin
      state        <= state_n;
      idx          <= idx_n;
      neg          <= neg_n;
      seen_digit   <= seen_digit_n;
      seen_dot     <= seen_dot_n;
      frac_cnt     <= frac_cnt_n;
      extra_round  <= extra_round_n;
      acc_q        <= acc_q_n;
      frac_mul_reg <= frac_mul_reg_n;
      err          <= err_n;
      q_out        <= q_out_n;
      end_idx      <= end_idx_n;
      err_flags    <= err_flags_n;
      done         <= done_n;
    end
  end
endmodule


module frac_digit_lut_q16 (
    input wire [2:0] frac_idx,  // 0=>1st decimal place, 1=>2nd, ...
    input wire [3:0] digit,  // 0..9
    output reg [31:0] value
);
  always @* begin
    // default
    value = 16'd0;
    case (frac_idx)
      // k = 1 => /10, each = round(d * 65536/10)
      3'd0: begin
        case (digit)
          4'd0: value = 16'd0;
          4'd1: value = 16'd6554;
          4'd2: value = 16'd13107;
          4'd3: value = 16'd19661;
          4'd4: value = 16'd26214;
          4'd5: value = 16'd32768;
          4'd6: value = 16'd39322;
          4'd7: value = 16'd45875;
          4'd8: value = 16'd52429;
          default: value = 16'd58982;  // 9
        endcase
      end
      // k = 2 => /100
      3'd1: begin
        case (digit)
          4'd0: value = 16'd0;
          4'd1: value = 16'd655;
          4'd2: value = 16'd1311;
          4'd3: value = 16'd1966;
          4'd4: value = 16'd2621;
          4'd5: value = 16'd3277;
          4'd6: value = 16'd3932;
          4'd7: value = 16'd4588;  // 4587.52 -> 4588
          4'd8: value = 16'd5243;
          default: value = 16'd5898;  // 9
        endcase
      end
      // k = 3 => /1000
      3'd2: begin
        case (digit)
          4'd0: value = 16'd0;
          4'd1: value = 16'd66;  // 65.536 -> 66
          4'd2: value = 16'd131;  // 131.072 -> 131
          4'd3: value = 16'd197;
          4'd4: value = 16'd262;
          4'd5: value = 16'd328;  // 327.68 -> 328
          4'd6: value = 16'd393;
          4'd7: value = 16'd459;  // 458.752 -> 459
          4'd8: value = 16'd524;
          default: value = 16'd590;  // 589.824 -> 590
        endcase
      end
      // k = 4 => /10000
      3'd3: begin
        case (digit)
          4'd0: value = 16'd0;
          4'd1: value = 16'd7;
          4'd2: value = 16'd13;
          4'd3: value = 16'd20;
          4'd4: value = 16'd26;
          4'd5: value = 16'd33;
          4'd6: value = 16'd39;
          4'd7: value = 16'd46;
          4'd8: value = 16'd52;
          default: value = 16'd59;  // 9
        endcase
      end
      // k = 5 => /100000
      3'd4: begin
        case (digit)
          4'd0: value = 16'd0;
          4'd1: value = 16'd1;
          4'd2: value = 16'd1;
          4'd3: value = 16'd2;
          4'd4: value = 16'd3;
          4'd5: value = 16'd3;
          4'd6: value = 16'd4;
          4'd7: value = 16'd5;
          4'd8: value = 16'd5;
          default: value = 16'd6;  // 9
        endcase
      end
      default: value = 16'd0;
    endcase
  end
endmodule

module q16_to_str3 (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   start,
    input  wire signed [    31:0] val_q16,
    output reg         [8*10-1:0] str_le,
    output reg         [     7:0] str_len,
    output reg                    done
);

  reg [2:0] state;
  reg is_neg;
  reg [31:0] abs_val;
  reg [15:0] int_part;
  reg [31:0] frac_scaled;
  reg [31:0] frac_rounded;
  reg [9:0] frac_final;

  // Use flat bit vectors instead of 2D arrays
  reg [79:0] temp_str;  // 10 bytes x 8 bits
  reg [19:0] int_digits;  // 5 digits x 4 bits  
  reg [11:0] frac_digits;  // 3 digits x 4 bits

  reg [3:0] int_digit_count;
  reg [3:0] frac_digit_count;
  reg [7:0] write_pos;
  reg [3:0] i;

  always @(posedge clk) begin
    if (rst) begin
      state <= 0;
      done <= 0;
      str_le <= 0;
      str_len <= 0;
      is_neg <= 0;
      abs_val <= 0;
      int_part <= 0;
      frac_scaled <= 0;
      frac_rounded <= 0;
      frac_final <= 0;
      temp_str <= 0;
      int_digits <= 0;
      frac_digits <= 0;
      int_digit_count <= 0;
      frac_digit_count <= 0;
      write_pos <= 0;
      i <= 0;
    end else begin
      done <= 0;

      case (state)
        0: begin  // IDLE
          if (start) begin
            is_neg  <= val_q16[31];
            abs_val <= val_q16[31] ? -val_q16 : val_q16;
            state   <= 1;
          end
        end

        1: begin  // Extract integer and fractional parts
          int_part <= abs_val[31:16];
          frac_scaled <= abs_val[15:0] * 32'd1000;
          state <= 2;
        end

        2: begin  // Divide and round
          frac_rounded <= frac_scaled + 32'd32768;
          state <= 3;
        end

        3: begin  // Complete rounding
          frac_final <= frac_rounded[25:16];

          // FIX: Check for zero and output "0" with length 1
          if (int_part == 0 && frac_rounded[25:16] == 0) begin
            // Special case: output "0"
            temp_str[7:0] <= 8'd48;  // '0' at position 0
            write_pos <= 1;  // CRITICAL FIX: was missing
            state <= 7;  // Skip to done
          end else begin
            state <= 4;
          end
        end

        4: begin  // Convert integer part to digits
          if (int_part >= 10000) begin
            int_digits[19:16] <= int_part / 10000;
            int_digits[15:12] <= (int_part / 1000) % 10;
            int_digits[11:8]  <= (int_part / 100) % 10;
            int_digits[7:4]   <= (int_part / 10) % 10;
            int_digits[3:0]   <= int_part % 10;
            int_digit_count   <= 5;
          end else if (int_part >= 1000) begin
            int_digits[15:12] <= int_part / 1000;
            int_digits[11:8]  <= (int_part / 100) % 10;
            int_digits[7:4]   <= (int_part / 10) % 10;
            int_digits[3:0]   <= int_part % 10;
            int_digit_count   <= 4;
          end else if (int_part >= 100) begin
            int_digits[11:8] <= int_part / 100;
            int_digits[7:4]  <= (int_part / 10) % 10;
            int_digits[3:0]  <= int_part % 10;
            int_digit_count  <= 3;
          end else if (int_part >= 10) begin
            int_digits[7:4] <= int_part / 10;
            int_digits[3:0] <= int_part % 10;
            int_digit_count <= 2;
          end else begin
            int_digits[3:0] <= int_part;
            int_digit_count <= 1;
          end

          // Convert fractional part to digits
          frac_digits[11:8] <= frac_final / 100;
          frac_digits[7:4]  <= (frac_final / 10) % 10;
          frac_digits[3:0]  <= frac_final % 10;

          // Trim trailing zeros
          if ((frac_final % 10) != 0) begin
            frac_digit_count <= 3;
          end else if (((frac_final / 10) % 10) != 0) begin
            frac_digit_count <= 2;
          end else if ((frac_final / 100) != 0) begin
            frac_digit_count <= 1;
          end else begin
            frac_digit_count <= 0;
          end

          write_pos <= 0;
          temp_str <= 0;
          state <= 5;
        end

        5: begin  // Add sign if negative
          if (is_neg) begin
            temp_str[7:0] <= 8'd45;  // '-'
            write_pos <= 1;
          end
          i <= 0;
          state <= 6;
        end

        6: begin  // Write digits
          if (i < int_digit_count) begin
            // Write integer digits MSB to LSB
            // Access digit at position (int_digit_count-1-i)
            case (int_digit_count - 1 - i)
              0: temp_str[write_pos*8+:8] <= 8'd48 + int_digits[3:0];
              1: temp_str[write_pos*8+:8] <= 8'd48 + int_digits[7:4];
              2: temp_str[write_pos*8+:8] <= 8'd48 + int_digits[11:8];
              3: temp_str[write_pos*8+:8] <= 8'd48 + int_digits[15:12];
              4: temp_str[write_pos*8+:8] <= 8'd48 + int_digits[19:16];
            endcase
            write_pos <= write_pos + 1;
            i <= i + 1;
          end else if (frac_digit_count > 0 && i == int_digit_count) begin
            // Add decimal point
            temp_str[write_pos*8+:8] <= 8'd46;  // '.'

            // Add fractional digits - unroll to avoid complex indexing
            if (frac_digit_count >= 1) temp_str[(write_pos+1)*8+:8] <= 8'd48 + frac_digits[11:8];
            if (frac_digit_count >= 2) temp_str[(write_pos+2)*8+:8] <= 8'd48 + frac_digits[7:4];
            if (frac_digit_count >= 3) temp_str[(write_pos+3)*8+:8] <= 8'd48 + frac_digits[3:0];

            write_pos <= write_pos + 1 + frac_digit_count;
            state <= 7;
          end else begin
            state <= 7;
          end
        end

        7: begin  // Finalize
          str_len <= write_pos;
          str_le <= temp_str;
          done <= 1;
          state <= 0;
        end

        default: state <= 0;
      endcase
    end
  end

endmodule
