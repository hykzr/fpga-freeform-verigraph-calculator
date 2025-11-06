//------------------------------------------------------------------------------
// math.v : Q16.16 math submodules (uniform outputs; unary/binary as needed)
// Error bit convention (you can map to your global bits later):
//   bit5 OVERFLOW (set when we saturate)
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
        // floor: if negative and has fraction -> ai - 1.0 (saturate at MIN)
        if (a[31] && frac_nz) begin
          if (at_min) begin
            y   <= Q16_MIN;
            err <= 8'h20;  // OVERFLOW (underflow)
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
        // ceil: if positive and has fraction -> ai + 1.0 (saturate at MAX)
        if (!a[31] && frac_nz) begin
          if (at_maxi) begin
            y   <= Q16_MAX;
            err <= 8'h20;  // OVERFLOW
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

  // round-half-away from zero with saturation
  wire signed [31:0] bias = a[31] ? -32'sh0000_8000 : 32'sh0000_8000;
  wire signed [32:0] sum = a + bias;
  wire               ov_pos = (!a[31]) && (sum[32] != sum[31] || sum[31:0] > Q16_MAX);
  wire               ov_neg = (a[31]) && (sum[32] != sum[31] || sum[31:0] < Q16_MIN);
  wire               any_ov = ov_pos || ov_neg;
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
          err <= 8'h20;  // OVERFLOW
        end else begin
          y   <= rounded;
          err <= 8'd0;
        end
        ready <= 1'b1;
      end
    end
  end
endmodule

//----------- Dummies (replace later) ------------------------------------------
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
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y <= a;
        err <= 8'd0;
        ready <= 1'b1;
      end
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
    output reg ready,
    output reg [7:0] err
);
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y <= a;
        err <= 8'd0;
        ready <= 1'b1;
      end
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
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y <= a;
        err <= 8'd0;
        ready <= 1'b1;
      end
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
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y <= a;
        err <= 8'd0;
        ready <= 1'b1;
      end
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
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y <= a;
        err <= 8'd0;
        ready <= 1'b1;
      end
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
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      y <= 32'sd0;
      ready <= 1'b0;
      err <= 8'd0;
    end else begin
      ready <= 1'b0;
      if (start) begin
        y <= a;
        err <= 8'd0;
        ready <= 1'b1;
      end
    end
  end
endmodule

module math_sqrt_q16 (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire signed [31:0] a,      // operand (Q16.16), must be >= 0
    output reg signed  [31:0] y,      // result  (Q16.16)
    output reg                ready,  // 1-cycle pulse when y is valid
    output reg         [ 7:0] err     // error flags (sticky until next start)
);

  // ---- Error bit map ------------------------------------------------------
  localparam ERR_NEG_INPUT = 8'h01;  // a < 0
  localparam ERR_DIV_ZERO = 8'h02;  // internal divide-by-zero guard tripped

  // ---- Fixed-point constants ----------------------------------------------
  localparam signed [31:0] ONE = 32'sh0001_0000;  // 1.0 in Q16.16
  localparam signed [31:0] HALF = 32'sh0000_8000;  // 0.5 in Q16.16

  // ---- Internal state ------------------------------------------------------
  reg        [ 1:0] st;  // 0:IDLE, 1:ITER, 2:DONE
  reg        [ 3:0] it;  // iteration counter (0..7)
  reg signed [31:0] x;  // operand latched
  reg signed [31:0] yk;  // current iterate
  reg signed [31:0] yn;  // next iterate

  // ---- Local fixed-point helpers (Q16.16) ---------------------------------
  function automatic signed [31:0] qmul;
    input signed [31:0] a, b;
    reg signed [63:0] t;
    begin
      t = a * b;
      qmul = t[47:16];  // keep Q16.16
    end
  endfunction

  function automatic signed [31:0] qdiv;
    input signed [31:0] a, b;
    reg signed [63:0] t;
    begin
      // shift numerator by 16 to preserve Q16.16 on division
      t = {a, 16'd0};
      // Simple guard: if b==0, return 0 (and set an error flag in FSM)
      qdiv = (b == 0) ? 32'sd0 : t / b;
    end
  endfunction

  // ---- FSM ----------------------------------------------------------------
  always @(posedge clk) begin
    if (rst) begin
      st    <= 2'd0;
      it    <= 4'd0;
      x     <= 32'sd0;
      yk    <= 32'sd0;
      yn    <= 32'sd0;
      y     <= 32'sd0;
      ready <= 1'b0;
      err   <= 8'd0;
    end else begin
      // default
      ready <= 1'b0;

      case (st)
        // IDLE / accept new job
        2'd0: begin
          if (start) begin
            err <= 8'd0;  // clear sticky errors on new start

            // Negative input -> error, return 0 immediately
            if (a < 0) begin
              y     <= 32'sd0;
              ready <= 1'b1;
              err   <= ERR_NEG_INPUT;
              st    <= 2'd0;  // stay idle (single-cycle ready pulse)
            end  // Zero -> valid result 0 (no error)
            else if (a == 0) begin
              y     <= 32'sd0;
              ready <= 1'b1;
              st    <= 2'd0;
            end else begin
              // latch operand and initialize iterate
              x  <= a;
              // Good heuristic: y0 = max(1.0, a/2) to keep divisor non-zero
              yk <= (a < ONE) ? ONE : (a >>> 1);
              it <= 4'd0;
              st <= 2'd1;  // ITER
            end
          end
        end

        // ITER: Newton step y_{k+1} = 0.5 * ( yk + x/yk )
        2'd1: begin
          // Divide guard: if yk==0 (shouldn't happen with our init), flag & recover
          if (yk == 0) begin
            err <= err | ERR_DIV_ZERO;
            // Nudge away from zero to continue (keeps resource use tiny)
            yk  <= ONE;  // restart iterate at 1.0
          end else begin
            yn <= qmul(HALF, (yk + qdiv(x, yk)));
            yk <= yn;
            it <= it + 1'b1;
            // After 8 iterations, settle (good for Q16.16)
            if (it == 4'd7) begin
              y  <= yn;
              st <= 2'd2;  // DONE
            end
          end
        end

        // DONE: assert ready for 1 cycle, then return to IDLE
        2'd2: begin
          ready <= 1'b1;
          st    <= 2'd0;
        end

        default: st <= 2'd0;
      endcase
    end
  end

endmodule
