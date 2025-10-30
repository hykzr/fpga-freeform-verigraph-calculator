`timescale 1ns/1ps
// ============================================================
// recv_eval_core_ns_synth.v  (synthesizable, multi-cycle FSM)
// Receiver-side integer expression evaluator (no spaces, no '=').
//
// Grammar : number (('+'|'-'|'*'|'/') number)*
// Prec    : '*' '/' > '+' '-' (left-associative)
// Unary   : leading '-' or after operator (e.g., -12+3, 5*-6)
// Div     : signed integer division, trunc toward 0
//
// Errors bits: [0]EMPTY [1]SYNTAX [2]DIV0 [3]OVF [4]STACK
//
// I/O: On a 1-cycle 'start' pulse, evaluate in_str[0..in_len-1].
//      'result' and 'errors' are valid when 'done' asserts for 1 cycle.
// ============================================================

module recv_eval_core_ns_synth #(
    parameter integer MAX_EXPR   = 64,   // max input chars (ASCII)
    parameter integer MAX_TOKENS = 32    // token / stack depth
)(
    input  wire clk,
    input  wire rst,

    input  wire                         start,    // 1-cycle pulse
    input  wire [8*MAX_EXPR-1:0]        in_str,   // char0:[7:0], char1:[15:8], ...
    input  wire [$clog2(MAX_EXPR+1)-1:0] in_len,

    output reg                          done,     // 1-cycle
    output reg  signed [31:0]           result,
    output reg  [7:0]                   errors
);

    // ---------- helpers ----------
    function [0:0] is_digit(input [7:0] c);
        is_digit = (c >= "0" && c <= "9");
    endfunction
    function [0:0] is_op(input [7:0] c);
        is_op = (c=="+" || c=="-" || c=="*" || c=="/");
    endfunction
    function [1:0] prec(input [7:0] c);
        prec = (c=="*" || c=="/") ? 2 : 1;
    endfunction

    // ---------- sanitized buffer (x/X -> *) ----------
    reg [7:0] s [0:MAX_EXPR-1];
    reg [$clog2(MAX_EXPR+1)-1:0] slen;

    // ---------- token storage ----------
    localparam [1:0] T_NUM=2'd0, T_OP=2'd1;
    reg [1:0]          t_type [0:MAX_TOKENS-1];
    reg signed [31:0]  t_val  [0:MAX_TOKENS-1];
    reg [$clog2(MAX_TOKENS+1)-1:0] tcnt;

    // ---------- shunting-yard ----------
    reg [7:0] opstk [0:MAX_TOKENS-1];
    reg [$clog2(MAX_TOKENS+1)-1:0] op_sp;

    reg [1:0]          r_type [0:MAX_TOKENS-1];
    reg signed [31:0]  r_val  [0:MAX_TOKENS-1];
    reg [$clog2(MAX_TOKENS+1)-1:0] rcnt;

    // ---------- value stack for RPN exec ----------
    reg signed [31:0] vstk [0:MAX_TOKENS-1];
    reg [$clog2(MAX_TOKENS+1)-1:0] vsp;

    // ---------- indices / temporaries ----------
    reg [$clog2(MAX_EXPR+1)-1:0]  san_pos;   // sanitize pos
    reg [$clog2(MAX_EXPR+1)-1:0]  tok_pos;   // tokenizer pos
    reg                           tok_accum; // in-number accumulation state
    reg signed [63:0]             num_acc;   // 64-bit for ovf check
    reg                           num_neg;

    reg [$clog2(MAX_TOKENS+1)-1:0] sy_pos;   // shunting-yard token index
    reg                           sy_have_op;
    reg [7:0]                     sy_opi;    // current operator in SY
    reg                           sy_drain;  // draining remaining ops

    reg [$clog2(MAX_TOKENS+1)-1:0] rpn_pos;  // RPN exec position
    reg signed [31:0]             A, B, R32;
    reg [7:0]                     OP8;
    reg signed [63:0]             WIDE;

    // ---------- FSM ----------
    localparam [3:0]
        S_IDLE   = 4'd0,
        S_SAN    = 4'd1,
        S_TOK_INIT = 4'd2,
        S_TOK_READ = 4'd3,
        S_TOK_ACC  = 4'd4,
        S_TOK_PUSH = 4'd5,
        S_SY_INIT  = 4'd6,
        S_SY_STEP  = 4'd7,
        S_SY_POP   = 4'd8,
        S_SY_DRAIN = 4'd9,
        S_RPN_INIT = 4'd10,
        S_RPN_STEP = 4'd11,
        S_OUT    = 4'd12;

    reg [3:0] st, nx;

    // ---------- state register ----------
    always @(posedge clk) begin
        if (rst) begin
            st     <= S_IDLE;
            result <= 32'sd0;
            errors <= 8'd0;
        end else begin
            st     <= nx;
        end
    end

    // ---------- next-state ----------
    always @* begin
        nx = st;
        case (st)
            S_IDLE    : nx = start ? S_SAN : S_IDLE;
            S_SAN     : nx = S_TOK_INIT;
            S_TOK_INIT: nx = S_TOK_READ;
            S_TOK_READ: nx = (tok_pos >= slen) ? S_SY_INIT
                             : tok_accum ? S_TOK_ACC
                             : S_TOK_READ; // stay until decision flips tok_accum
            S_TOK_ACC : nx = S_TOK_PUSH;   // finish accumulation then push
            S_TOK_PUSH: nx = S_TOK_READ;
            S_SY_INIT : nx = S_SY_STEP;
            S_SY_STEP : nx = (sy_pos >= tcnt) ? S_SY_DRAIN
                             : (sy_have_op ? S_SY_POP : S_SY_STEP);
            S_SY_POP  : nx = S_SY_STEP;    // one pop per cycle
            S_SY_DRAIN: nx = (op_sp==0) ? S_RPN_INIT : S_SY_DRAIN; // drain ops
            S_RPN_INIT: nx = S_RPN_STEP;
            S_RPN_STEP: nx = (rpn_pos >= rcnt) ? S_OUT : S_RPN_STEP;
            S_OUT     : nx = S_IDLE;
            default   : nx = S_IDLE;
        endcase
    end

    // =========================================================
    // SANITIZE: copy & map 'x'/'X' -> '*'
    // =========================================================
    integer ii;
    always @(posedge clk) begin
        if (rst) begin
            slen    <= 0;
            san_pos <= 0;
        end else if (st==S_SAN) begin
            errors  <= 8'd0;
            slen    <= 0;
            // copy in one cycle using fixed bound loop
            for (ii=0; ii<MAX_EXPR; ii=ii+1) begin
                if (ii < in_len) begin
                    s[ii] <= ((in_str[8*ii +: 8] == "x") || (in_str[8*ii +: 8] == "X"))
                             ? 8'h2A /* '*' */ : in_str[8*ii +: 8];
                end else begin
                    s[ii] <= 8'd0;
                end
            end
            slen <= in_len;
            if (in_len==0) errors[0] <= 1'b1; // EMPTY
        end
    end

    // =========================================================
    // TOKENIZE: multi-cycle (one char per cycle when needed)
    // =========================================================
    always @(posedge clk) begin
        if (rst) begin
            tok_pos   <= 0;
            tcnt      <= 0;
            tok_accum <= 1'b0;
            num_acc   <= 0;
            num_neg   <= 1'b0;
        end else begin
            case (st)
                S_TOK_INIT: begin
                    tok_pos   <= 0;
                    tcnt      <= 0;
                    tok_accum <= 1'b0;
                    num_acc   <= 0;
                    num_neg   <= 1'b0;
                end
                S_TOK_READ: begin
                    if (tok_pos < slen) begin
                        // decide action for s[tok_pos]
                        if (is_digit(s[tok_pos]) ||
                            ( (s[tok_pos]=="-") &&
                              ( (tok_pos==0) || is_op(s[tok_pos-1]) ) &&
                              (tok_pos+1 < slen) && is_digit(s[tok_pos+1]) )) begin
                            // start number accumulate
                            tok_accum <= 1'b1;
                            num_acc   <= 0;
                            num_neg   <= (s[tok_pos]=="-");
                            if (s[tok_pos]=="-")
                                tok_pos <= tok_pos + 1;
                        end else if (is_op(s[tok_pos])) begin
                            // push operator token
                            if (tcnt < MAX_TOKENS) begin
                                t_type[tcnt] <= T_OP;
                                t_val [tcnt] <= {24'd0, s[tok_pos]};
                                tcnt         <= tcnt + 1;
                            end else begin
                                errors[4] <= 1'b1; // STACK/DEPTH
                            end
                            tok_pos <= tok_pos + 1;
                        end else begin
                            // invalid char
                            errors[1] <= 1'b1; // SYNTAX
                            tok_pos   <= tok_pos + 1;
                        end
                    end
                end
                S_TOK_ACC: begin
                    // accumulate exactly one digit per cycle
                    if (tok_pos < slen && is_digit(s[tok_pos])) begin
                        // acc = acc*10 + digit (64-bit to detect OVF early)
                        num_acc <= num_acc*10 + (s[tok_pos]-"0");
                        tok_pos <= tok_pos + 1;
                    end else begin
                        // finish accumulation -> push number next state
                        tok_accum <= 1'b0;
                    end
                end
                S_TOK_PUSH: begin
                    // finalize number, check ovf, store token
                    if (num_neg) num_acc <= -num_acc;
                    // overflow clamp & flag
                    if (num_acc >  32'sh7fffffff) begin
                        errors[3] <= 1'b1;
                        if (tcnt < MAX_TOKENS) begin
                            t_type[tcnt] <= T_NUM;
                            t_val [tcnt] <= 32'sh7fffffff;
                            tcnt         <= tcnt + 1;
                        end
                    end else if (num_acc < -32'sh80000000) begin
                        errors[3] <= 1'b1;
                        if (tcnt < MAX_TOKENS) begin
                            t_type[tcnt] <= T_NUM;
                            t_val [tcnt] <= -32'sh80000000;
                            tcnt         <= tcnt + 1;
                        end
                    end else begin
                        if (tcnt < MAX_TOKENS) begin
                            t_type[tcnt] <= T_NUM;
                            t_val [tcnt] <= num_acc[31:0];
                            tcnt         <= tcnt + 1;
                        end else begin
                            errors[4] <= 1'b1;
                        end
                    end
                end
            endcase
        end
    end

  // Simple start/end token check (performed once in the SY stage)
    always @(posedge clk) begin
        if (rst) begin
            // nothing
        end else if (st==S_SY_INIT) begin
            if (tcnt==0) errors[0] <= 1'b1; // EMPTY
            else begin
                if (t_type[0]==T_OP)           errors[1] <= 1'b1;
                if (t_type[tcnt-1]==T_OP)      errors[1] <= 1'b1;
            end
        end
    end

    // =========================================================
    // SHUNTING-YARD: multi-cycle (one pop per cycle)
    // =========================================================
    always @(posedge clk) begin
        if (rst) begin
            sy_pos    <= 0;
            op_sp     <= 0;
            rcnt      <= 0;
            sy_have_op<= 1'b0;
            sy_opi    <= 8'd0;
            sy_drain  <= 1'b0;
        end else begin
            case (st)
                S_SY_INIT: begin
                    sy_pos    <= 0;
                    op_sp     <= 0;
                    rcnt      <= 0;
                    sy_have_op<= 1'b0;
                    sy_opi    <= 8'd0;
                    sy_drain  <= 1'b0;
                end
                S_SY_STEP: begin
                    if (sy_pos < tcnt) begin
                        if (t_type[sy_pos]==T_NUM) begin
                            // output number directly
                            if (rcnt < MAX_TOKENS) begin
                                r_type[rcnt] <= T_NUM;
                                r_val [rcnt] <= t_val[sy_pos];
                                rcnt         <= rcnt + 1;
                            end else begin
                                errors[4] <= 1'b1;
                            end
                            sy_pos <= sy_pos + 1;
                            sy_have_op <= 1'b0;
                        end else begin
                            // operator token: set current op and go to POP
                            sy_opi    <= t_val[sy_pos][7:0];
                            sy_have_op<= 1'b1;
                        end
                    end
                end
                S_SY_POP: begin
                    // pop while (op_sp>0 && prec(top)>=prec(curr)) one per cycle
                    if (op_sp>0 && prec(opstk[op_sp-1]) >= prec(sy_opi)) begin
                        if (rcnt < MAX_TOKENS) begin
                            r_type[rcnt] <= T_OP;
                            r_val [rcnt] <= {24'd0, opstk[op_sp-1]};
                            rcnt         <= rcnt + 1;
                        end else begin
                            errors[4] <= 1'b1;
                        end
                        op_sp <= op_sp - 1;
                    end else begin
                        // push current op and advance
                        if (op_sp < MAX_TOKENS) begin
                            opstk[op_sp] <= sy_opi;
                            op_sp        <= op_sp + 1;
                        end else begin
                            errors[4] <= 1'b1;
                        end
                        sy_pos    <= sy_pos + 1;
                        sy_have_op<= 1'b0;
                    end
                end
                S_SY_DRAIN: begin
                    // drain remaining ops: one per cycle
                    if (op_sp>0) begin
                        if (rcnt < MAX_TOKENS) begin
                            r_type[rcnt] <= T_OP;
                            r_val [rcnt] <= {24'd0, opstk[op_sp-1]};
                            rcnt         <= rcnt + 1;
                        end else begin
                            errors[4] <= 1'b1;
                        end
                        op_sp <= op_sp - 1;
                    end
                end
            endcase
        end
    end

    // =========================================================
    // RPN EXECUTION: multi-cycle (one token per cycle)
    // =========================================================
    always @(posedge clk) begin
        if (rst) begin
            rpn_pos <= 0;
            vsp     <= 0;
            A       <= 0;
            B       <= 0;
            R32     <= 0;
            OP8     <= 0;
            WIDE    <= 0;
        end else begin
            case (st)
                S_RPN_INIT: begin
                    rpn_pos <= 0;
                    vsp     <= 0;
                end
                S_RPN_STEP: begin
                    if (rpn_pos < rcnt) begin
                        if (r_type[rpn_pos]==T_NUM) begin
                            if (vsp < MAX_TOKENS) begin
                                vstk[vsp] <= r_val[rpn_pos][31:0];
                                vsp       <= vsp + 1;
                            end else begin
                                errors[4] <= 1'b1;
                            end
                            rpn_pos <= rpn_pos + 1;
                        end else begin
                            // operator: need two operands
                            if (vsp < 2) begin
                                errors[1] <= 1'b1; // SYNTAX
                                rpn_pos   <= rpn_pos + 1; // skip to avoid lock
                            end else begin
                                B   <= vstk[vsp-1];
                                A   <= vstk[vsp-2];
                                OP8 <= r_val[rpn_pos][7:0];
                                // compute immediately (single-cycle ALU)
                                case (r_val[rpn_pos][7:0])
                                    "+": begin
                                        WIDE = $signed(A) + $signed(B);
                                        if (WIDE>32'sh7fffffff || WIDE<-32'sh80000000) errors[3] <= 1'b1;
                                        R32  = A + B;
                                    end
                                    "-": begin
                                        WIDE = $signed(A) - $signed(B);
                                        if (WIDE>32'sh7fffffff || WIDE<-32'sh80000000) errors[3] <= 1'b1;
                                        R32  = A - B;
                                    end
                                    "*": begin
                                        WIDE = $signed(A) * $signed(B);
                                        if (WIDE>32'sh7fffffff || WIDE<-32'sh80000000) errors[3] <= 1'b1;
                                        R32  = A * B;
                                    end
                                    "/": begin
                                        if (B==0) begin
                                            errors[2] <= 1'b1;
                                            R32  = 32'sd0;
                                        end else begin
                                            R32  = A / B; // trunc toward 0
                                        end
                                    end
                                    default: begin
                                        errors[1] <= 1'b1; // SYNTAX
                                        R32  = 32'sd0;
                                    end
                                endcase
                                // push back
                                vstk[vsp-2] <= R32;
                                vsp         <= vsp - 1;  // pop 2, push 1
                                rpn_pos     <= rpn_pos + 1;
                            end
                        end
                    end
                end
            endcase
        end
    end

    // =========================================================
    // OUT
    // =========================================================
    always @(posedge clk) begin
        if (st==S_OUT) begin
            // finalize result
            if (vsp==1) begin
                result <= vstk[0];
            end else begin
                result <= 32'sd0;
                errors[1] <= 1'b1; // residual -> SYNTAX
            end
            done <= 1'b1;
        end
        else done <= 1'b0;
    end

endmodule
