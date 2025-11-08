//------------------------------------------------------------------------------
// parse.v : Tokenize (33b), Infix→RPN, Evaluate RPN (Q16.16)
// Token = {is_num[32], data[31:0]}
//   is_num=1 => data=Q16.16 number
//   is_num=0 => data[31:28]=kind, [27:24]=id
//------------------------------------------------------------------------------
`include "constants.vh"

`define TK_ISNUM(tk)     (tk[32])
`define TK_DATA(tk)      (tk[31:0])
`define TK_KIND(tk)      (tk[31:28])
`define TK_ID(tk)        (tk[27:24])

//============================== TOKENIZER =====================================
module tokenizer #(
    parameter MAX_LEN    = 64,
    parameter MAX_TOKENS = 32
)(
    input  wire                        clk, rst, start,
    input  wire [8*MAX_LEN-1:0]        expr_in,
    input  wire [7:0]                  expr_len,
    input  wire signed [31:0]          x_value,
    output reg  [32:0]                 out_tok,
    output reg                         out_valid,
    input  wire                        out_ready,
    output reg                         done,
    output reg  [7:0]                  err_flags
);
    reg        np_start;
    reg [7:0]  np_base;
    wire signed [31:0] np_q;
    wire [7:0] np_end;
    wire [7:0] np_err;
    wire       np_done;

    str_to_q16_16 #(.MAX_LEN(MAX_LEN), .MAX_FRAC_DIG(6)) NUM (
        .clk(clk), .rst(rst), .start(np_start),
        .expr_in(expr_in), .expr_len(expr_len), .base_idx(np_base),
        .q_out(np_q), .end_idx(np_end), .err_flags(np_err), .done(np_done)
    );

    localparam [2:0] S_IDLE=3'd0, S_SCAN=3'd1, S_NUM=3'd2, S_EMIT=3'd3, S_TAIL=3'd4, S_END=3'd5;
    reg [2:0] s, s_n;

    reg [7:0]  i, i_n;
    reg        prev_value, prev_value_n;
    reg [32:0] tok_buf, tok_buf_n;

    reg [7:0] paren_balance, paren_balance_n; // count '(' minus ')'
    reg [7:0] tail_cnt, tail_cnt_n;           // how many ')' to flush at end

    wire [7:0] ch = (i < expr_len) ? expr_in[8*i +: 8] : 8'd0;

    wire is_digit = (ch >= "0" && ch <= "9");
    wire is_dot   = (ch == ".");
    wire is_x     = (ch == "x");

    function [31:0] pack_op; input [3:0] id; begin pack_op = {`TK_KIND_OP,id,24'd0}; end endfunction
    localparam [31:0] pack_lp    = {`TK_KIND_LPAREN ,4'd0,24'd0};
    localparam [31:0] pack_rp    = {`TK_KIND_RPAREN,4'd0,24'd0};
    localparam [31:0] pack_comma = {`TK_KIND_COMMA ,4'd0,24'd0};
    function [31:0] pack_fn; input [3:0] id; begin pack_fn = {`TK_KIND_FUNC,id,24'd0}; end endfunction
    localparam [31:0] pack_end   = {`TK_KIND_END   ,4'd0,24'd0};

    wire is_sin_key    = (ch == `SIN_KEY);
    wire is_cos_key    = (ch == `COS_KEY);
    wire is_tan_key    = (ch == `TAN_KEY);
    wire is_sqrt_key   = (ch == `SQRT_KEY);
    wire is_ln_key     = (ch == `LN_KEY);
    wire is_log_key    = (ch == `LOG_KEY);
    wire is_abs_key    = (ch == `ABS_KEY);
    wire is_floor_key  = (ch == `FLOOR_KEY);
    wire is_ceil_key   = (ch == `CEIL_KEY);
    wire is_round_key  = (ch == `ROUND_KEY);
    wire is_not_ascii  = (ch == "~"); // keep as unary function

    // binary/variadic functions that still require () + commas
    wire is_min_key    = (ch == `MIN_KEY);
    wire is_max_key    = (ch == `MAX_KEY);

    // operators / constants
    wire is_pow_char   = (ch == "^");          // '^' is POWER operator now
    wire is_pow_key    = (ch == `POW_KEY);     // optional: accept special power key too
    wire is_xor_key    = (ch == `XOR_KEY);     // XOR no longer '^'
    wire is_pi_key     = (ch == `PI_KEY);
    wire is_e_ascii    = (ch == "e");

    function [3:0] fn_id_from_key;
        input [7:0] key;
    begin
        case (key)
            `SIN_KEY:   fn_id_from_key = `FN_SIN;
            `COS_KEY:   fn_id_from_key = `FN_COS;
            `TAN_KEY:   fn_id_from_key = `FN_TAN;
            `SQRT_KEY:  fn_id_from_key = `FN_SQRT;
            `ABS_KEY:   fn_id_from_key = `FN_ABS;
            `FLOOR_KEY: fn_id_from_key = `FN_FLOOR;
            `CEIL_KEY:  fn_id_from_key = `FN_CEIL;
            `ROUND_KEY: fn_id_from_key = `FN_ROUND;
            `LN_KEY:    fn_id_from_key = `FN_LN;
            `LOG_KEY:   fn_id_from_key = `FN_LOG;
            default:    fn_id_from_key = `FN_NOT; // '~'
        endcase
    end endfunction

    always @* begin
        s_n = s; i_n = i; prev_value_n = prev_value;
        out_valid=1'b0; out_tok=33'd0; done=1'b0; err_flags=8'd0;
        tok_buf_n=tok_buf; np_start=1'b0; np_base=i;
        paren_balance_n = paren_balance; tail_cnt_n = tail_cnt;

        case (s)
            S_IDLE: begin
                if (start) begin
                    s_n=S_SCAN; i_n=8'd0; prev_value_n=1'b0;
                    paren_balance_n=8'd0; tail_cnt_n=8'd0;
                end
            end
            S_SCAN: begin
                if (i >= expr_len) begin
                    // end → flush missing ')' then END
                    if (paren_balance != 0) begin
                        tail_cnt_n = paren_balance;
                        s_n = S_TAIL;
                    end else begin
                        s_n = S_END;
                    end

                end else if (is_digit || is_dot) begin
                    np_start = 1'b1; np_base = i; s_n = S_NUM;
                end else if (is_x) begin
                    tok_buf_n = {1'b1, x_value}; i_n = i+1; s_n=S_EMIT;
                end else if (is_pi_key) begin
                    tok_buf_n = {1'b1, `Q16_PI}; i_n = i+1; s_n=S_EMIT;
                end else if (is_e_ascii) begin
                    tok_buf_n = {1'b1, `Q16_E}; i_n = i+1; s_n=S_EMIT;
                end else if (ch=="(") begin
                    tok_buf_n = {1'b0, pack_lp}; i_n=i+1; s_n=S_EMIT;
                    paren_balance_n = paren_balance + 1;
                end else if (ch==")") begin
                    tok_buf_n = {1'b0, pack_rp}; i_n=i+1; s_n=S_EMIT;
                    paren_balance_n = (paren_balance!=0) ? (paren_balance - 1) : 8'd0;
                end else if (ch==",") begin
                    tok_buf_n = {1'b0, pack_comma}; i_n=i+1; s_n=S_EMIT;
                end else if (ch=="+") begin
                    tok_buf_n = {1'b0, pack_op(`OP_ADD)}; i_n=i+1; s_n=S_EMIT;
                end else if (ch=="-") begin
                    tok_buf_n = {1'b0, pack_op(prev_value ? `OP_SUB : `OP_UN_NEG)}; i_n=i+1; s_n=S_EMIT;
                end else if (ch=="*") begin
                    tok_buf_n = {1'b0, pack_op(`OP_MUL)}; i_n=i+1; s_n=S_EMIT;
                end else if (ch=="/") begin
                    tok_buf_n = {1'b0, pack_op(`OP_DIV)}; i_n=i+1; s_n=S_EMIT;
                end else if (ch=="%") begin
                    tok_buf_n = {1'b0, pack_op(`OP_REM)}; i_n=i+1; s_n=S_EMIT;
                end else if (ch=="&") begin
                    tok_buf_n = {1'b0, pack_op(`OP_AND)}; i_n=i+1; s_n=S_EMIT;
                end else if (ch=="|") begin
                    tok_buf_n = {1'b0, pack_op(`OP_OR)}; i_n=i+1; s_n=S_EMIT;
                end else if (is_xor_key) begin
                    tok_buf_n = {1'b0, pack_op(`OP_XOR)}; i_n=i+1; s_n=S_EMIT;
                end else if (is_pow_char || is_pow_key) begin
                    tok_buf_n = {1'b0, pack_op(`OP_POW)}; i_n=i+1; s_n=S_EMIT;
                end else if (is_sin_key || is_cos_key || is_tan_key || is_sqrt_key ||
                             is_ln_key  || is_log_key || is_abs_key  || is_floor_key ||
                             is_ceil_key|| is_round_key || is_not_ascii) begin
                    tok_buf_n = {1'b0, pack_fn(fn_id_from_key(ch))};
                    i_n = i+1; s_n = S_EMIT;
                end else if (is_min_key || is_max_key) begin
                    tok_buf_n = {1'b0, pack_fn((ch==`MIN_KEY)?`FN_MIN:`FN_MAX)};
                    i_n = i+1; s_n = S_EMIT;
                end else begin
                    // unknown → end
                    s_n = S_END;
                end
            end
            S_NUM: begin
                if (np_done) begin
                    tok_buf_n = {1'b1, np_q};
                    i_n       = np_end;
                    s_n       = S_EMIT;
                end
            end
            S_EMIT: begin
                out_valid = 1'b1; out_tok = tok_buf;
                if (out_ready) begin
                    if (tok_buf[32]) begin
                        prev_value_n = 1'b1;                // number
                    end else begin
                        case (`TK_KIND(tok_buf))
                          `TK_KIND_RPAREN: prev_value_n = 1'b1;
                          default:         prev_value_n = 1'b0;
                        endcase
                    end
                    s_n = S_SCAN;
                end
            end
            // flush missing ')' at end
            S_TAIL: begin
                if (tail_cnt != 0) begin
                    out_valid = 1'b1; out_tok = {1'b0, pack_rp};
                    if (out_ready) begin
                        tail_cnt_n = tail_cnt - 1;
                        if (tail_cnt_n == 0) s_n = S_END;
                    end
                end else begin
                    s_n = S_END;
                end
            end
            // final END
            S_END: begin
                out_valid = 1'b1; out_tok = {1'b0, pack_end};
                if (out_ready) begin
                    done = 1'b1; s_n = S_IDLE;
                end
            end
            default: s_n=S_IDLE;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            s<=S_IDLE; i<=0; prev_value<=1'b0; tok_buf<=33'd0;
            paren_balance<=0; tail_cnt<=0;
        end else begin
            s<=s_n; i<=i_n; prev_value<=prev_value_n; tok_buf<=tok_buf_n;
            paren_balance<=paren_balance_n; tail_cnt<=tail_cnt_n;
        end
    end
endmodule

//=========================== SHUNTING-YARD ====================================
module shunting_yard #(
    parameter MAX_TOKENS = 32
)(
    input  wire        clk, rst,
    input  wire [32:0] in_tok,
    input  wire        in_valid,
    output reg         in_ready,
    output reg  [32:0] out_tok,
    output reg         out_valid,
    input  wire        out_ready,
    output reg         done,
    output reg  [7:0]  err_flags
);

    function [6:0] op_info; input [3:0] id; begin
        case (id)
            `OP_ADD: op_info = {2'd2,3'd1,1'b0};
            `OP_SUB: op_info = {2'd2,3'd1,1'b0};
            `OP_MUL: op_info = {2'd2,3'd2,1'b0};
            `OP_DIV: op_info = {2'd2,3'd2,1'b0};
            `OP_REM: op_info = {2'd2,3'd2,1'b0};
            `OP_AND: op_info = {2'd2,3'd0,1'b0};
            `OP_OR : op_info = {2'd2,3'd0,1'b0};
            `OP_XOR: op_info = {2'd2,3'd0,1'b0};
            `OP_POW: op_info = {2'd2,3'd3,1'b1};
            default: op_info = {2'd1,3'd4,1'b1}; // unary as highest precedence (assoc right)
        endcase
    end endfunction

    localparam integer WTK = 33;
    localparam integer DEP = MAX_TOKENS;
    reg [WTK*DEP-1:0] opv, opv_n;
    reg [$clog2(DEP+1)-1:0] sp, sp_n;
    reg [32:0] hold, hold_n;
    reg        have_hold, have_hold_n;

    wire [32:0] top = (sp==0) ? 33'd0 : opv[WTK*(sp-1)+:WTK];
    wire top_is_op   = (!top[32]) && (`TK_KIND(top)==`TK_KIND_OP);
    wire top_is_func = (!top[32]) && (`TK_KIND(top)==`TK_KIND_FUNC);
    function need_pop; 
        input [32:0] cur_op, stk_op; 
        reg [6:0] ci, si;
    begin
        ci = op_info(`TK_ID(cur_op));
        si = op_info(`TK_ID(stk_op));
        need_pop = (ci[0]) ? (si[3:1] > ci[3:1]) : (si[3:1] >= ci[3:1]);
    end endfunction

    localparam [2:0] S_IDLE=3'd0,S_GET=3'd1,S_HOLD=3'd2,S_FLUSH=3'd3,S_DONE=3'd4,
                     S_FLUSHFN=3'd5;
    reg [2:0] s, s_n;

    task emit_top;
    begin
        if (out_ready) begin out_valid=1'b1; out_tok=top; sp_n=sp-1; end
        else            begin out_valid=1'b1; out_tok=top;             end
    end
    endtask

    always @* begin
        s_n=s; opv_n=opv; sp_n=sp; hold_n=hold; have_hold_n=have_hold;
        in_ready=1'b0; out_valid=1'b0; out_tok=33'd0; done=1'b0; err_flags=8'd0;

        case (s)
            S_IDLE: begin
                opv_n={WTK*DEP{1'b0}}; sp_n=0; have_hold_n=1'b0;
                if (in_valid) s_n=S_GET; else in_ready=1'b1;
            end
            S_GET: begin
                if (!have_hold && in_valid) begin hold_n=in_tok; have_hold_n=1'b1; in_ready=1'b1; end
                if (have_hold) begin
                    if (`TK_ISNUM(hold)) begin
                        // output number, then immediately flush pending FUNCs (implicit application)
                        if (out_ready) begin out_valid=1'b1; out_tok=hold; have_hold_n=1'b0; s_n=S_FLUSHFN; end
                        else            begin out_valid=1'b1; out_tok=hold; end
                    end else begin
                        s_n=S_HOLD;
                    end
                end
            end
            S_HOLD: begin
                if      (`TK_KIND(hold)==`TK_KIND_LPAREN) begin
                    opv_n[WTK*sp+:WTK]=hold; sp_n=sp+1; have_hold_n=1'b0; s_n=S_GET;
                end else if (`TK_KIND(hold)==`TK_KIND_FUNC) begin
                    opv_n[WTK*sp+:WTK]=hold; sp_n=sp+1; have_hold_n=1'b0; s_n=S_GET;
                end else if (`TK_KIND(hold)==`TK_KIND_RPAREN) begin
                    if (sp==0) begin have_hold_n=1'b0; s_n=S_GET; end
                    else begin
                        if (`TK_KIND(top)==`TK_KIND_LPAREN) begin
                            sp_n=sp-1; // pop '('
                            // if function below '(', emit it (explicit call)
                            if (sp_n!=0 && opv[(WTK*(sp_n-1)+28)+:4]==`TK_KIND_FUNC) begin
                                emit_top; // this emits the FUNC that was below '('
                            end
                            have_hold_n=1'b0; s_n=S_GET;
                        end else begin
                            emit_top; // pop ops until '('
                        end
                    end

                end else if (`TK_KIND(hold)==`TK_KIND_COMMA) begin
                    // function arg separator: pop until '('
                    if (sp==0) begin have_hold_n=1'b0; s_n=S_GET; end
                    else begin
                        if (`TK_KIND(top)==`TK_KIND_LPAREN) begin
                            have_hold_n=1'b0; s_n=S_GET; // do not pop '('
                        end else begin
                            emit_top;
                        end
                    end
                end else if (`TK_KIND(hold)==`TK_KIND_OP) begin
                    if (sp!=0 && top_is_op && need_pop(hold, top)) begin
                        emit_top;
                    end else begin
                        opv_n[WTK*sp+:WTK] = hold; sp_n=sp+1; have_hold_n=1'b0; s_n=S_GET;
                    end
                end else if (`TK_KIND(hold)==`TK_KIND_END) begin
                    s_n=S_FLUSH;
                end else begin
                    have_hold_n=1'b0; s_n=S_GET;
                end
            end
            S_FLUSH: begin
                if (sp!=0) begin
                    emit_top;
                end else begin
                    if (out_ready) begin out_valid=1'b1; out_tok={1'b0,{`TK_KIND_END,4'd0,24'd0}}; done=1'b1; s_n=S_DONE; end
                    else            begin out_valid=1'b1; out_tok={1'b0,{`TK_KIND_END,4'd0,24'd0}}; end
                end
            end

            // NEW: after a primary, apply any pending implicit functions (highest precedence)
            S_FLUSHFN: begin
                if (sp!=0 && top_is_func) begin
                    emit_top;
                end else begin
                    s_n = S_GET;
                end
            end
            S_DONE: begin
                done=1'b1;
                if (!in_valid) s_n=S_IDLE;
            end
            default: s_n=S_IDLE;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin s<=S_IDLE; opv<={WTK*DEP{1'b0}}; sp<=0; hold<=33'd0; have_hold<=1'b0;
        end else begin s<=s_n; opv<=opv_n; sp<=sp_n; hold<=hold_n; have_hold<=have_hold_n; end
    end
endmodule

//============================== RPN EVALUATOR =================================
module rpn_eval #(
    parameter MAX_TOKENS = 32
)(
    input  wire        clk, rst,
    input  wire [32:0] in_tok,
    input  wire        in_valid,
    output reg         in_ready,
    output reg  signed [31:0] result,
    output reg         done,
    output reg  [7:0]  err_flags
);
    localparam integer DEP = MAX_TOKENS;
    reg [32*DEP-1:0] vv, vv_n;
    reg [$clog2(DEP+1)-1:0] sp, sp_n;

    reg        m_start;
    reg [4:0]  m_sel;
    reg signed [31:0] a, b;

    wire signed [31:0] y_add,y_sub,y_mul,y_div,y_div_rem,y_pow,y_sin,y_cos,y_tan,y_ceil,y_floor,y_round;
    wire signed [31:0] y_sqrt,y_abs,y_max,y_min,y_and,y_or,y_xor,y_not,y_ln,y_log;
    wire r_add,r_sub,r_mul,r_div,r_pow,r_sin,r_cos,r_tan,r_ceil,r_floor,r_round;
    wire r_sqrt,r_abs,r_max,r_min,r_and,r_or,r_xor,r_not,r_ln,r_log;
    wire [7:0] e_add,e_sub,e_mul,e_div,e_pow,e_sin,e_cos,e_tan,e_ceil,e_floor,e_round;
    wire [7:0] e_sqrt,e_abs,e_max,e_min,e_and,e_or,e_xor,e_not,e_ln,e_log;

    math_add_q16   U_ADD(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd0)),.a(a),.b(b),.y(y_add),.ready(r_add),.err(e_add));
    math_sub_q16   U_SUB(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd1)),.a(a),.b(b),.y(y_sub),.ready(r_sub),.err(e_sub));
    math_mul_q16   U_MUL(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd2)),.a(a),.b(b),.y(y_mul),.ready(r_mul),.err(e_mul));
    math_div_q16   U_DIV(.clk(clk),.rst(rst),.start(m_start&&((m_sel==5'd3)||(m_sel==5'd15))),.a(a),.b(b),.y(y_div),.remainder(y_div_rem),.ready(r_div),.err(e_div));
    math_pow_q16   U_POW(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd4)),.a(a),.b(b),.y(y_pow),.ready(r_pow),.err(e_pow));
    math_sin_q16   U_SIN(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd5)),.a(a),.y(y_sin),.ready(r_sin),.err(e_sin));
    math_cos_q16   U_COS(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd6)),.a(a),.y(y_cos),.ready(r_cos),.err(e_cos));
    math_tan_q16   U_TAN(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd7)),.a(a),.y(y_tan),.ready(r_tan),.err(e_tan));
    math_ceil_q16  U_CEIL(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd8)),.a(a),.y(y_ceil),.ready(r_ceil),.err(e_ceil));
    math_floor_q16 U_FLOOR(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd9)),.a(a),.y(y_floor),.ready(r_floor),.err(e_floor));
    math_round_q16 U_ROUND(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd10)),.a(a),.y(y_round),.ready(r_round),.err(e_round));
    sqrt_q16_16    U_SQRT(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd11)),.a(a),.y(y_sqrt),.ready(r_sqrt),.err(e_sqrt));
    math_abs_q16   U_ABS(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd12)),.a(a),.y(y_abs),.ready(r_abs),.err(e_abs));
    math_max_q16   U_MAX(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd13)),.a(a),.b(b),.y(y_max),.ready(r_max),.err(e_max));
    math_min_q16   U_MIN(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd14)),.a(a),.b(b),.y(y_min),.ready(r_min),.err(e_min));
    math_and_q16   U_AND(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd16)),.a(a),.b(b),.y(y_and),.ready(r_and),.err(e_and));
    math_or_q16    U_OR(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd17)),.a(a),.b(b),.y(y_or),.ready(r_or),.err(e_or));
    math_xor_q16   U_XOR(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd18)),.a(a),.b(b),.y(y_xor),.ready(r_xor),.err(e_xor));
    math_not_q16   U_NOT(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd19)),.a(a),.y(y_not),.ready(r_not),.err(e_not));
    math_ln_q16    U_LN(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd20)),.a(a),.y(y_ln),.ready(r_ln),.err(e_ln));
    math_log_q16   U_LOG(.clk(clk),.rst(rst),.start(m_start&&(m_sel==5'd21)),.a(a),.y(y_log),.ready(r_log),.err(e_log));

    reg signed [31:0] y_mux;
    reg [7:0] e_mux;
    wire r_any = r_add|r_sub|r_mul|r_div|r_pow|r_sin|r_cos|r_tan|r_ceil|r_floor|r_round|
                 r_sqrt|r_abs|r_max|r_min|r_and|r_or|r_xor|r_not|r_ln|r_log;

    always @* begin
        y_mux = 32'sd0; e_mux=8'd0;
        if (r_add)   begin y_mux=y_add;   e_mux=e_add; end
        else if(r_sub)begin y_mux=y_sub;  e_mux=e_sub; end
        else if(r_mul)begin y_mux=y_mul;  e_mux=e_mul; end
        else if(r_div)begin 
            if (m_sel==5'd15) begin y_mux=y_div_rem; e_mux=e_div; end
            else begin y_mux=y_div; e_mux=e_div; end
        end
        else if(r_pow)begin y_mux=y_pow;  e_mux=e_pow; end
        else if(r_sin)begin y_mux=y_sin;  e_mux=e_sin; end
        else if(r_cos)begin y_mux=y_cos;  e_mux=e_cos; end
        else if(r_tan)begin y_mux=y_tan;  e_mux=e_tan; end
        else if(r_ceil)begin y_mux=y_ceil;e_mux=e_ceil; end
        else if(r_floor)begin y_mux=y_floor; e_mux=e_floor; end
        else if(r_round)begin y_mux=y_round; e_mux=e_round; end
        else if(r_sqrt)begin y_mux=y_sqrt; e_mux=e_sqrt; end
        else if(r_abs)begin y_mux=y_abs; e_mux=e_abs; end
        else if(r_max)begin y_mux=y_max; e_mux=e_max; end
        else if(r_min)begin y_mux=y_min; e_mux=e_min; end
        else if(r_and)begin y_mux=y_and; e_mux=e_and; end
        else if(r_or)begin y_mux=y_or; e_mux=e_or; end
        else if(r_xor)begin y_mux=y_xor; e_mux=e_xor; end
        else if(r_not)begin y_mux=y_not; e_mux=e_not; end
        else if(r_ln)begin y_mux=y_ln; e_mux=e_ln; end
        else if(r_log)begin y_mux=y_log; e_mux=e_log; end
    end

    localparam [2:0] S_IDLE=3'd0,S_READ=3'd1,S_OP=3'd2,S_WAIT=3'd3,S_DONE=3'd4;
    reg [2:0] s, s_n;
    reg [7:0] err_acc, err_acc_n;

    wire signed [31:0] top    = (sp==0) ? 32'sd0 : vv[32*(sp-1) +: 32];
    wire signed [31:0] topm1  = (sp<2)  ? 32'sd0 : vv[32*(sp-2) +: 32];

    reg [32:0] tk, tk_n;
    reg        have_tk, have_tk_n;

    always @* begin
        s_n=s; in_ready=1'b0; result=32'sd0; done=1'b0;
        vv_n=vv; sp_n=sp; tk_n=tk; have_tk_n=have_tk;
        m_start=1'b0; m_sel=5'd0; a=32'sd0; b=32'sd0;
        err_acc_n = err_acc;

        case (s)
            S_IDLE: begin
                vv_n={32*DEP{1'b0}}; sp_n=0; have_tk_n=1'b0; err_acc_n=8'd0;
                if (in_valid) s_n=S_READ; else in_ready=1'b1;
            end
            S_READ: begin
                if (!have_tk && in_valid) begin tk_n=in_tok; have_tk_n=1'b1; in_ready=1'b1; end
                if (have_tk) begin
                    if (`TK_ISNUM(tk)) begin
                        vv_n[32*sp +: 32] = `TK_DATA(tk); sp_n = sp + 1; have_tk_n=1'b0;
                    end else if (`TK_KIND(tk)==`TK_KIND_OP) begin
                        s_n = S_OP;
                    end else if (`TK_KIND(tk)==`TK_KIND_FUNC) begin
                        if (sp<1) begin sp_n=0; have_tk_n=1'b0;
                        end else if (`TK_ID(tk)==`FN_POW || `TK_ID(tk)==`FN_MAX || `TK_ID(tk)==`FN_MIN) begin
                            if (sp<2) begin sp_n=0; have_tk_n=1'b0; end
                            else begin
                                a = topm1; b = top;
                                case (`TK_ID(tk))
                                    `FN_POW: m_sel=5'd4;
                                    `FN_MAX: m_sel=5'd13;
                                    default: m_sel=5'd14;
                                endcase
                                m_start=1'b1; s_n=S_WAIT;
                                vv_n[32*(sp-1) +: 32] = 32'sd0;
                                vv_n[32*(sp-2) +: 32] = 32'sd0;
                                sp_n = sp - 2;
                            end
                        end else begin
                            a = top;
                            case (`TK_ID(tk))
                                `FN_SIN:   m_sel=5'd5;
                                `FN_COS:   m_sel=5'd6;
                                `FN_TAN:   m_sel=5'd7;
                                `FN_CEIL:  m_sel=5'd8;
                                `FN_FLOOR: m_sel=5'd9;
                                `FN_ROUND: m_sel=5'd10;
                                `FN_SQRT:  m_sel=5'd11;
                                `FN_ABS:   m_sel=5'd12;
                                `FN_NOT:   m_sel=5'd19;
                                `FN_LN:    m_sel=5'd20;
                                default:   m_sel=5'd21;
                            endcase
                            m_start=1'b1; s_n=S_WAIT; vv_n[32*(sp-1) +: 32] = 32'sd0; sp_n=sp-1;
                        end
                    end else if (`TK_KIND(tk)==`TK_KIND_END) begin
                        if (sp==1) begin result=top; done=1'b1; s_n=S_DONE; end
                        else begin result=(sp!=0)?top:32'sd0; done=1'b1; s_n=S_DONE; end
                    end
                end
            end
            S_OP: begin
                if (`TK_ID(tk)==`OP_UN_NEG) begin
                    if (sp<1) begin sp_n=0; have_tk_n=1'b0; s_n=S_READ; end
                    else begin
                        a = 32'sd0; b = top; m_sel=5'd1;
                        m_start=1'b1; s_n=S_WAIT; vv_n[32*(sp-1) +: 32] = 32'sd0; sp_n=sp-1;
                    end
                end else begin
                    if (sp<2) begin sp_n=0; have_tk_n=1'b0; s_n=S_READ; end
                    else begin
                        a = topm1; b = top;
                        case (`TK_ID(tk))
                            `OP_ADD: m_sel=5'd0;
                            `OP_SUB: m_sel=5'd1;
                            `OP_MUL: m_sel=5'd2;
                            `OP_DIV: m_sel=5'd3;
                            `OP_POW: m_sel=5'd4;
                            `OP_REM: m_sel=5'd15;
                            `OP_AND: m_sel=5'd16;
                            `OP_OR:  m_sel=5'd17;
                            default: m_sel=5'd18;
                        endcase
                        m_start=1'b1; s_n=S_WAIT;
                        vv_n[32*(sp-1) +: 32] = 32'sd0;
                        vv_n[32*(sp-2) +: 32] = 32'sd0;
                        sp_n = sp - 2;
                    end
                end
            end
            S_WAIT: begin
                if (r_any) begin
                    vv_n[32*sp +: 32] = y_mux; sp_n = sp + 1;
                    err_acc_n = err_acc | e_mux;
                    have_tk_n = 1'b0;
                    s_n = S_READ;
                end
            end
            S_DONE: begin
                done=1'b1; err_flags = err_acc;
                if (!in_valid) s_n=S_IDLE;
            end
            default: s_n=S_IDLE;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin s<=S_IDLE; vv<={32*DEP{1'b0}}; sp<=0; tk<=33'd0; have_tk<=1'b0; err_acc<=8'd0;
        end else begin s<=s_n; vv<=vv_n; sp<=sp_n; tk<=tk_n; have_tk<=have_tk_n; err_acc<=err_acc_n; end
    end
endmodule