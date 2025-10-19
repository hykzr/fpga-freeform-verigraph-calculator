// constants.vf  — immutable constants & enums only
`ifndef EE2026_CONSTANTS_VF
`define EE2026_CONSTANTS_VF

// ---- Display geometry (SSD1331/96x64) ----
`define DISP_W 96
`define DISP_H 64

// ---- Theme (RGB565) ----
`define C_BG     16'h0000
`define C_BTN    16'h39E7
`define C_FOCUS  16'hFFE0
`define C_TEXT   16'hFFFF
`define C_BORDER 16'h0841

// ---- Operators (3 bits) ----
`define OP_NONE 3'd0
`define OP_ADD  3'd1
`define OP_SUB  3'd2
`define OP_MUL  3'd3
`define OP_DIV  3'd4

// ---- Input error flags (4 bits) ----
`define ERR_NONE         4'b0000
`define ERR_EMPTY        4'b0001
`define ERR_MISSING_OPER 4'b0010
`define ERR_TOO_MANY_OPS 4'b0100
`define ERR_OVERFLOW     4'b1000

// ---- Protocol CMDs (on-wire) ----
`define CMD_TEXT  8'h10   // set/render text payload
`define CMD_CLEAR 8'h11   // clear remote display/buffer
`define START_BYTE  8'hAA   // set/render text payload
`define END_BYTE 8'h55   // clear remote display/buffer
`endif // EE2026_CONSTANTS_VF
