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
    input  wire               rst,
    input  wire               start,
    input  wire signed [31:0] a,      // Q16.16
    output reg signed  [31:0] y,      // Q16.16
    output reg                ready,
    output reg         [ 7:0] err
);
  wire signed [31:0] base = {a[31:16], 16'h0000};

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y    <= base;
        err  <= 8'd0;
        ready<= 1'b1;
      end
    end
  end
endmodule

module math_ceil_q16 (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire signed [31:0] a,      // Q16.16
    output reg signed  [31:0] y,      // Q16.16
    output reg                ready,
    output reg         [ 7:0] err
);
  localparam signed [31:0] Q16_MAX = 32'sh7FFF_FFFF;

  wire signed [31:0] base = {a[31:16], 16'h0000};  // floor(a)
  wire               frac_nz = |a[15:0];
  wire               will_ov = (!a[31]) && frac_nz && (base == 32'sh7FFF_0000);

  wire signed [31:0] ceil_val = will_ov ? Q16_MAX : (base + (frac_nz ? 32'sh0001_0000 : 32'sh0));

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y    <= ceil_val;
        err  <= will_ov ? 8'h20 : 8'd0;
        ready<= 1'b1;
      end
    end
  end
endmodule

module math_round_q16 (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire signed [31:0] a,      // Q16.16
    output reg signed  [31:0] y,      // Q16.16
    output reg                ready,
    output reg         [ 7:0] err
);
  localparam signed [31:0] Q16_MAX = 32'sh7FFF_FFFF;
  localparam signed [31:0] Q16_MIN = 32'sh8000_0000;
  localparam signed [31:0] HALF = 32'sh0000_8000;  // +0.5 in Q16.16

  // Bias away from zero
  wire signed [31:0] bias = a[31] ? -HALF : HALF;

  // 32-bit signed add and overflow detection (same-sign add flips sign)
  wire signed [31:0] sum = a + bias;
  wire ov_add = ((a[31] == bias[31]) && (sum[31] != a[31]));

  // Truncate toward zero
  wire frac_nz = |sum[15:0];
  wire signed [31:0] base = {sum[31:16], 16'h0000};  // floor(sum)
  wire signed [31:0] trunc0 = (sum[31] && frac_nz) ? (base + 32'sh0001_0000)  // bump toward 0
  : base;

  // Saturate only on true overflow
  wire signed [31:0] y_next = ov_add ? (a[31] ? Q16_MIN : Q16_MAX) : trunc0;
  wire [7:0] e_next = ov_add ? 8'h20 : 8'd0;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y    <= y_next;
        err  <= e_next;
        ready<= 1'b1;
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
    input  wire               clk,
    input  wire               rst,        // synchronous, active-high
    input  wire               start,      // 1-cycle pulse when idle
    input  wire signed [31:0] a,          // Q16.16
    input  wire signed [31:0] b,          // Q16.16
    output reg signed  [31:0] y,          // Q16.16
    output reg signed  [31:0] remainder,
    output reg                ready,      // 1-cycle pulse
    output reg         [ 7:0] err
);

  // ---- Error bits ----
  localparam [7:0] ERR_DIV0 = 8'h01;
  localparam [7:0] ERR_OVF = 8'h02;

  // ---- Saturation constants ----
  // Q16.16 max/min representable values
  localparam signed [31:0] Q16_MAX = 32'sh7FFF_FFFF;  // +32767.9999847...
  localparam signed [31:0] Q16_MIN = 32'sh8000_0000;  // -32768.0

  // ---- Internal state ----
  reg         running;
  reg  [ 5:0] cnt;  // counts 48..1
  reg         sign_q;  // sign of result = a[31] ^ b[31]

  reg  [47:0] dividend;  // |a| << 16 (to keep Q16.16)
  reg  [31:0] divisor;  // |b|
  reg  [32:0] rem;  // remainder (33 bits for compare/sub)
  reg  [47:0] quo;  // 48-bit quotient accumulator

  // Next-state temporaries (declared at module scope for Verilog-2001)
  reg  [32:0] rem_n;
  reg  [47:0] quo_n;
  reg  [47:0] dividend_n;

  wire [31:0] abs_a = a[31] ? (~a + 32'sd1) : a;
  wire [31:0] abs_b = b[31] ? (~b + 32'sd1) : b;

  always @(posedge clk) begin
    if (rst) begin
      running   <= 1'b0;
      cnt       <= 6'd0;
      sign_q    <= 1'b0;
      dividend  <= 48'd0;
      divisor   <= 32'd0;
      rem       <= 33'd0;
      quo       <= 48'd0;
      y         <= 32'sd0;
      ready     <= 1'b0;
      err       <= 8'd0;
      remainder <= 0;
    end else begin
      // default outputs each cycle
      ready <= 1'b0;

      // Start a new division when idle
      if (start && !running) begin
        err    <= 8'd0;
        sign_q <= a[31] ^ b[31];

        if (b == 32'sd0) begin
          // Divide-by-zero: saturate toward +/- infinity based on 'a' sign
          y       <= a[31] ? Q16_MIN : Q16_MAX;
          err     <= ERR_DIV0;
          ready   <= 1'b1;  // immediate result
          running <= 1'b0;
        end else begin
          dividend <= {abs_a, 16'h0000};  // shift to align Q16.16
          divisor  <= abs_b;
          rem      <= 33'd0;
          quo      <= 48'd0;
          cnt      <= 6'd48;
          running  <= 1'b1;
        end
      end  // Iterative restoring division (1 bit per cycle)
      else if (running) begin
        // Build next-state using current registers
        rem_n      = {rem[31:0], dividend[47]};  // shift-in next bit
        dividend_n = {dividend[46:0], 1'b0};  // shift left
        // provisional shift of quotient; set LSB if subtraction succeeds
        if (rem_n >= {1'b0, divisor}) begin
          rem_n = rem_n - {1'b0, divisor};
          quo_n = {quo[46:0], 1'b1};
        end else begin
          quo_n = {quo[46:0], 1'b0};
        end

        // Register next-state
        rem      <= rem_n;
        dividend <= dividend_n;
        quo      <= quo_n;

        // Countdown
        if (cnt != 0) cnt <= cnt - 6'd1;

        // Finish when last bit is resolved
        if (cnt == 6'd1) begin
          running <= 1'b0;

          // Detect overflow: upper 16 bits of 48-bit quotient are non-zero
          if (|quo_n[47:32]) begin
            y   <= (sign_q ? Q16_MIN : Q16_MAX);
            err <= err | ERR_OVF;
          end else begin
            // Apply sign to 32-bit result
            if (sign_q) y <= -$signed(quo_n[31:0]);
            else y <= $signed(quo_n[31:0]);
            remainder <= $signed(rem[31:0]);
          end

          ready <= 1'b1;  // 1-cycle pulse
        end
      end
    end
  end
endmodule

module math_pow_q16 (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire signed [31:0] a,      // Q16.16 base
    input  wire signed [31:0] b,      // Q16.16 exponent
    output reg signed  [31:0] y,      // Q16.16
    output reg                ready,
    output reg         [ 7:0] err
);
  // constants
  reg signed [31:0] Q_ZERO, Q_ONE, Q_NEGONE;
  initial begin
    Q_ZERO   = 32'sh0000_0000;
    Q_ONE    = 32'sh0001_0000;
    Q_NEGONE = 32'shFFFF_0000;
  end

  // states
  reg [2:0]
      S_IDLE, S_CHECK, S_LN_START, S_LN_WAIT, S_MUL_1, S_MUL_2, S_EXP_START, S_EXP_WAIT, S_DONE;
  initial begin
    S_IDLE = 3'd0;
    S_CHECK = 3'd1;
    S_LN_START = 3'd2;
    S_LN_WAIT = 3'd3;
    S_MUL_1 = 3'd4;
    S_MUL_2 = 3'd5;
    S_EXP_START = 3'd6;
    S_EXP_WAIT = 3'd7;
    S_DONE = 3'd0;
  end
  reg [2:0] state;

  // datapath
  reg signed [31:0] a_abs;
  reg a_is_neg, b_is_int, b_is_odd, neg_result;

  // ln
  reg                ln_start;
  reg signed  [31:0] ln_in_q;
  wire signed [31:0] ln_out_q;
  wire               ln_ready;
  wire        [ 7:0] ln_err;
  reg signed  [31:0] ln_result;

  // exp
  reg                exp_start;
  reg signed  [31:0] exp_in_q;
  wire signed [31:0] exp_out_q;
  wire               exp_ready;
  wire        [ 7:0] exp_err;

  // b*ln(|a|)
  reg signed  [63:0] mul64;
  reg signed  [31:0] bln_q16;
  reg signed [63:0] ROUND16_POS, ROUND16_NEG;

  reg [7:0] err_acc;

  initial begin
    ROUND16_POS = 64'sh0000_0000_0000_8000;  // +0.5 ulp for >>>16 rounding
    ROUND16_NEG = -64'sh0000_0000_0000_8000;
  end

  math_ln_q16 u_ln (
      .clk(clk),
      .rst(rst),
      .start(ln_start),
      .a(ln_in_q),
      .y(ln_out_q),
      .ready(ln_ready),
      .err(ln_err)
  );

  math_exp_q16 u_exp (
      .clk(clk),
      .rst(rst),
      .start(exp_start),
      .a(exp_in_q),
      .y(exp_out_q),
      .ready(exp_ready),
      .err(exp_err)
  );

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_IDLE;
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
      a_abs <= 32'sd0;
      a_is_neg <= 1'b0;
      b_is_int <= 1'b0;
      b_is_odd <= 1'b0;
      neg_result <= 1'b0;
      ln_start <= 1'b0;
      ln_in_q <= 32'sd0;
      ln_result <= 32'sd0;
      exp_start <= 1'b0;
      exp_in_q <= 32'sd0;
      mul64 <= 64'sd0;
      bln_q16 <= 32'sd0;
      err_acc <= 8'd0;
    end else begin
      ready <= 1'b0;
      ln_start <= 1'b0;
      exp_start <= 1'b0;

      case (state)
        S_IDLE:
        if (start) begin
          err_acc <= 8'd0;
          y <= 32'sd0;
          state <= S_CHECK;
        end

        S_CHECK: begin
          a_is_neg   <= a[31];
          a_abs      <= (a[31] ? -a : a);
          b_is_int   <= (b[15:0] == 16'h0000);
          b_is_odd   <= (b[15:0] == 16'h0000) && b[16];
          neg_result <= a[31] && (b[15:0] == 16'h0000) && b[16];

          if (a == Q_ZERO && (b == Q_ZERO || b[31])) begin
            y <= 32'sd0;
            err <= 8'b0000_0001;
            ready <= 1'b1;
            state <= S_IDLE;
          end else if (a == Q_ZERO && !b[31] && b != Q_ZERO) begin
            y <= 32'sd0;
            err <= 8'd0;
            ready <= 1'b1;
            state <= S_IDLE;
          end else if (b == Q_ONE - Q_ZERO) begin
            y <= Q_ONE;
            err <= 8'd0;
            ready <= 1'b1;
            state <= S_IDLE;
          end else if (a == Q_ONE) begin
            y <= Q_ONE;
            err <= 8'd0;
            ready <= 1'b1;
            state <= S_IDLE;
          end else if (a == Q_NEGONE && b_is_int) begin
            y <= (b_is_odd ? Q_NEGONE : Q_ONE);
            err <= 8'd0;
            ready <= 1'b1;
            state <= S_IDLE;
          end else if (a[31] && !b_is_int) begin
            y <= 32'sd0;
            err <= 8'b0000_0001;
            ready <= 1'b1;
            state <= S_IDLE;
          end else begin
            ln_in_q  <= (a[31] ? -a : a);
            ln_start <= 1'b1;
            state    <= S_LN_START;
          end
        end

        S_LN_START: state <= S_LN_WAIT;

        S_LN_WAIT:
        if (ln_ready) begin
          ln_result <= ln_out_q;
          if (ln_err != 8'd0) err_acc <= err_acc | 8'b0000_1000 | (ln_err & 8'b0000_0111);
          state <= S_MUL_1;
        end

        // b * ln(|a|)
        S_MUL_1: begin
          mul64 <= $signed(b) * $signed(ln_result);  // Q32.32
          state <= S_MUL_2;
        end
        S_MUL_2: begin
          bln_q16   <= $signed((mul64 + (mul64[63] ? ROUND16_NEG : ROUND16_POS)) >>> 16);
          exp_in_q  <= $signed((mul64 + (mul64[63] ? ROUND16_NEG : ROUND16_POS)) >>> 16);
          exp_start <= 1'b1;
          state     <= S_EXP_START;
        end

        S_EXP_START: state <= S_EXP_WAIT;

        S_EXP_WAIT:
        if (exp_ready) begin
          if (exp_err != 8'd0) err_acc <= err_acc | 8'b0000_1000 | (exp_err & 8'b0000_0111);
          y <= (neg_result ? -exp_out_q : exp_out_q);
          err   <= (err_acc |
                    (exp_err[1] ? 8'b0000_0010 : 8'b0000_0000) |
                    (exp_err[2] ? 8'b0000_0100 : 8'b0000_0000));
          ready <= 1'b1;
          state <= S_DONE;
        end

        S_DONE:  state <= S_IDLE;
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule


// Q16.16 exponential: y = exp(x)
// Handshake: start (pulse) -> ready (1-cycle)
// Error flags:
//   [1] OVERFLOW   saturated to +MAX
//   [2] UNDERFLOW  flushed to 0
//   [3] INEXACT    rounding/reduction produced discarded bits (approximation)
//   [7:4],[0] reserved
// Q16.16 exponential: y = exp(a)
// Fix: every multiply has a MUL state (compute) and an ACC state (consume).
// ==============================
// Q16.16 exponential: y = exp(a)
// - Every multiply has MUL/ACC phases (no read-after-write hazards).
// - k/f split into two states so f uses the updated k.
// - Pure Verilog-2001: no localparam, no declarations inside always.
// ==============================
module math_exp_q16 (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire signed [31:0] a,      // x in Q16.16
    output reg signed  [31:0] y,      // exp(x) in Q16.16
    output reg                ready,
    output reg         [ 7:0] err
);
  // constants
  reg signed [31:0] Q_ZERO, Q_ONE, Q_MAX, Q_MIN, LN2_Q16, INV_LN2_Q16, HALF_Q16;
  reg signed [31:0] C5, C4, C3, C2;
  reg signed [63:0] QMAX_64, QMIN_64;
  reg signed [63:0] ROUND16_POS, ROUND16_NEG;
  initial begin
    Q_ZERO      = 32'sh0000_0000;
    Q_ONE       = 32'sh0001_0000;
    Q_MAX       = 32'sh7FFF_FFFF;
    Q_MIN       = 32'sh8000_0000;
    HALF_Q16    = 32'sh0000_8000;
    LN2_Q16     = 32'sh0000_B172;  // ln 2
    INV_LN2_Q16 = 32'sh0001_7154;  // 1/ln 2
    C5          = 32'sh0000_0222;  // 1/120
    C4          = 32'sh0000_0AAA;  // 1/24
    C3          = 32'sh0000_2AAA;  // 1/6
    C2          = 32'sh0000_8000;  // 1/2
    QMAX_64     = 64'sh0000_0000_7FFF_FFFF;
    QMIN_64     = 64'shFFFF_FFFF_8000_0000;
    ROUND16_POS = 64'sh0000_0000_0000_8000;  // +0.5 ulp for >>>16
    ROUND16_NEG = -64'sh0000_0000_0000_8000;
  end

  // states
  reg [4:0]
      S_IDLE,
      S_Y_MUL,
      S_Y_ACC,
      S_K_MAKE,
      S_F_MAKE,
      S_R_MUL,
      S_R_ACC,
      S_H0_MUL,
      S_H0_ACC,
      S_H1_MUL,
      S_H1_ACC,
      S_H2_MUL,
      S_H2_ACC,
      S_H3_MUL,
      S_H3_ACC,
      S_H4_MUL,
      S_H4_ACC,
      S_SCALE,
      S_DONE;
  initial begin
    S_IDLE   = 5'd0;
    S_Y_MUL  = 5'd1;
    S_Y_ACC  = 5'd2;
    S_K_MAKE = 5'd3;
    S_F_MAKE = 5'd4;
    S_R_MUL  = 5'd5;
    S_R_ACC  = 5'd6;
    S_H0_MUL = 5'd7;
    S_H0_ACC = 5'd8;
    S_H1_MUL = 5'd9;
    S_H1_ACC = 5'd10;
    S_H2_MUL = 5'd11;
    S_H2_ACC = 5'd12;
    S_H3_MUL = 5'd13;
    S_H3_ACC = 5'd14;
    S_H4_MUL = 5'd15;
    S_H4_ACC = 5'd16;
    S_SCALE  = 5'd17;
    S_DONE   = 5'd18;
  end
  reg [4:0] state, state_n;

  // datapath
  reg signed [31:0] x_q, y_q16, y_bias, f_q16, r_q16, t_q16;
  reg signed [15:0] k_int;
  reg signed [63:0] prod64;
  reg overflow, underflow, inexact;

  // next-state
  always @* begin
    state_n = state;
    case (state)
      S_IDLE:   if (start) state_n = S_Y_MUL;
      S_Y_MUL:  state_n = S_Y_ACC;
      S_Y_ACC:  state_n = S_K_MAKE;
      S_K_MAKE: state_n = S_F_MAKE;
      S_F_MAKE: state_n = S_R_MUL;
      S_R_MUL:  state_n = S_R_ACC;
      S_R_ACC:  state_n = S_H0_MUL;
      S_H0_MUL: state_n = S_H0_ACC;
      S_H0_ACC: state_n = S_H1_MUL;
      S_H1_MUL: state_n = S_H1_ACC;
      S_H1_ACC: state_n = S_H2_MUL;
      S_H2_MUL: state_n = S_H2_ACC;
      S_H2_ACC: state_n = S_H3_MUL;
      S_H3_MUL: state_n = S_H3_ACC;
      S_H3_ACC: state_n = S_H4_MUL;
      S_H4_MUL: state_n = S_H4_ACC;
      S_H4_ACC: state_n = S_SCALE;
      S_SCALE:  state_n = S_DONE;
      S_DONE:   state_n = S_IDLE;
      default:  state_n = S_IDLE;
    endcase
  end

  // sequential
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_IDLE;
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
      x_q <= 32'sd0;
      y_q16 <= 32'sd0;
      y_bias <= 32'sd0;
      f_q16 <= 32'sd0;
      r_q16 <= 32'sd0;
      t_q16 <= 32'sd0;
      k_int <= 16'sd0;
      prod64 <= 64'sd0;
      overflow <= 1'b0;
      underflow <= 1'b0;
      inexact <= 1'b0;
    end else begin
      state <= state_n;
      ready <= 1'b0;

      case (state)
        S_IDLE:
        if (start) begin
          x_q <= a;
          err <= 8'd0;
          overflow <= 1'b0;
          underflow <= 1'b0;
          inexact <= 1'b0;
        end

        // y = a * inv_ln2  (rounded)
        S_Y_MUL: prod64 <= $signed(x_q) * $signed(INV_LN2_Q16);
        S_Y_ACC: y_q16 <= $signed((prod64 + (prod64[63] ? ROUND16_NEG : ROUND16_POS)) >>> 16);

        // k = round(y)
        S_K_MAKE: begin
          y_bias <= (y_q16[31] ? -HALF_Q16 : HALF_Q16);
          k_int  <= $signed((y_q16 + y_bias) >>> 16);
        end

        // f = y - k
        S_F_MAKE: begin
          f_q16 <= y_q16 - ({{16{k_int[15]}}, k_int} <<< 16);
          if (f_q16 != 32'sd0) inexact <= 1'b1;
        end

        // r = f * ln2  (rounded)
        S_R_MUL: prod64 <= $signed(f_q16) * $signed(LN2_Q16);
        S_R_ACC: r_q16 <= $signed((prod64 + (prod64[63] ? ROUND16_NEG : ROUND16_POS)) >>> 16);

        // Horner (every >>>16 rounded)
        S_H0_MUL: prod64 <= $signed(C5) * $signed(r_q16);
        S_H0_ACC: t_q16 <= $signed((prod64 + (prod64[63] ? ROUND16_NEG : ROUND16_POS)) >>> 16) + C4;

        S_H1_MUL: prod64 <= $signed(t_q16) * $signed(r_q16);
        S_H1_ACC: t_q16 <= $signed((prod64 + (prod64[63] ? ROUND16_NEG : ROUND16_POS)) >>> 16) + C3;

        S_H2_MUL: prod64 <= $signed(t_q16) * $signed(r_q16);
        S_H2_ACC: t_q16 <= $signed((prod64 + (prod64[63] ? ROUND16_NEG : ROUND16_POS)) >>> 16) + C2;

        S_H3_MUL: prod64 <= $signed(t_q16) * $signed(r_q16);
        S_H3_ACC:
        t_q16 <= $signed((prod64 + (prod64[63] ? ROUND16_NEG : ROUND16_POS)) >>> 16) + Q_ONE;

        S_H4_MUL: prod64 <= $signed(t_q16) * $signed(r_q16);
        S_H4_ACC:
        t_q16 <= $signed((prod64 + (prod64[63] ? ROUND16_NEG : ROUND16_POS)) >>> 16) + Q_ONE;

        // scale by 2^k (same as before)
        S_SCALE: begin
          if (k_int >= 0) begin
            if (k_int >= 15) begin
              y <= Q_MAX;
              overflow <= 1'b1;
            end else begin
              prod64 = $signed({{32{t_q16[31]}}, t_q16}) <<< k_int;
              if (prod64 > QMAX_64) begin
                y <= Q_MAX;
                overflow <= 1'b1;
              end else begin
                y <= prod64[31:0];
              end
            end
          end else begin
            if (k_int <= -31) begin
              y <= Q_ZERO;
              if (t_q16 != 32'sd0) underflow <= 1'b1;
            end else begin
              y <= $signed(t_q16) >>> (-k_int);
              if (y == Q_ZERO && t_q16 != 32'sd0) underflow <= 1'b1;
            end
          end
        end

        S_DONE: begin
          err[1]   <= overflow;
          err[2]   <= underflow;
          err[3]   <= inexact;
          err[7:4] <= 4'b0000;
          err[0]   <= 1'b0;
          ready    <= 1'b1;
        end
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
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire signed [31:0] a,      // Q16.16, must be > 0
    output reg signed  [31:0] y,      // ln(a) in Q16.16
    output reg                ready,
    output reg         [ 7:0] err
);
  // ---- constants (Q16.16) ----
  reg signed [31:0] Q_ONE, Q_TWO, Q_ZERO, Q_MAX, Q_MIN, LN2_Q16;
  initial begin
    Q_ONE   = 32'sh0001_0000;  // 1.0
    Q_TWO   = 32'sh0002_0000;  // 2.0
    Q_ZERO  = 32'sd0;
    Q_MAX   = 32'sh7FFF_FFFF;
    Q_MIN   = 32'sh8000_0000;
    LN2_Q16 = 32'sh0000_B172;  // ln(2) ? 0.693147
  end

  // ---- state enc ----
  reg [2:0] S_IDLE, S_CHECK, S_NORM, S_PREP, S_ITER, S_FIN1, S_FIN2, S_DONE;
  initial begin
    S_IDLE  = 3'd0;
    S_CHECK = 3'd1;
    S_NORM  = 3'd2;
    S_PREP  = 3'd3;
    S_ITER  = 3'd4;
    S_FIN1  = 3'd5;
    S_FIN2  = 3'd6;
    S_DONE  = 3'd7;
  end
  reg [2:0] state, state_n;

  // ---- datapath regs ----
  reg signed [31:0] a_mag, m;
  reg signed [7:0] k;  // a = m*2^k

  // CORDIC state
  reg signed [31:0] x, yv, z;
  reg [5:0] i;
  reg       rep_do;

  // flags
  reg inexact, underflow, overflow;

  // helpers / temps (module-scope)
  wire signed [31:0] x_shift = $signed(x) >>> i;
  wire signed [31:0] y_shift = $signed(yv) >>> i;
  wire               need_repeat = (i == 6'd4) || (i == 6'd13);

  // 64-bit final accumulator terms
  reg signed  [63:0] term_twoz;  // 2*z in 64-bit
  reg signed  [63:0] term_kln2;  // k*ln(2) in 64-bit
  reg signed  [63:0] sum64;  // final 64-bit sum before saturation

  // for saturation compare
  reg signed [63:0] QMAX_64, QMIN_64;
  initial begin
    QMAX_64 = 64'sh0000_0000_7FFF_FFFF;
    QMIN_64 = 64'shFFFF_FFFF_8000_0000;
  end

  // atanh table as function
  function [31:0] atanh_q16;
    input [5:0] idx;
    begin
      case (idx)
        6'd1: atanh_q16 = 32'sh00008C9F;  // 0.5493061443
        6'd2: atanh_q16 = 32'sh00004163;  // 0.2554128119
        6'd3: atanh_q16 = 32'sh0000202B;  // 0.1256572141
        6'd4: atanh_q16 = 32'sh00001005;  // 0.0625815715
        6'd5: atanh_q16 = 32'sh00000801;  // 0.0312601785
        6'd6: atanh_q16 = 32'sh00000400;  // 0.0156262718
        6'd7: atanh_q16 = 32'sh00000200;  // 0.0078126589
        6'd8: atanh_q16 = 32'sh00000100;
        6'd9: atanh_q16 = 32'sh00000080;
        6'd10: atanh_q16 = 32'sh00000040;
        6'd11: atanh_q16 = 32'sh00000020;
        6'd12: atanh_q16 = 32'sh00000010;
        6'd13: atanh_q16 = 32'sh00000008;
        6'd14: atanh_q16 = 32'sh00000004;
        6'd15: atanh_q16 = 32'sh00000002;
        6'd16: atanh_q16 = 32'sh00000001;
        6'd17: atanh_q16 = 32'sh00000001;
        default: atanh_q16 = 32'sh00000000;
      endcase
    end
  endfunction

  // ---- sequential ----
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= S_IDLE;
      ready <= 1'b0;
      err <= 8'd0;
      y <= 32'sd0;

      a_mag <= 32'sd0;
      m <= 32'sd0;
      k <= 8'sd0;
      x <= 32'sd0;
      yv <= 32'sd0;
      z <= 32'sd0;
      i <= 6'd0;
      rep_do <= 1'b0;

      inexact <= 1'b0;
      underflow <= 1'b0;
      overflow <= 1'b0;

      term_twoz <= 64'sd0;
      term_kln2 <= 64'sd0;
      sum64 <= 64'sd0;

    end else begin
      state <= state_n;
      ready <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            err       <= 8'd0;
            inexact   <= 1'b0;
            underflow <= 1'b0;
            overflow  <= 1'b0;
            a_mag     <= a;
          end
        end

        S_CHECK: begin
          if (a_mag <= Q_ZERO) begin
            y     <= 32'sd0;
            err   <= 8'b0000_0001;  // DOMAIN
            ready <= 1'b1;
          end else begin
            m <= a_mag;
            k <= 8'sd0;  // start normalization
          end
        end

        // normalize m into [1,2), tracking k
        S_NORM: begin
          if (m >= Q_TWO) begin
            m <= m >>> 1;
            k <= k + 8'sd1;
          end else if (m < Q_ONE) begin
            m <= m <<< 1;
            k <= k - 8'sd1;
          end
        end

        S_PREP: begin
          x       <= m + Q_ONE;  // x0 = m+1
          yv      <= m - Q_ONE;  // y0 = m-1
          z       <= 32'sd0;
          i       <= 6'd1;
          rep_do  <= 1'b0;
          inexact <= 1'b0;
        end

        // Hyperbolic CORDIC vectoring, repeats at i=4,13
        S_ITER: begin
          if (yv >= 0) begin
            // d = -1
            x  <= x - y_shift;
            yv <= yv - x_shift;
            z  <= z + atanh_q16(i);  // z <- z - d*atanh = z + atanh
          end else begin
            // d = +1
            x  <= x + y_shift;
            yv <= yv + x_shift;
            z  <= z - atanh_q16(i);
          end

          if ((i == 6'd24) && (yv != 32'sd0)) inexact <= 1'b1;

          if (need_repeat && !rep_do) begin
            rep_do <= 1'b1;  // repeat this i once
          end else begin
            rep_do <= 1'b0;
            i      <= i + 6'd1;
          end
        end

        // FIX: Split final computation into two cycles
        // Cycle 1: Compute terms
        S_FIN1: begin
          // term_twoz = 2*z (Q16.16 << 1), sign-extended to 64b
          term_twoz <= {{32{z[31]}}, z} <<< 1;

          // term_kln2 = k * LN2_Q16 (signed 8-bit * Q16.16 -> Q16.16 in 64-bit)
          term_kln2 <= $signed({{56{k[7]}}, k}) * $signed({{32{LN2_Q16[31]}}, LN2_Q16});
        end

        // Cycle 2: Sum the terms
        S_FIN2: begin
          sum64 <= term_twoz + term_kln2;
        end

        S_DONE: begin
          // Saturate sum64 to 32-bit Q16.16
          if (sum64 > QMAX_64) begin
            y        <= Q_MAX;
            overflow <= 1'b1;
          end else if (sum64 < QMIN_64) begin
            y        <= Q_MIN;
            overflow <= 1'b1;
          end else begin
            y <= sum64[31:0];
            if ((sum64[31:0] == 32'sd0) && (a_mag != Q_ONE)) underflow <= 1'b1;
          end

          err[1]   <= overflow;
          err[2]   <= underflow;
          // err[3]   <= inexact;
          err[7:3] <= 5'b00000;
          ready    <= 1'b1;
        end
      endcase
    end
  end

  // ---- next-state ----
  always @* begin
    state_n = state;
    case (state)
      S_IDLE:  if (start) state_n = S_CHECK;
      S_CHECK: if (a_mag <= Q_ZERO) state_n = S_DONE;
 else state_n = S_NORM;
      S_NORM:  if ((m >= Q_ONE) && (m < Q_TWO)) state_n = S_PREP;
 else state_n = S_NORM;
      S_PREP:  state_n = S_ITER;
      S_ITER:  if (i > 6'd24) state_n = S_FIN1;
 else state_n = S_ITER;
      S_FIN1:  state_n = S_FIN2;
      S_FIN2:  state_n = S_DONE;
      S_DONE:  state_n = S_IDLE;
      default: state_n = S_IDLE;
    endcase
  end

endmodule

module math_log_q16 (
    input  wire               clk,
    input  wire               rst,    // synchronous, active-high
    input  wire               start,  // 1-cycle pulse when idle
    input  wire signed [31:0] a,      // Q16.16, must be > 0
    output reg signed  [31:0] y,      // log10(x) in Q16.16
    output wire               ready,  // 1-cycle pulse on completion
    output wire               err     // sticky (1=any error since last start)
);

  // ln(10) in Q16.16
  localparam signed [31:0] LN10_Q16 = 32'sh0002_4D76;  // 2.302585...

  // FSM
  localparam [2:0] S_IDLE   = 3'd0,
                   S_RUNLN  = 3'd1,
                   S_WAITLN = 3'd2,
                   S_RUNDIV = 3'd3,
                   S_WAITDV = 3'd4,
                   S_DONE   = 3'd5;

  reg [2:0] state, state_n;

  // Submodule handshakes
  reg                ln_start;
  wire               ln_ready;
  wire        [ 7:0] ln_err;
  wire signed [31:0] ln_y;

  reg                div_start;
  wire               div_ready;
  wire        [ 7:0] div_err;
  wire signed [31:0] div_y;

  // Latched ln(x)
  reg signed  [31:0] ln_y_hold;

  // Sticky error + done pulse
  reg                err_sticky;
  reg                done_r;
  assign err   = err_sticky;
  assign ready = done_r;

  // convenience
  wire ln_domain_err = ln_err[0];  // x<=0
  wire ln_overflow = ln_err[1];
  wire ln_underflow = ln_err[2];
  // Fallback: near x?1, use ln(x) ? x-1 if ln underflowed to 0 but domain OK
  wire use_linear_fallback = (~ln_domain_err) & ln_underflow;

  // Submodules
  math_ln_q16 u_ln (
      .clk  (clk),
      .rst  (rst),
      .start(ln_start),
      .a    (a),
      .y    (ln_y),
      .ready(ln_ready),
      .err  (ln_err)
  );

  math_div_q16 u_div (
      .clk  (clk),
      .rst  (rst),
      .start(div_start),
      .a    (ln_y_hold),  // latched ln(x) or fallback
      .b    (LN10_Q16),
      .y    (div_y),
      .ready(div_ready),
      .err  (div_err)
  );

  // Sequential
  always @(posedge clk) begin
    if (rst) begin
      state      <= S_IDLE;
      ln_start   <= 1'b0;
      div_start  <= 1'b0;
      ln_y_hold  <= 32'sd0;
      y          <= 32'sd0;
      done_r     <= 1'b0;
      err_sticky <= 1'b0;
    end else begin
      state     <= state_n;

      // defaults
      ln_start  <= 1'b0;
      div_start <= 1'b0;
      done_r    <= 1'b0;

      case (state)
        S_IDLE: begin
          // clear sticky error on a fresh start
          if (start) begin
            err_sticky <= 1'b0;
            ln_start   <= 1'b1;  // kick ln
          end
        end

        S_RUNLN: begin
          // transit
        end

        S_WAITLN: begin
          if (ln_ready) begin
            // accumulate any ln errors
            if (|ln_err) err_sticky <= 1'b1;

            if (ln_domain_err) begin
              // x<=0: stop here, y=0
              y <= 32'sd0;
              // go S_DONE via next-state logic
            end else begin
              // Prepare ln(x) for division
              if (use_linear_fallback && (ln_y == 32'sd0)) begin
                // ln(x) ? x-1 for |x-1|<<1
                ln_y_hold <= a - 32'sh0001_0000;
              end else begin
                ln_y_hold <= ln_y;
              end
              div_start <= 1'b1;  // one-cycle start to divider
            end
          end
        end

        S_RUNDIV: begin
          // transit
        end

        S_WAITDV: begin
          if (div_ready) begin
            y <= div_y;
            if (|div_err) err_sticky <= 1'b1;
          end
        end

        S_DONE: begin
          done_r <= 1'b1;  // 1-cycle pulse
        end
      endcase
    end
  end

  // Next-state
  always @* begin
    state_n = state;
    case (state)
      S_IDLE:   state_n = start ? S_RUNLN : S_IDLE;
      S_RUNLN:  state_n = S_WAITLN;
      S_WAITLN: state_n = ln_ready ? ((ln_domain_err) ? S_DONE : S_RUNDIV) : S_WAITLN;
      S_RUNDIV: state_n = S_WAITDV;
      S_WAITDV: state_n = div_ready ? S_DONE : S_WAITDV;
      S_DONE:   state_n = S_IDLE;
      default:  state_n = S_IDLE;
    endcase
  end

endmodule
