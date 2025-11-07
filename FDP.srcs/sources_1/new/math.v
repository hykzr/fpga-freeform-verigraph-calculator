//------------------------------------------------------------------------------
// math.v : Q16.16 math submodules (uniform outputs; unary/binary as needed)
// Error bit convention:
//   bit0 ERR_NEG_INPUT (for sqrt)
//   bit1 ERR_DIV_ZERO
//   bit5 OVERFLOW (saturation)
//------------------------------------------------------------------------------

module math_add_q16 (
    input  wire               clk,
    rst,
    start,
    input  wire signed [31:0] a,
    input  wire signed [31:0] b,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);
  localparam signed [31:0] Q16_MAX = 32'h7FFF_FFFF;
  localparam signed [31:0] Q16_MIN = 32'h8000_0000;

  reg signed [32:0] s;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        s = a + b;
        if (s[32] != s[31]) begin
          y   <= s[31] ? Q16_MIN : Q16_MAX;
          err <= 8'h20;  // OVERFLOW
        end else begin
          y   <= s[31:0];
          err <= 8'd0;
        end
        ready <= 1'b1;
      end
    end
  end
endmodule

module math_sub_q16 (
    input  wire               clk,
    rst,
    start,
    input  wire signed [31:0] a,
    input  wire signed [31:0] b,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);
  localparam signed [31:0] Q16_MAX = 32'h7FFF_FFFF;
  localparam signed [31:0] Q16_MIN = 32'h8000_0000;

  reg signed [32:0] s;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        s = a - b;
        if (s[32] != s[31]) begin
          y   <= s[31] ? Q16_MIN : Q16_MAX;
          err <= 8'h20;  // OVERFLOW
        end else begin
          y   <= s[31:0];
          err <= 8'd0;
        end
        ready <= 1'b1;
      end
    end
  end
endmodule

module math_floor_q16 (
    input  wire               clk,
    rst,
    start,
    input  wire signed [31:0] a,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);
  localparam signed [31:0] Q16_MAX = 32'h7FFF_FFFF;
  localparam signed [31:0] Q16_MIN = 32'h8000_0000;

  wire signed [31:0] ai = {a[31:16], 16'h0000};
  wire frac_nz = |a[15:0];
  wire at_min = (ai == Q16_MIN);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        if (a[31] && frac_nz) begin
          if (at_min) begin
            y   <= Q16_MIN;
            err <= 8'h20;
          end else begin
            y   <= ai - 32'sh0001_0000;
            err <= 8'd0;
          end
        end else begin
          y   <= ai;
          err <= 8'd0;
        end
        ready <= 1'b1;
      end
    end
  end
endmodule

module math_ceil_q16 (
    input  wire               clk,
    rst,
    start,
    input  wire signed [31:0] a,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);
  localparam signed [31:0] Q16_MAX = 32'h7FFF_FFFF;

  wire signed [31:0] ai = {a[31:16], 16'h0000};
  wire frac_nz = |a[15:0];
  wire at_maxi = (ai == 32'sh7FFF_0000);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        if (!a[31] && frac_nz) begin
          if (at_maxi) begin
            y   <= Q16_MAX;
            err <= 8'h20;
          end else begin
            y   <= ai + 32'sh0001_0000;
            err <= 8'd0;
          end
        end else begin
          y   <= ai;
          err <= 8'd0;
        end
        ready <= 1'b1;
      end
    end
  end
endmodule

module math_round_q16 (
    input  wire               clk,
    rst,
    start,
    input  wire signed [31:0] a,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);
  localparam signed [31:0] Q16_MAX = 32'h7FFF_FFFF;
  localparam signed [31:0] Q16_MIN = 32'h8000_0000;

  wire signed [31:0] bias = a[31] ? -32'sh0000_8000 : 32'sh0000_8000;
  wire signed [32:0] sum = a + bias;
  wire ov_pos = (!a[31]) && (sum[32] != sum[31] || sum[31:0] > Q16_MAX);
  wire ov_neg = (a[31]) && (sum[32] != sum[31] || sum[31:0] < Q16_MIN);
  wire any_ov = ov_pos || ov_neg;
  wire signed [31:0] rounded = {sum[31:16], 16'h0000};

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        if (any_ov) begin
          y   <= a[31] ? Q16_MIN : Q16_MAX;
          err <= 8'h20;
        end else begin
          y   <= rounded;
          err <= 8'd0;
        end
        ready <= 1'b1;
      end
    end
  end
endmodule

module math_abs_q16 (
    input  wire               clk,
    rst,
    start,
    input  wire signed [31:0] a,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);
  localparam signed [31:0] Q16_MAX = 32'h7FFF_FFFF;
  localparam signed [31:0] Q16_MIN = 32'h8000_0000;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        if (a == Q16_MIN) begin
          y   <= Q16_MAX;
          err <= 8'h20;  // OVERFLOW
        end else begin
          y   <= (a[31]) ? -a : a;
          err <= 8'd0;
        end
        ready <= 1'b1;
      end
    end
  end
endmodule

module math_max_q16 (
    input  wire               clk,
    rst,
    start,
    input  wire signed [31:0] a,
    input  wire signed [31:0] b,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y <= ($signed(a) > $signed(b)) ? a : b;
        err <= 8'd0;
        ready <= 1'b1;
      end
    end
  end
endmodule

module math_min_q16 (
    input  wire               clk,
    rst,
    start,
    input  wire signed [31:0] a,
    input  wire signed [31:0] b,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y <= ($signed(a) < $signed(b)) ? a : b;
        err <= 8'd0;
        ready <= 1'b1;
      end
    end
  end
endmodule

// module math_rem_q16 (
//     input  wire               clk,
//     rst,
//     start,
//     input  wire signed [31:0] a,
//     input  wire signed [31:0] b,
//     output reg signed  [31:0] y,
//     output reg                ready,
//     output reg         [ 7:0] err
// );
//   always @(posedge clk or posedge rst) begin
//     if (rst) begin
//       y <= 32'sd0;
//       ready <= 1'b0;
//       err <= 8'd0;
//     end else begin
//       ready <= 1'b0;
//       if (start) begin
//         if (b == 32'sd0) begin
//           y   <= 32'sd0;
//           err <= 8'h02;  // DIV_ZERO
//         end else begin
//           // Integer remainder: a%b for integers only
//           y   <= {(a[31:16] % b[31:16]), 16'h0000};
//           err <= 8'd0;
//         end
//         ready <= 1'b1;
//       end
//     end
//   end
// endmodule

// Binary bitwise operations (work on integer part only)
module math_and_q16 (
    input  wire               clk,
    rst,
    start,
    input  wire signed [31:0] a,
    input  wire signed [31:0] b,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y <= {(a[31:16] & b[31:16]), 16'h0000};
        err <= 8'd0;
        ready <= 1'b1;
      end
    end
  end
endmodule

module math_or_q16 (
    input  wire               clk,
    rst,
    start,
    input  wire signed [31:0] a,
    input  wire signed [31:0] b,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y <= {(a[31:16] | b[31:16]), 16'h0000};
        err <= 8'd0;
        ready <= 1'b1;
      end
    end
  end
endmodule

module math_xor_q16 (
    input  wire               clk,
    rst,
    start,
    input  wire signed [31:0] a,
    input  wire signed [31:0] b,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y <= {(a[31:16] ^ b[31:16]), 16'h0000};
        err <= 8'd0;
        ready <= 1'b1;
      end
    end
  end
endmodule

module math_not_q16 (
    input  wire               clk,
    rst,
    start,
    input  wire signed [31:0] a,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y <= {(~a[31:16]), 16'h0000};
        err <= 8'd0;
        ready <= 1'b1;
      end
    end
  end
endmodule

module math_mul_q16 (
    input wire clk,
    rst,
    start,
    input wire signed [31:0] a,
    b,
    output reg signed [31:0] y,
    output reg ready,
    output reg [7:0] err
);
  reg [1:0] state;
  reg signed [63:0] product;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
      state <= 2'd0;
      product <= 64'sd0;
    end else begin
      case (state)
        2'd0: begin
          ready <= 1'b0;
          if (start) begin
            product <= a * b;
            state   <= 2'd1;
          end
        end
        2'd1: begin
          y <= product[47:16];
          err <= 8'd0;
          ready <= 1'b1;
          state <= 2'd0;
        end
        default: state <= 2'd0;
      endcase
    end
  end
endmodule

module math_div_q16 (
    input wire clk,
    rst,
    start,
    input wire signed [31:0] a,
    b,
    output reg signed [31:0] y,
    output reg signed [31:0] remainder,
    output reg ready,
    output reg [7:0] err
);
  reg [5:0] state;
  reg [5:0] bit_count;
  reg a_sign;
  reg b_sign;
  reg [47:0] dividend;
  reg [31:0] divisor;
  reg [47:0] quotient;
  reg [47:0] partial_rem;
  reg [48:0] temp_sub;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      remainder <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
      state <= 6'd0;
      bit_count <= 6'd0;
      a_sign <= 1'b0;
      b_sign <= 1'b0;
      dividend <= 48'd0;
      divisor <= 32'd0;
      quotient <= 48'd0;
      partial_rem <= 48'd0;
      temp_sub <= 49'd0;
    end else begin
      case (state)
        6'd0: begin
          ready <= 1'b0;
          if (start) begin
            if (b == 32'sd0) begin
              y <= 32'sd0;
              remainder <= 32'sd0;
              err <= 8'h02;
              ready <= 1'b1;
              state <= 6'd0;
            end else begin
              a_sign <= a[31];
              b_sign <= b[31];
              dividend <= (a[31] ? -a : a);
              divisor <= (b[31] ? -b : b);
              quotient <= 48'd0;
              partial_rem <= 48'd0;
              bit_count <= 6'd47;
              state <= 6'd1;
            end
          end
        end

        6'd1: begin
          partial_rem <= partial_rem << 1;
          partial_rem[0] <= dividend[bit_count];
          state <= 6'd2;
        end

        6'd2: begin
          temp_sub <= partial_rem - {16'd0, divisor, 1'b0};
          state <= 6'd3;
        end

        6'd3: begin
          if (!temp_sub[48]) begin
            partial_rem <= temp_sub[47:0];
            quotient[bit_count] <= 1'b1;
          end

          if (bit_count == 6'd0) begin
            state <= 6'd4;
          end else begin
            bit_count <= bit_count - 6'd1;
            state <= 6'd1;
          end
        end

        6'd4: begin
          if (a_sign ^ b_sign) begin
            y <= -(quotient[31:0]);
          end else begin
            y <= quotient[31:0];
          end

          if (a_sign) begin
            remainder <= -(partial_rem[31:0]);
          end else begin
            remainder <= partial_rem[31:0];
          end

          err   <= 8'd0;
          ready <= 1'b1;
          state <= 6'd0;
        end

        default: state <= 6'd0;
      endcase
    end
  end
endmodule

module math_pow_q16 (
    input wire clk,
    rst,
    start,
    input wire signed [31:0] a,
    b,
    output reg signed [31:0] y,
    output reg ready,
    output reg [7:0] err
);
  reg [5:0] state;
  reg signed [63:0] result;
  reg signed [31:0] base;
  reg signed [31:0] exp_remaining;
  reg exp_negative;
  reg signed [63:0] temp_result;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
      state <= 6'd0;
      result <= 64'sd0;
      base <= 32'sd0;
      exp_remaining <= 32'sd0;
      exp_negative <= 1'b0;
      temp_result <= 64'sd0;
    end else begin
      case (state)
        6'd0: begin
          ready <= 1'b0;
          if (start) begin
            if (b == 32'sd0) begin
              y <= 32'sd65536;
              err <= 8'd0;
              ready <= 1'b1;
              state <= 6'd0;
            end else begin
              base <= a;
              if (b < 0) begin
                exp_remaining <= -b;
                exp_negative  <= 1'b1;
              end else begin
                exp_remaining <= b;
                exp_negative  <= 1'b0;
              end
              result <= 64'sd65536;
              state  <= 6'd1;
            end
          end
        end
        6'd1: begin
          if (exp_remaining <= 32'sd0) begin
            if (exp_negative) begin
              if (result[31:0] == 32'sd0) begin
                y   <= 32'sd0;
                err <= 8'd1;
              end else begin
                temp_result <= {32'sd65536, 16'd0} / result[31:0];
                state <= 6'd2;
              end
            end else begin
              y <= result[31:0];
              err <= 8'd0;
              ready <= 1'b1;
              state <= 6'd0;
            end
          end else begin
            result <= (result * base) >>> 16;
            exp_remaining <= exp_remaining - 32'sd65536;
          end
        end
        6'd2: begin
          y <= temp_result[31:0];
          err <= 8'd0;
          ready <= 1'b1;
          state <= 6'd0;
        end
        default: state <= 6'd0;
      endcase
    end
  end
endmodule

module cordic_q16 (
    input wire clk,
    rst,
    start,
    input wire signed [31:0] angle,
    output reg signed [31:0] cos_out,
    output reg signed [31:0] sin_out,
    output reg ready
);
  parameter width = 16;

  reg [5:0] state;
  reg [4:0] iteration;

  reg signed [31:0] atan_table[0:15];
  initial begin
    atan_table[00] = 32'sd51471;
    atan_table[01] = 32'sd30385;
    atan_table[02] = 32'sd16054;
    atan_table[03] = 32'sd8149;
    atan_table[04] = 32'sd4090;
    atan_table[05] = 32'sd2047;
    atan_table[06] = 32'sd1024;
    atan_table[07] = 32'sd512;
    atan_table[08] = 32'sd256;
    atan_table[09] = 32'sd128;
    atan_table[10] = 32'sd64;
    atan_table[11] = 32'sd32;
    atan_table[12] = 32'sd16;
    atan_table[13] = 32'sd8;
    atan_table[14] = 32'sd4;
    atan_table[15] = 32'sd2;
  end

  reg signed [31:0] x;
  reg signed [31:0] y;
  reg signed [31:0] z;
  reg signed [31:0] x_new;
  reg signed [31:0] y_new;
  reg signed [31:0] z_new;
  reg signed [31:0] angle_work;
  reg negate_cos;
  reg negate_sin;

  localparam signed [31:0] K = 32'sd39796;
  localparam signed [31:0] PI = 32'sd205887;
  localparam signed [31:0] TWO_PI = 32'sd411775;
  localparam signed [31:0] PI_HALF = 32'sd102944;
  localparam signed [31:0] CORDIC_MAX = 32'sd98304;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      cos_out <= 32'sd0;
      sin_out <= 32'sd0;
      ready <= 1'b0;
      state <= 6'd0;
      iteration <= 5'd0;
      x <= 32'sd0;
      y <= 32'sd0;
      z <= 32'sd0;
      angle_work <= 32'sd0;
      negate_cos <= 1'b0;
      negate_sin <= 1'b0;
      x_new <= 32'sd0;
      y_new <= 32'sd0;
      z_new <= 32'sd0;
    end else begin
      case (state)
        6'd0: begin
          ready <= 1'b0;
          if (start) begin
            angle_work <= angle;
            state <= 6'd1;
          end
        end

        6'd1: begin
          if (angle_work > PI) begin
            angle_work <= angle_work - TWO_PI;
          end else if (angle_work <= -PI) begin
            angle_work <= angle_work + TWO_PI;
          end else begin
            state <= 6'd10;
          end
        end

        6'd10: begin
          x <= K;
          y <= 32'sd0;

          if (angle_work > CORDIC_MAX) begin
            z <= PI - angle_work;
            negate_cos <= 1'b1;
            negate_sin <= 1'b0;
          end else if (angle_work < -CORDIC_MAX) begin
            z <= angle_work + PI;
            negate_cos <= 1'b1;
            negate_sin <= 1'b1;
          end else begin
            z <= angle_work;
            negate_cos <= 1'b0;
            negate_sin <= 1'b0;
          end

          iteration <= 5'd0;
          state <= 6'd2;
        end

        6'd2: begin
          if (iteration >= 5'd16) begin
            state <= 6'd3;
          end else begin
            if (z >= 32'sd0) begin
              x_new <= x - (y >>> iteration);
              y_new <= y + (x >>> iteration);
              z_new <= z - atan_table[iteration];
            end else begin
              x_new <= x + (y >>> iteration);
              y_new <= y - (x >>> iteration);
              z_new <= z + atan_table[iteration];
            end
            state <= 6'd4;
          end
        end

        6'd4: begin
          x <= x_new;
          y <= y_new;
          z <= z_new;
          iteration <= iteration + 5'd1;
          state <= 6'd2;
        end

        6'd3: begin
          cos_out <= negate_cos ? -x : x;
          sin_out <= negate_sin ? -y : y;
          ready   <= 1'b1;
          state   <= 6'd0;
        end

        default: state <= 6'd0;
      endcase
    end
  end
endmodule

module math_sin_q16 (
    input wire clk,
    rst,
    start,
    input wire signed [31:0] a,
    output reg signed [31:0] y,
    output reg ready,
    output reg [7:0] err
);
  reg [5:0] state;
  wire signed [31:0] cos_val;
  wire signed [31:0] sin_val;
  wire cordic_ready;
  reg cordic_start;
  reg signed [31:0] angle_reg;

  localparam signed [31:0] PI_HALF = 32'sd102944;  // π/2 in Q16.16

  cordic_q16 cordic_inst (
      .clk(clk),
      .rst(rst),
      .start(cordic_start),
      .angle(angle_reg),
      .cos_out(cos_val),
      .sin_out(sin_val),
      .ready(cordic_ready)
  );

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
      state <= 6'd0;
      cordic_start <= 1'b0;
      angle_reg <= 32'sd0;
    end else begin
      case (state)
        6'd0: begin
          cordic_start <= 1'b0;
          if (start && !ready) begin  // Only start if not already ready
            // sin(θ) = cos(π/2 - θ)
            angle_reg <= PI_HALF - a;
            cordic_start <= 1'b1;
            ready <= 1'b0;  // Clear ready flag
            state <= 6'd1;
          end else if (!start) begin
            ready <= 1'b0;  // Clear ready when start goes low
          end
        end
        6'd1: begin
          cordic_start <= 1'b0;
          state <= 6'd2;
        end
        6'd2: begin
          if (cordic_ready) begin
            // Use cosine output as sine result
            y <= cos_val;
            err <= 8'd0;
            ready <= 1'b1;
            state <= 6'd0;
          end
        end
        default: state <= 6'd0;
      endcase
    end
  end
endmodule

module math_cos_q16 (
    input wire clk,
    rst,
    start,
    input wire signed [31:0] a,
    output reg signed [31:0] y,
    output reg ready,
    output reg [7:0] err
);
  reg [5:0] state;
  wire signed [31:0] cos_val;
  wire signed [31:0] sin_val;
  wire cordic_ready;
  reg cordic_start;
  reg signed [31:0] angle_reg;

  cordic_q16 cordic_inst (
      .clk(clk),
      .rst(rst),
      .start(cordic_start),
      .angle(angle_reg),
      .cos_out(cos_val),
      .sin_out(sin_val),
      .ready(cordic_ready)
  );

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
      state <= 6'd0;
      cordic_start <= 1'b0;
      angle_reg <= 32'sd0;
    end else begin
      case (state)
        6'd0: begin
          ready <= 1'b0;
          cordic_start <= 1'b0;
          if (start) begin
            angle_reg <= a;
            cordic_start <= 1'b1;
            state <= 6'd1;
          end
        end
        6'd1: begin
          cordic_start <= 1'b0;
          state <= 6'd2;
        end
        6'd2: begin
          if (cordic_ready) begin
            y <= cos_val;
            err <= 8'd0;
            ready <= 1'b1;
            state <= 6'd0;
          end
        end
        default: state <= 6'd0;
      endcase
    end
  end
endmodule

module math_tan_q16 (
    input wire clk,
    rst,
    start,
    input wire signed [31:0] a,
    output reg signed [31:0] y,
    output reg ready,
    output reg [7:0] err
);
  reg [5:0] state;
  reg signed [31:0] sin_val;
  reg signed [31:0] cos_val;
  wire signed [31:0] cordic_sin;
  wire signed [31:0] cordic_cos;
  wire cordic_ready;
  reg cordic_start;
  reg signed [31:0] a_reg;
  wire signed [31:0] div_out;
  wire div_ready;
  wire [7:0] div_err;
  reg div_start;

  cordic_q16 cordic_inst (
      .clk(clk),
      .rst(rst),
      .start(cordic_start),
      .angle(a_reg),
      .cos_out(cordic_cos),
      .sin_out(cordic_sin),
      .ready(cordic_ready)
  );

  math_div_q16 div_inst (
      .clk(clk),
      .rst(rst),
      .start(div_start),
      .a(sin_val),
      .b(cos_val),
      .y(div_out),
      .ready(div_ready),
      .err(div_err)
  );

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
      state <= 6'd0;
      cordic_start <= 1'b0;
      div_start <= 1'b0;
      sin_val <= 32'sd0;
      cos_val <= 32'sd0;
      a_reg <= 32'sd0;
    end else begin
      case (state)
        6'd0: begin
          ready <= 1'b0;
          cordic_start <= 1'b0;
          div_start <= 1'b0;
          if (start) begin
            a_reg <= a;
            cordic_start <= 1'b1;
            state <= 6'd1;
          end
        end
        6'd1: begin
          cordic_start <= 1'b0;
          state <= 6'd2;
        end
        6'd2: begin
          if (cordic_ready) begin
            sin_val <= cordic_sin;
            cos_val <= cordic_cos;
            state   <= 6'd3;
          end
        end
        6'd3: begin
          // Check for near-zero cosine (avoid division by zero)
          // tan is undefined at ±π/2 where cos ≈ 0
          if (cos_val == 32'sd0 || (cos_val > -32'sd3277 && cos_val < 32'sd3277)) begin
            y <= 32'sd0;
            err <= 8'd1;
            ready <= 1'b1;
            state <= 6'd0;
          end else begin
            // Start division: tan = sin/cos
            // sin_val and cos_val are already set, so just start divider
            div_start <= 1'b1;
            state <= 6'd4;
          end
        end
        6'd4: begin
          div_start <= 1'b0;
          state <= 6'd5;
        end
        6'd5: begin
          if (div_ready) begin
            y <= div_out;
            err <= div_err;
            ready <= 1'b1;
            state <= 6'd0;
          end
        end
        default: state <= 6'd0;
      endcase
    end
  end
endmodule


module sqrt_q16_16 (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire signed [31:0] a,
    output reg signed  [31:0] y,
    output reg                ready,
    output reg         [ 7:0] err
);

  localparam ERR_NEG_INPUT = 8'h01;

  reg [ 2:0] st;
  reg [ 5:0] bit_pos;
  reg [31:0] result;
  reg [31:0] remainder;
  reg [31:0] test_bit;
  reg [31:0] radicand;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      st        <= 3'd0;
      bit_pos   <= 6'd0;
      result    <= 32'd0;
      remainder <= 32'd0;
      test_bit  <= 32'd0;
      radicand  <= 32'd0;
      y         <= 32'sd0;
      ready     <= 1'b0;
      err       <= 8'd0;
    end else begin
      case (st)
        3'd0: begin
          ready <= 1'b0;
          if (start) begin
            if (a < 0) begin
              y     <= 32'sd0;
              ready <= 1'b1;
              err   <= ERR_NEG_INPUT;
              st    <= 3'd0;
            end else if (a == 0) begin
              y     <= 32'sd0;
              ready <= 1'b1;
              err   <= 8'd0;
              st    <= 3'd0;
            end else begin
              radicand  <= a;
              result    <= 32'd0;
              remainder <= 32'd0;
              bit_pos   <= 6'd30;
              st        <= 3'd1;
            end
          end
        end

        3'd1: begin
          remainder <= (remainder << 2) | ((radicand >> bit_pos) & 2'b11);
          test_bit  <= (result << 2) | 32'd1;
          st        <= 3'd2;
        end

        3'd2: begin
          if (remainder >= test_bit) begin
            remainder <= remainder - test_bit;
            result    <= (result << 1) | 32'd1;
          end else begin
            result <= result << 1;
          end

          if (bit_pos == 6'd0) begin
            st <= 3'd3;
          end else begin
            bit_pos <= bit_pos - 6'd2;
            st      <= 3'd1;
          end
        end

        3'd3: begin
          y     <= result << 8;
          ready <= 1'b1;
          err   <= 8'd0;
          st    <= 3'd0;
        end

        default: st <= 3'd0;
      endcase
    end
  end

endmodule


module math_ln_q16 (
    input wire clk,
    rst,
    start,
    input wire signed [31:0] a,
    output reg signed [31:0] y,
    output reg ready,
    output reg [7:0] err
);
  reg [5:0] state;
  reg signed [31:0] x;
  reg signed [31:0] result;
  reg signed [63:0] power;
  reg signed [31:0] term;
  reg signed [31:0] x_minus_1;
  reg [5:0] n;
  reg [4:0] scale_count;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
      state <= 6'd0;
      x <= 32'sd0;
      result <= 32'sd0;
      power <= 64'sd0;
      term <= 32'sd0;
      x_minus_1 <= 32'sd0;
      n <= 6'd0;
      scale_count <= 5'd0;
    end else begin
      case (state)
        6'd0: begin
          ready <= 1'b0;
          if (start) begin
            if (a <= 32'sd0) begin
              y <= 32'sd0;
              err <= 8'd1;
              ready <= 1'b1;
              state <= 6'd0;
            end else begin
              x <= a;
              result <= 32'sd0;
              scale_count <= 5'd0;
              state <= 6'd1;
            end
          end
        end
        6'd1: begin
          if (x < 32'sd32768) begin
            x <= x << 1;
            result <= result - 32'sd45426;
            scale_count <= scale_count + 5'd1;
            if (scale_count >= 5'd10) begin
              state <= 6'd2;
            end
          end else if (x > 32'sd131072) begin
            x <= x >> 1;
            result <= result + 32'sd45426;
            scale_count <= scale_count + 5'd1;
            if (scale_count >= 5'd10) begin
              state <= 6'd2;
            end
          end else begin
            state <= 6'd2;
          end
        end
        6'd2: begin
          x_minus_1 <= x - 32'sd65536;
          power <= {(x - 32'sd65536), 16'd0};
          n <= 6'd1;
          state <= 6'd3;
        end
        6'd3: begin
          if (n >= 6'd16) begin
            y <= result;
            err <= 8'd0;
            ready <= 1'b1;
            state <= 6'd0;
          end else begin
            term  <= power[47:16] / $signed({26'd0, n});
            state <= 6'd4;
          end
        end
        6'd4: begin
          if (n[0] == 1'b1) begin
            result <= result + term;
          end else begin
            result <= result - term;
          end
          power <= (power[47:16] * x_minus_1);
          n <= n + 6'd1;
          state <= 6'd3;
        end
        default: state <= 6'd0;
      endcase
    end
  end
endmodule

module math_log_q16 (
    input wire clk,
    rst,
    start,
    input wire signed [31:0] a,
    output reg signed [31:0] y,
    output reg ready,
    output reg [7:0] err
);
  reg [5:0] state;
  wire signed [31:0] ln_out;
  wire ln_ready;
  wire [7:0] ln_err;
  reg ln_start;
  reg signed [31:0] a_reg;
  reg signed [63:0] temp_result;

  localparam signed [31:0] LN10_INV = 32'sd28394;

  math_ln_q16 ln_inst (
      .clk(clk),
      .rst(rst),
      .start(ln_start),
      .a(a_reg),
      .y(ln_out),
      .ready(ln_ready),
      .err(ln_err)
  );

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
      state <= 6'd0;
      ln_start <= 1'b0;
      a_reg <= 32'sd0;
      temp_result <= 64'sd0;
    end else begin
      case (state)
        6'd0: begin
          ready <= 1'b0;
          ln_start <= 1'b0;
          if (start) begin
            a_reg <= a;
            ln_start <= 1'b1;
            state <= 6'd1;
          end
        end
        6'd1: begin
          ln_start <= 1'b0;
          state <= 6'd2;
        end
        6'd2: begin
          if (ln_ready) begin
            if (ln_err != 8'd0) begin
              y <= 32'sd0;
              err <= ln_err;
              ready <= 1'b1;
              state <= 6'd0;
            end else begin
              temp_result <= ln_out * LN10_INV;
              state <= 6'd3;
            end
          end
        end
        6'd3: begin
          y <= temp_result[47:16];
          err <= 8'd0;
          ready <= 1'b1;
          state <= 6'd0;
        end
        default: state <= 6'd0;
      endcase
    end
  end
endmodule
