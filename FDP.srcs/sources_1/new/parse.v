//------------------------------------------------------------------------------
// parse.v : Tokenize (33b), Infix→RPN, Evaluate RPN (Q16.16)
// Token = {is_num[32], data[31:0]}
//   is_num=1 => data=Q16.16 number
//   is_num=0 => data[31:28]=kind, [27:24]=id
// Kinds: OP=1, LPAREN=2, RPAREN=3, FUNC=4, END=15
// OP ids: ADD=0,SUB=1,MUL=2,DIV=3,POW=4,UN_NEG=5
// FUNC ids: SIN=0,COS=1,TAN=2,CEIL=3,FLOOR=4,ROUND=5
// Error flags: bit5 used by math cores for OVERFLOW; others can be added.
//------------------------------------------------------------------------------

`define TK_ISNUM(tk)     (tk[32])
`define TK_DATA(tk)      (tk[31:0])
`define TK_KIND(tk)      (tk[31:28])
`define TK_ID(tk)        (tk[27:24])

//============================== TOKENIZER =====================================
module tokenizer33 #(
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
    localparam [3:0] K_OP=4'd1, K_LP=4'd2, K_RP=4'd3, K_FUNC=4'd4, K_END=4'd15;
    localparam [3:0] OP_ADD=4'd0,OP_SUB=4'd1,OP_MUL=4'd2,OP_DIV=4'd3,OP_POW=4'd4,OP_UN=4'd5;
    localparam [3:0] FN_SIN=4'd0,FN_COS=4'd1,FN_TAN=4'd2,FN_CEIL=4'd3,FN_FLOOR=4'd4,FN_ROUND=4'd5;

    // number parser
    reg        np_start;
    reg [7:0]  np_base;
    wire signed [31:0] np_q;
    wire [7:0] np_end;
    wire [7:0] np_err;
    wire np_done;

    str_to_q16_16 #(.MAX_LEN(MAX_LEN), .MAX_FRAC_DIG(6)) NUM (
        .clk(clk), .rst(rst), .start(np_start),
        .expr_in(expr_in), .expr_len(expr_len), .base_idx(np_base),
        .q_out(np_q), .end_idx(np_end), .err_flags(np_err), .done(np_done)
    );

    // state
    localparam [2:0] S_IDLE=3'd0,S_SCAN=3'd1,S_NUM=3'd2,S_EMIT=3'd3;
    reg [2:0] s, s_n;

    reg [7:0] i, i_n;              // scan index
    reg       prev_value, prev_value_n; // for unary minus detection
    reg [32:0] tok_buf, tok_buf_n;

    // helpers
    wire [7:0] ch  = (i < expr_len) ? expr_in[8*i +: 8] : 8'd0;
    wire [7:0] ch1 = ((i+1) < expr_len) ? expr_in[8*(i+1) +: 8] : 8'd0;
    wire [7:0] ch2 = ((i+2) < expr_len) ? expr_in[8*(i+2) +: 8] : 8'd0;
    wire [7:0] ch3 = ((i+3) < expr_len) ? expr_in[8*(i+3) +: 8] : 8'd0;
    wire [7:0] ch4 = ((i+4) < expr_len) ? expr_in[8*(i+4) +: 8] : 8'd0;

    wire is_digit = (ch >= "0" && ch <= "9");
    wire is_dot   = (ch == ".");
    wire is_x     = (ch == "x");   // lower-case only

    function [31:0] pack_op; input [3:0] id; begin pack_op = {K_OP,id,24'd0}; end endfunction
    localparam [31:0] pack_lp = {K_LP,4'd0,24'd0};
    localparam [31:0] pack_rp = {K_RP,4'd0,24'd0};
    function [31:0] pack_fn; input [3:0] id; begin pack_fn = {K_FUNC,id,24'd0}; end endfunction
    localparam [31:0] pack_end = {K_END,4'd0,24'd0};

    // identifiers (lowercase)
    wire is_sin   = (ch=="s" && ch1=="i" && ch2=="n");
    wire is_cos   = (ch=="c" && ch1=="o" && ch2=="s");
    wire is_tan   = (ch=="t" && ch1=="a" && ch2=="n");
    wire is_ceil  = (ch=="c" && ch1=="e" && ch2=="i" && ch3=="l");
    wire is_floor = (ch=="f" && ch1=="l" && ch2=="o" && ch3=="o" && ch4=="r");
    wire is_round = (ch=="r" && ch1=="o" && ch2=="u" && ch3=="n" && ch4=="d");

    always @* begin
        s_n = s; i_n = i; prev_value_n = prev_value;
        out_valid=1'b0; out_tok=33'd0; done=1'b0; err_flags=8'd0;
        tok_buf_n=tok_buf; np_start=1'b0; np_base=i;

        case (s)
            S_IDLE: begin
                if (start) begin s_n=S_SCAN; i_n=8'd0; prev_value_n=1'b0; end
            end
            S_SCAN: begin
                if (i >= expr_len) begin
                    tok_buf_n = {1'b0, pack_end};
                    s_n = S_EMIT;
                end else if (is_digit || is_dot) begin
                    np_start = 1'b1; np_base = i; s_n = S_NUM;
                end else if (is_x) begin
                    tok_buf_n = {1'b1, x_value};
                    i_n = i + 8'd1; s_n = S_EMIT;
                end else if (ch=="(") begin
                    tok_buf_n = {1'b0, pack_lp}; i_n=i+8'd1; s_n=S_EMIT;
                end else if (ch==")") begin
                    tok_buf_n = {1'b0, pack_rp}; i_n=i+8'd1; s_n=S_EMIT;
                end else if (ch=="+") begin
                    tok_buf_n = {1'b0, pack_op(OP_ADD)}; i_n=i+8'd1; s_n=S_EMIT;
                end else if (ch=="-") begin
                    tok_buf_n = {1'b0, pack_op(prev_value ? OP_SUB : OP_UN)}; i_n=i+8'd1; s_n=S_EMIT;
                end else if (ch=="*") begin
                    tok_buf_n = {1'b0, pack_op(OP_MUL)}; i_n=i+8'd1; s_n=S_EMIT;
                end else if (ch=="/") begin
                    tok_buf_n = {1'b0, pack_op(OP_DIV)}; i_n=i+8'd1; s_n=S_EMIT;
                end else if (ch=="^") begin
                    tok_buf_n = {1'b0, pack_op(OP_POW)}; i_n=i+8'd1; s_n=S_EMIT;
                end else if (is_sin) begin
                    tok_buf_n = {1'b0, pack_fn(FN_SIN)}; i_n=i+8'd3; s_n=S_EMIT;
                end else if (is_cos) begin
                    tok_buf_n = {1'b0, pack_fn(FN_COS)}; i_n=i+8'd3; s_n=S_EMIT;
                end else if (is_tan) begin
                    tok_buf_n = {1'b0, pack_fn(FN_TAN)}; i_n=i+8'd3; s_n=S_EMIT;
                end else if (is_ceil) begin
                    tok_buf_n = {1'b0, pack_fn(FN_CEIL)}; i_n=i+8'd4; s_n=S_EMIT;
                end else if (is_floor) begin
                    tok_buf_n = {1'b0, pack_fn(FN_FLOOR)}; i_n=i+8'd5; s_n=S_EMIT;
                end else if (is_round) begin
                    tok_buf_n = {1'b0, pack_fn(FN_ROUND)}; i_n=i+8'd5; s_n=S_EMIT;
                end else begin
                    // unknown -> force END; you can also set a SYNTAX bit here
                    tok_buf_n = {1'b0, pack_end};
                    s_n = S_EMIT;
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
                if (out_ready) begin
                    out_valid = 1'b1;
                    out_tok   = tok_buf;
                    // prev_value: true after NUMBER or ')', false after FUNC (expects '(')
                    if (tok_buf[32]) prev_value_n = 1'b1;
                    else if (`TK_KIND(tok_buf)==K_RP) prev_value_n = 1'b1;
                    else prev_value_n = 1'b0;

                    if (!tok_buf[32] && `TK_KIND(tok_buf)==K_END) begin
                        done = 1'b1; s_n=S_IDLE;
                    end else begin
                        s_n = S_SCAN;
                    end
                end else begin
                    out_valid = 1'b1; out_tok = tok_buf;
                end
            end
            default: s_n=S_IDLE;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin s<=S_IDLE; i<=8'd0; prev_value<=1'b0; tok_buf<=33'd0;
        end else begin s<=s_n; i<=i_n; prev_value<=prev_value_n; tok_buf<=tok_buf_n; end
    end
endmodule

//=========================== SHUNTING-YARD ====================================
module shunting_yard33 #(
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
    localparam [3:0] K_OP=4'd1, K_LP=4'd2, K_RP=4'd3, K_FUNC=4'd4, K_END=4'd15;
    localparam [3:0] OP_ADD=4'd0,OP_SUB=4'd1,OP_MUL=4'd2,OP_DIV=4'd3,OP_POW=4'd4,OP_UN=4'd5;

    function [6:0] op_info; input [3:0] id; begin
        // {arity[1:0], prec[2:0], right_assoc}
        case (id)
            OP_ADD: op_info = {2'd2,3'd1,1'b0};
            OP_SUB: op_info = {2'd2,3'd1,1'b0};
            OP_MUL: op_info = {2'd2,3'd2,1'b0};
            OP_DIV: op_info = {2'd2,3'd2,1'b0};
            OP_POW: op_info = {2'd2,3'd3,1'b1};
            default: op_info= {2'd1,3'd4,1'b1}; // UN_NEG
        endcase
    end endfunction

    localparam integer WTK = 33;
    localparam integer DEP = MAX_TOKENS;
    reg [WTK*DEP-1:0] opv, opv_n;
    reg [$clog2(DEP+1)-1:0] sp, sp_n;

    reg  [32:0] hold, hold_n;
    reg         have_hold, have_hold_n;

    localparam [2:0] S_IDLE=3'd0,S_GET=3'd1,S_POP=3'd2,S_FLUSH=3'd3,S_DONE=3'd4;
    reg [2:0] s, s_n;

    wire [32:0] top = (sp==0) ? 33'd0 : opv[WTK*(sp-1) +: WTK];
    wire top_is_op  = (!top[32]) && (top[31:28]==K_OP);
    wire top_is_fn  = (!top[32]) && (top[31:28]==K_FUNC);
    wire top_is_lp  = (!top[32]) && (top[31:28]==K_LP);

    function need_pop;
        input [32:0] curr_op, stack_top;
        reg [6:0] ci, ti;
        begin
            ci = op_info(curr_op[27:24]);
            ti = op_info(stack_top[27:24]);
            if (top_is_op) begin
                if (ti[4:2] > ci[4:2])                 need_pop = 1'b1;
                else if (ti[4:2] == ci[4:2] && !ci[0]) need_pop = 1'b1;
                else                                    need_pop = 1'b0;
            end else need_pop = 1'b0;
        end
    endfunction

    always @* begin
        s_n=s; in_ready=1'b0; out_valid=1'b0; out_tok=33'd0; done=1'b0; err_flags=8'd0;
        opv_n=opv; sp_n=sp; hold_n=hold; have_hold_n=have_hold;

        case (s)
            S_IDLE: begin
                opv_n = {WTK*DEP{1'b0}}; sp_n=0; have_hold_n=1'b0;
                if (in_valid) s_n = S_GET; else in_ready=1'b1;
            end
            S_GET: begin
                if (!have_hold && in_valid) begin
                    hold_n = in_tok; have_hold_n=1'b1; in_ready=1'b1;
                    if (`TK_ISNUM(in_tok)) begin
                        if (out_ready) begin out_valid=1'b1; out_tok=in_tok; have_hold_n=1'b0; end
                        else begin out_valid=1'b1; out_tok=in_tok; end
                    end else if (`TK_KIND(in_tok)==K_LP) begin
                        opv_n[WTK*sp +: WTK] = in_tok; sp_n = sp + 1; have_hold_n=1'b0;
                    end else if (`TK_KIND(in_tok)==K_RP) begin
                        s_n = S_POP; // pop until LP
                    end else if (`TK_KIND(in_tok)==K_FUNC) begin
                        opv_n[WTK*sp +: WTK] = in_tok; sp_n = sp + 1; have_hold_n=1'b0;
                    end else if (`TK_KIND(in_tok)==K_OP) begin
                        s_n = S_POP; // precedence pop
                    end else if (`TK_KIND(in_tok)==K_END) begin
                        s_n = S_FLUSH;
                    end else begin
                        have_hold_n=1'b0;
                    end
                end else if (have_hold) begin
                    // Handle held token that's waiting for out_ready
                    if (`TK_ISNUM(hold)) begin
                        out_valid=1'b1; out_tok=hold;
                        if (out_ready) begin
                            have_hold_n=1'b0;
                        end
                    end else begin
                        // Non-number tokens shouldn't be held in S_GET, clear it
                        have_hold_n=1'b0;
                    end
                end
            end
            S_POP: begin
                if (!have_hold) s_n = S_GET;
                else begin
                    if (`TK_KIND(hold)==K_RP) begin
                        if (sp==0) begin have_hold_n=1'b0; s_n=S_GET; end
                        else if (!top_is_lp) begin
                            if (out_ready) begin out_valid=1'b1; out_tok=top; sp_n=sp-1; end
                            else begin out_valid=1'b1; out_tok=top; end
                        end else begin
                            sp_n=sp-1;
                            if (sp_n!=0 && opv[(WTK*(sp_n-1)+28)+:4]==K_FUNC) begin
                                if (out_ready) begin out_valid=1'b1; out_tok=opv[WTK*(sp_n-1)+:WTK]; sp_n=sp_n-1; end
                                else begin out_valid=1'b1; out_tok=opv[WTK*(sp_n-1)+:WTK]; end
                            end
                            have_hold_n=1'b0; s_n=S_GET;
                        end
                    end else if (`TK_KIND(hold)==K_OP) begin
                        if (sp!=0 && top_is_op && need_pop(hold, top)) begin
                            if (out_ready) begin out_valid=1'b1; out_tok=top; sp_n=sp-1; end
                            else begin out_valid=1'b1; out_tok=top; end
                        end else begin
                            opv_n[WTK*sp +: WTK] = hold; sp_n=sp+1; have_hold_n=1'b0; s_n=S_GET;
                        end
                    end else begin
                        have_hold_n=1'b0; s_n=S_GET;
                    end
                end
            end
            S_FLUSH: begin
                if (sp!=0) begin
                    if (out_ready) begin out_valid=1'b1; out_tok=opv[WTK*(sp-1)+:WTK]; sp_n=sp-1; end
                    else begin out_valid=1'b1; out_tok=opv[WTK*(sp-1)+:WTK]; end
                end else begin
                    if (out_ready) begin out_valid=1'b1; out_tok={1'b0,{K_END,4'd0,24'd0}}; done=1'b1; s_n=S_DONE; end
                    else begin out_valid=1'b1; out_tok={1'b0,{K_END,4'd0,24'd0}}; end
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
        if (rst) begin s<=S_IDLE; opv<= {WTK*DEP{1'b0}}; sp<=0; hold<=33'd0; have_hold<=1'b0;
        end else begin s<=s_n; opv<=opv_n; sp<=sp_n; hold<=hold_n; have_hold<=have_hold_n; end
    end
endmodule

//=========================== RPN EVALUATOR ====================================
module rpn_eval33 #(
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
    localparam [3:0] K_OP=4'd1, K_LP=4'd2, K_RP=4'd3, K_FUNC=4'd4, K_END=4'd15;
    localparam [3:0] OP_ADD=4'd0,OP_SUB=4'd1,OP_MUL=4'd2,OP_DIV=4'd3,OP_POW=4'd4,OP_UN=4'd5;
    localparam [3:0] FN_SIN=4'd0,FN_COS=4'd1,FN_TAN=4'd2,FN_CEIL=4'd3,FN_FLOOR=4'd4,FN_ROUND=4'd5;

    localparam integer DEP = MAX_TOKENS;
    reg [32*DEP-1:0] vv, vv_n;
    reg [$clog2(DEP+1)-1:0] sp, sp_n;

    // math units
    reg        m_start;
    reg [3:0]  m_sel;
    reg signed [31:0] a, b;

    wire signed [31:0] y_add,y_sub,y_mul,y_div,y_pow,y_sin,y_cos,y_tan,y_ceil,y_floor,y_round;
    wire r_add,r_sub,r_mul,r_div,r_pow,r_sin,r_cos,r_tan,r_ceil,r_floor,r_round;
    wire [7:0] e_add,e_sub,e_mul,e_div,e_pow,e_sin,e_cos,e_tan,e_ceil,e_floor,e_round;

    math_add_q16   U_ADD(.clk(clk),.rst(rst),.start(m_start&&(m_sel==4'd0)),.a(a),.b(b),.y(y_add),.ready(r_add),.err(e_add));
    math_sub_q16   U_SUB(.clk(clk),.rst(rst),.start(m_start&&(m_sel==4'd1)),.a(a),.b(b),.y(y_sub),.ready(r_sub),.err(e_sub));
    math_mul_q16   U_MUL(.clk(clk),.rst(rst),.start(m_start&&(m_sel==4'd2)),.a(a),.b(b),.y(y_mul),.ready(r_mul),.err(e_mul));
    math_div_q16   U_DIV(.clk(clk),.rst(rst),.start(m_start&&(m_sel==4'd3)),.a(a),.b(b),.y(y_div),.ready(r_div),.err(e_div));
    math_pow_q16   U_POW(.clk(clk),.rst(rst),.start(m_start&&(m_sel==4'd4)),.a(a),.b(b),.y(y_pow),.ready(r_pow),.err(e_pow));
    math_sin_q16   U_SIN(.clk(clk),.rst(rst),.start(m_start&&(m_sel==4'd5)),.a(a),.y(y_sin),.ready(r_sin),.err(e_sin));
    math_cos_q16   U_COS(.clk(clk),.rst(rst),.start(m_start&&(m_sel==4'd6)),.a(a),.y(y_cos),.ready(r_cos),.err(e_cos));
    math_tan_q16   U_TAN(.clk(clk),.rst(rst),.start(m_start&&(m_sel==4'd7)),.a(a),.y(y_tan),.ready(r_tan),.err(e_tan));
    math_ceil_q16  U_CEIL(.clk(clk),.rst(rst),.start(m_start&&(m_sel==4'd8)),.a(a),.y(y_ceil),.ready(r_ceil),.err(e_ceil));
    math_floor_q16 U_FLOOR(.clk(clk),.rst(rst),.start(m_start&&(m_sel==4'd9)),.a(a),.y(y_floor),.ready(r_floor),.err(e_floor));
    math_round_q16 U_ROUND(.clk(clk),.rst(rst),.start(m_start&&(m_sel==4'd10)),.a(a),.y(y_round),.ready(r_round),.err(e_round));

    // result mux + ready/err
    reg signed [31:0] y_mux;
    reg [7:0]         e_mux;
    wire              r_any = r_add|r_sub|r_mul|r_div|r_pow|r_sin|r_cos|r_tan|r_ceil|r_floor|r_round;

    always @* begin
        y_mux = 32'sd0; e_mux=8'd0;
        if (r_add)   begin y_mux=y_add;   e_mux=e_add; end
        else if(r_sub)begin y_mux=y_sub;  e_mux=e_sub; end
        else if(r_mul)begin y_mux=y_mul;  e_mux=e_mul; end
        else if(r_div)begin y_mux=y_div;  e_mux=e_div; end
        else if(r_pow)begin y_mux=y_pow;  e_mux=e_pow; end
        else if(r_sin)begin y_mux=y_sin;  e_mux=e_sin; end
        else if(r_cos)begin y_mux=y_cos;  e_mux=e_cos; end
        else if(r_tan)begin y_mux=y_tan;  e_mux=e_tan; end
        else if(r_ceil)begin y_mux=y_ceil;e_mux=e_ceil; end
        else if(r_floor)begin y_mux=y_floor; e_mux=e_floor; end
        else if(r_round)begin y_mux=y_round; e_mux=e_round; end
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
        m_start=1'b0; m_sel=4'd0; a=32'sd0; b=32'sd0;
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
                    end else if (`TK_KIND(tk)==K_OP) begin
                        s_n = S_OP;
                    end else if (`TK_KIND(tk)==K_FUNC) begin
                        if (sp<1) begin sp_n=0; have_tk_n=1'b0; // underflow -> ignore
                        end else begin
                            a = top;
                            case (`TK_ID(tk))
                                FN_SIN:   m_sel=4'd5;
                                FN_COS:   m_sel=4'd6;
                                FN_TAN:   m_sel=4'd7;
                                FN_CEIL:  m_sel=4'd8;
                                FN_FLOOR: m_sel=4'd9;
                                default:  m_sel=4'd10; // ROUND
                            endcase
                            m_start=1'b1; s_n=S_WAIT; vv_n[32*(sp-1) +: 32] = 32'sd0; sp_n=sp-1;
                        end
                    end else if (`TK_KIND(tk)==K_END) begin
                        if (sp==1) begin result=top; done=1'b1; s_n=S_DONE; end
                        else begin result=(sp!=0)?top:32'sd0; done=1'b1; s_n=S_DONE; end
                    end
                end
            end
            S_OP: begin
                if (`TK_ID(tk)==OP_UN) begin
                    if (sp<1) begin sp_n=0; have_tk_n=1'b0; s_n=S_READ; end
                    else begin
                        // negate = 0 - top
                        a = 32'sd0; b = top; m_sel=4'd1; // SUB
                        m_start=1'b1; s_n=S_WAIT; vv_n[32*(sp-1) +: 32] = 32'sd0; sp_n=sp-1;
                    end
                end else begin
                    if (sp<2) begin sp_n=0; have_tk_n=1'b0; s_n=S_READ; end
                    else begin
                        a = topm1; b = top;
                        case (`TK_ID(tk))
                            OP_ADD: m_sel=4'd0;
                            OP_SUB: m_sel=4'd1;
                            OP_MUL: m_sel=4'd2;
                            OP_DIV: m_sel=4'd3;
                            default: m_sel=4'd4; // POW
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
                    err_acc_n = err_acc | e_mux;   // accumulate errors
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
        if (rst) begin s<=S_IDLE; vv<= {32*DEP{1'b0}}; sp<=0; tk<=33'd0; have_tk<=1'b0; err_acc<=8'd0;
        end else begin s<=s_n; vv<=vv_n; sp<=sp_n; tk<=tk_n; have_tk<=have_tk_n; err_acc<=err_acc_n; end
    end
endmodule