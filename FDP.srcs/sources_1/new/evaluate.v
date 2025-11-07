module expression_evaluator #(
    parameter MAX_LEN    = 64,
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
  wire [32:0] tok_d;
  wire tok_v, tok_rdy;
  wire [7:0] tok_err;
  wire tok_done, rpn_done;
  tokenizer #(
      .MAX_LEN(MAX_LEN),
      .MAX_TOKENS(MAX_TOKENS)
  ) U_TOK (
      .clk(clk),
      .rst(rst),
      .start(start),
      .expr_in(expr_in),
      .expr_len(expr_len),
      .x_value(x_value),
      .out_tok(tok_d),
      .out_valid(tok_v),
      .out_ready(tok_rdy),
      .done(tok_done),
      .err_flags(tok_err)
  );

  wire [32:0] rpn_d;
  wire rpn_v, rpn_rdy;
  wire [7:0] rpn_err;

  shunting_yard #(
      .MAX_TOKENS(MAX_TOKENS)
  ) U_S (
      .clk(clk),
      .rst(rst),
      .in_tok(tok_d),
      .in_valid(tok_v),
      .in_ready(tok_rdy),
      .out_tok(rpn_d),
      .out_valid(rpn_v),
      .out_ready(rpn_rdy),
      .done(rpn_done),
      .err_flags(rpn_err)
  );

  wire signed [31:0] eval_res;
  wire               eval_done;
  wire        [ 7:0] eval_err;

  rpn_eval #(
      .MAX_TOKENS(MAX_TOKENS)
  ) U_E (
      .clk(clk),
      .rst(rst),
      .in_tok(rpn_d),
      .in_valid(rpn_v),
      .in_ready(rpn_rdy),
      .result(eval_res),
      .done(eval_done),
      .err_flags(eval_err)
  );

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      result <= 32'sd0;
      error_flags <= 8'd0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      if (eval_done) begin
        result      <= eval_res;
        error_flags <= tok_err | rpn_err | eval_err;
        done        <= 1'b1;
      end
    end
  end
endmodule
