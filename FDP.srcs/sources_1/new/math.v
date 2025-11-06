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
