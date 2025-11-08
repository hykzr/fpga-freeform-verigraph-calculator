// constants.vf  — immutable constants & enums only
`ifndef EE2026_CONSTANTS_VF
`define EE2026_CONSTANTS_VF

`define SIN_KEY   8'h80
`define COS_KEY   8'h81
`define TAN_KEY   8'h82
`define LOG_KEY   8'h83
`define LN_KEY    8'h84
`define SQRT_KEY  8'h85
`define PI_KEY    8'h86

`define ABS_KEY    8'h87
`define FLOOR_KEY  8'h88
`define CEIL_KEY   8'h89
`define ROUND_KEY  8'h8A
`define MIN_KEY    8'h8B
`define MAX_KEY    8'h8C
`define POW_KEY    8'h8D
`define BACK_KEY    8'h8E
`define XOR_KEY 8'h8F

// Special bracket glyphs for rendering
`define CEIL_L_KEY   8'h90  // ⌈
`define CEIL_R_KEY   8'h91  // ⌉
`define FLOOR_L_KEY  8'h92  // ⌊
`define FLOOR_R_KEY  8'h93  // ⌋

// ---- Display geometry (SSD1331/96x64) ----
`define DISP_W 96
`define DISP_H 64

`define TK_KIND_OP    4'd1
`define TK_KIND_LPAREN 4'd2
`define TK_KIND_RPAREN 4'd3
`define TK_KIND_FUNC  4'd4
`define TK_KIND_END   4'd15
`define TK_KIND_COMMA 4'd5

// ---- Theme (RGB565) ----
`define C_BG     16'h0000
`define C_BTN    16'h39E7
`define C_FOCUS  16'hFFE0
`define C_TEXT   16'hFFFF
`define C_BORDER 16'h0841

`define OP_ADD    4'd0
`define OP_SUB    4'd1
`define OP_MUL    4'd2
`define OP_DIV    4'd3
`define OP_POW    4'd4
`define OP_UN_NEG 4'd5
`define OP_REM    4'd6  // Remainder/modulo
`define OP_AND    4'd7  // Bitwise AND
`define OP_OR     4'd8  // Bitwise OR
`define OP_XOR    4'd9  // Bitwise XOR

`define FN_SIN    4'd0
`define FN_COS    4'd1
`define FN_TAN    4'd2
`define FN_CEIL   4'd3
`define FN_FLOOR  4'd4
`define FN_ROUND  4'd5
`define FN_SQRT   4'd6
`define FN_ABS    4'd7
`define FN_MAX    4'd8
`define FN_MIN    4'd9
`define FN_NOT    4'd10
`define FN_POW    4'd11
`define FN_LN    4'd12
`define FN_LOG    4'd13

// ---- Input error flags (4 bits) ----
`define ERR_NONE        8'h00
`define ERR_NEG_INPUT   8'h01  // sqrt of negative
`define ERR_DIV_ZERO    8'h02  // division by zero
`define ERR_SYNTAX      8'h04  // parse error
`define ERR_UNDERFLOW   8'h10  // stack underflow
`define ERR_OVERFLOW    8'h20  // arithmetic overflow/saturation

// ---- Protocol CMDs (on-wire) ----
`define CMD_TEXT  8'h10   // set/render text payload
`define CMD_CLEAR 8'h11   // clear remote display/buffer
`define CMD_COMPUTE 8'h20   // payload: ASCII expression
`define CMD_RESULT  8'h21   // payload: ASCII numeric result (for simple render)
`define CMD_GRAPH_EVAL 8'h22
`define START_BYTE  8'hAA   // set/render text payload
`define END_BYTE 8'h55   // clear remote display/buffer
`endif // EE2026_CONSTANTS_VF

`define Q16_PI    32'sd205887   // π ≈ 3.14159 in Q16.16
`define Q16_E     32'sd178145   // e ≈ 2.71828 in Q16.16
`define Q16_ONE   32'sd65536    // 1.0 in Q16.16
`define Q16_ZERO  32'sd0        // 0.0 in Q16.16

`define TO_Q16_16(x) ( (x) <<< 16 )
`define FROM_Q16_16(x) ( (x) >>> 16 )