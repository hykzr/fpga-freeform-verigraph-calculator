`timescale 1ns / 1ps
`include "constants.vh"

module font5x7_rom (
    input  wire [7:0] ascii,  // full 8-bit ASCII
    input  wire [2:0] row,    // 0..6
    output reg  [4:0] bits
);
  always @* begin
    bits = 5'b00000;
    case (ascii)
      "0": begin
        case (row)
          3'd0: bits = 5'b01110;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b10011;
          3'd3: bits = 5'b10101;
          3'd4: bits = 5'b11001;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b01110;
          default: bits = 5'b00000;
        endcase
      end
      "1": begin
        case (row)
          3'd0: bits = 5'b00100;
          3'd1: bits = 5'b01100;
          3'd2: bits = 5'b00100;
          3'd3: bits = 5'b00100;
          3'd4: bits = 5'b00100;
          3'd5: bits = 5'b00100;
          3'd6: bits = 5'b01110;
          default: bits = 5'b00000;
        endcase
      end
      "2": begin
        case (row)
          3'd0: bits = 5'b01110;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b00001;
          3'd3: bits = 5'b00010;
          3'd4: bits = 5'b00100;
          3'd5: bits = 5'b01000;
          3'd6: bits = 5'b11111;
          default: bits = 5'b00000;
        endcase
      end
      "3": begin
        case (row)
          3'd0: bits = 5'b11110;
          3'd1: bits = 5'b00001;
          3'd2: bits = 5'b00001;
          3'd3: bits = 5'b00110;
          3'd4: bits = 5'b00001;
          3'd5: bits = 5'b00001;
          3'd6: bits = 5'b11110;
          default: bits = 5'b00000;
        endcase
      end
      "4": begin
        case (row)
          3'd0: bits = 5'b00010;
          3'd1: bits = 5'b00110;
          3'd2: bits = 5'b01010;
          3'd3: bits = 5'b10010;
          3'd4: bits = 5'b11111;
          3'd5: bits = 5'b00010;
          3'd6: bits = 5'b00010;
          default: bits = 5'b00000;
        endcase
      end
      "5": begin
        case (row)
          3'd0: bits = 5'b11111;
          3'd1: bits = 5'b10000;
          3'd2: bits = 5'b11110;
          3'd3: bits = 5'b00001;
          3'd4: bits = 5'b00001;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b01110;
          default: bits = 5'b00000;
        endcase
      end
      "6": begin
        case (row)
          3'd0: bits = 5'b00110;
          3'd1: bits = 5'b01000;
          3'd2: bits = 5'b10000;
          3'd3: bits = 5'b11110;
          3'd4: bits = 5'b10001;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b01110;
          default: bits = 5'b00000;
        endcase
      end
      "7": begin
        case (row)
          3'd0: bits = 5'b11111;
          3'd1: bits = 5'b00001;
          3'd2: bits = 5'b00010;
          3'd3: bits = 5'b00100;
          3'd4: bits = 5'b01000;
          3'd5: bits = 5'b01000;
          3'd6: bits = 5'b01000;
          default: bits = 5'b00000;
        endcase
      end
      "8": begin
        case (row)
          3'd0: bits = 5'b01110;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b01110;
          3'd4: bits = 5'b10001;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b01110;
          default: bits = 5'b00000;
        endcase
      end
      "9": begin
        case (row)
          3'd0: bits = 5'b01110;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b01111;
          3'd4: bits = 5'b00001;
          3'd5: bits = 5'b00010;
          3'd6: bits = 5'b01100;
          default: bits = 5'b00000;
        endcase
      end
      "+": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b00100;
          3'd2: bits = 5'b00100;
          3'd3: bits = 5'b11111;
          3'd4: bits = 5'b00100;
          3'd5: bits = 5'b00100;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "-": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b00000;
          3'd2: bits = 5'b00000;
          3'd3: bits = 5'b11111;
          3'd4: bits = 5'b00000;
          3'd5: bits = 5'b00000;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "*": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b01010;
          3'd3: bits = 5'b00100;
          3'd4: bits = 5'b01010;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "/": begin
        case (row)
          3'd0: bits = 5'b00001;
          3'd1: bits = 5'b00010;
          3'd2: bits = 5'b00100;
          3'd3: bits = 5'b01000;
          3'd4: bits = 5'b10000;
          3'd5: bits = 5'b00000;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "=": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b00000;
          3'd2: bits = 5'b11111;
          3'd3: bits = 5'b00000;
          3'd4: bits = 5'b11111;
          3'd5: bits = 5'b00000;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "A": begin
        case (row)
          3'd0: bits = 5'b01110;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b11111;
          3'd4: bits = 5'b10001;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b10001;
          default: bits = 5'b00000;
        endcase
      end
      "B": begin
        case (row)
          3'd0: bits = 5'b11110;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b11110;
          3'd4: bits = 5'b10001;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b11110;
          default: bits = 5'b00000;
        endcase
      end
      "C": begin
        case (row)
          3'd0: bits = 5'b01110;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b10000;
          3'd3: bits = 5'b10000;
          3'd4: bits = 5'b10000;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b01110;
          default: bits = 5'b00000;
        endcase
      end
      "D": begin
        case (row)
          3'd0: bits = 5'b11110;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b10001;
          3'd4: bits = 5'b10001;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b11110;
          default: bits = 5'b00000;
        endcase
      end
      "E": begin
        case (row)
          3'd0: bits = 5'b11111;
          3'd1: bits = 5'b10000;
          3'd2: bits = 5'b10000;
          3'd3: bits = 5'b11110;
          3'd4: bits = 5'b10000;
          3'd5: bits = 5'b10000;
          3'd6: bits = 5'b11111;
          default: bits = 5'b00000;
        endcase
      end
      "F": begin
        case (row)
          3'd0: bits = 5'b11111;
          3'd1: bits = 5'b10000;
          3'd2: bits = 5'b10000;
          3'd3: bits = 5'b11110;
          3'd4: bits = 5'b10000;
          3'd5: bits = 5'b10000;
          3'd6: bits = 5'b10000;
          default: bits = 5'b00000;
        endcase
      end
      "a": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b01110;
          3'd2: bits = 5'b00001;
          3'd3: bits = 5'b01111;
          3'd4: bits = 5'b10001;
          3'd5: bits = 5'b01111;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "b": begin
        case (row)
          3'd0: bits = 5'b10000;
          3'd1: bits = 5'b10000;
          3'd2: bits = 5'b11110;
          3'd3: bits = 5'b10001;
          3'd4: bits = 5'b10001;
          3'd5: bits = 5'b11110;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "c": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b01110;
          3'd2: bits = 5'b10000;
          3'd3: bits = 5'b10000;
          3'd4: bits = 5'b10000;
          3'd5: bits = 5'b01110;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "d": begin
        case (row)
          3'd0: bits = 5'b00001;
          3'd1: bits = 5'b00001;
          3'd2: bits = 5'b01111;
          3'd3: bits = 5'b10001;
          3'd4: bits = 5'b10001;
          3'd5: bits = 5'b01111;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "e": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b01110;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b11111;
          3'd4: bits = 5'b10000;
          3'd5: bits = 5'b01110;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "f": begin
        case (row)
          3'd0: bits = 5'b00110;
          3'd1: bits = 5'b01001;
          3'd2: bits = 5'b01000;
          3'd3: bits = 5'b11100;
          3'd4: bits = 5'b01000;
          3'd5: bits = 5'b01000;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "g": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b01111;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b01111;
          3'd4: bits = 5'b00001;
          3'd5: bits = 5'b01110;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "h": begin
        case (row)
          3'd0: bits = 5'b10000;
          3'd1: bits = 5'b10000;
          3'd2: bits = 5'b11110;
          3'd3: bits = 5'b10001;
          3'd4: bits = 5'b10001;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "i": begin
        case (row)
          3'd0: bits = 5'b00100;
          3'd1: bits = 5'b00000;
          3'd2: bits = 5'b01100;
          3'd3: bits = 5'b00100;
          3'd4: bits = 5'b00100;
          3'd5: bits = 5'b01110;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "j": begin
        case (row)
          3'd0: bits = 5'b00010;
          3'd1: bits = 5'b00000;
          3'd2: bits = 5'b00110;
          3'd3: bits = 5'b00010;
          3'd4: bits = 5'b00010;
          3'd5: bits = 5'b10010;
          3'd6: bits = 5'b01100;
          default: bits = 5'b00000;
        endcase
      end
      "k": begin
        case (row)
          3'd0: bits = 5'b10000;
          3'd1: bits = 5'b10010;
          3'd2: bits = 5'b10100;
          3'd3: bits = 5'b11000;
          3'd4: bits = 5'b10100;
          3'd5: bits = 5'b10010;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "l": begin
        case (row)
          3'd0: bits = 5'b01100;
          3'd1: bits = 5'b00100;
          3'd2: bits = 5'b00100;
          3'd3: bits = 5'b00100;
          3'd4: bits = 5'b00100;
          3'd5: bits = 5'b01110;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "m": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b11010;
          3'd2: bits = 5'b10101;
          3'd3: bits = 5'b10101;
          3'd4: bits = 5'b10101;
          3'd5: bits = 5'b10101;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "n": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b11110;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b10001;
          3'd4: bits = 5'b10001;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "o": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b01110;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b10001;
          3'd4: bits = 5'b10001;
          3'd5: bits = 5'b01110;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "p": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b11110;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b11110;
          3'd4: bits = 5'b10000;
          3'd5: bits = 5'b10000;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "q": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b01111;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b01111;
          3'd4: bits = 5'b00001;
          3'd5: bits = 5'b00001;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "r": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b10110;
          3'd2: bits = 5'b11001;
          3'd3: bits = 5'b10000;
          3'd4: bits = 5'b10000;
          3'd5: bits = 5'b10000;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "s": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b01111;
          3'd2: bits = 5'b10000;
          3'd3: bits = 5'b01110;
          3'd4: bits = 5'b00001;
          3'd5: bits = 5'b11110;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "t": begin
        case (row)
          3'd0: bits = 5'b01000;
          3'd1: bits = 5'b01000;
          3'd2: bits = 5'b11100;
          3'd3: bits = 5'b01000;
          3'd4: bits = 5'b01001;
          3'd5: bits = 5'b00110;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "u": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b10001;
          3'd4: bits = 5'b10011;
          3'd5: bits = 5'b01101;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "v": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b01010;
          3'd4: bits = 5'b01010;
          3'd5: bits = 5'b00100;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "w": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b10101;
          3'd4: bits = 5'b11011;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "x": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b01010;
          3'd3: bits = 5'b00100;
          3'd4: bits = 5'b01010;
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "y": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b10001;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b01111;
          3'd4: bits = 5'b00001;
          3'd5: bits = 5'b01110;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "z": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b11111;
          3'd2: bits = 5'b00010;
          3'd3: bits = 5'b00100;
          3'd4: bits = 5'b01000;
          3'd5: bits = 5'b11111;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "(": begin
        case (row)
          3'd0: bits = 5'b00010;
          3'd1: bits = 5'b00100;
          3'd2: bits = 5'b01000;
          3'd3: bits = 5'b01000;
          3'd4: bits = 5'b01000;
          3'd5: bits = 5'b00100;
          3'd6: bits = 5'b00010;
          default: bits = 5'b00000;
        endcase
      end
      ")": begin
        case (row)
          3'd0: bits = 5'b01000;
          3'd1: bits = 5'b00100;
          3'd2: bits = 5'b00010;
          3'd3: bits = 5'b00010;
          3'd4: bits = 5'b00010;
          3'd5: bits = 5'b00100;
          3'd6: bits = 5'b01000;
          default: bits = 5'b00000;
        endcase
      end
      ".": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b00000;
          3'd2: bits = 5'b00000;
          3'd3: bits = 5'b00000;
          3'd4: bits = 5'b00000;
          3'd5: bits = 5'b00110;
          3'd6: bits = 5'b00110;
          default: bits = 5'b00000;
        endcase
      end
      ",": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b00000;
          3'd2: bits = 5'b00000;
          3'd3: bits = 5'b00000;
          3'd4: bits = 5'b00110;
          3'd5: bits = 5'b00110;
          3'd6: bits = 5'b01100;
          default: bits = 5'b00000;
        endcase
      end
      "<": begin
        case (row)
          3'd0: bits = 5'b00010;
          3'd1: bits = 5'b00100;
          3'd2: bits = 5'b01000;
          3'd3: bits = 5'b10000;
          3'd4: bits = 5'b01000;
          3'd5: bits = 5'b00100;
          3'd6: bits = 5'b00010;
          default: bits = 5'b00000;
        endcase
      end
      ">": begin
        case (row)
          3'd0: bits = 5'b01000;
          3'd1: bits = 5'b00100;
          3'd2: bits = 5'b00010;
          3'd3: bits = 5'b00001;
          3'd4: bits = 5'b00010;
          3'd5: bits = 5'b00100;
          3'd6: bits = 5'b01000;
          default: bits = 5'b00000;
        endcase
      end
      "^": begin
        case (row)
          3'd0: bits = 5'b00100;
          3'd1: bits = 5'b01010;
          3'd2: bits = 5'b10001;
          3'd3: bits = 5'b00000;
          3'd4: bits = 5'b00000;
          3'd5: bits = 5'b00000;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "~": begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b00000;
          3'd2: bits = 5'b01000;
          3'd3: bits = 5'b10101;
          3'd4: bits = 5'b00010;
          3'd5: bits = 5'b00000;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "&": begin
        case (row)
          3'd0: bits = 5'b00110;
          3'd1: bits = 5'b01001;
          3'd2: bits = 5'b00110;
          3'd3: bits = 5'b01100;
          3'd4: bits = 5'b10011;
          3'd5: bits = 5'b10010;
          3'd6: bits = 5'b01101;
          default: bits = 5'b00000;
        endcase
      end
      "|": begin
        case (row)
          3'd0: bits = 5'b00100;
          3'd1: bits = 5'b00100;
          3'd2: bits = 5'b00100;
          3'd3: bits = 5'b00100;
          3'd4: bits = 5'b00100;
          3'd5: bits = 5'b00100;
          3'd6: bits = 5'b00100;
          default: bits = 5'b00000;
        endcase
      end
      `PI_KEY: begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b11111;
          3'd2: bits = 5'b01010;
          3'd3: bits = 5'b01010;  // top bar
          3'd4: bits = 5'b01010;  // legs
          3'd5: bits = 5'b10001;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      `SQRT_KEY: begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b00011;
          3'd2: bits = 5'b00010;
          3'd3: bits = 5'b00010;
          3'd4: bits = 5'b00100;
          3'd5: bits = 5'b10100;
          3'd6: bits = 5'b01000;
          default: bits = 5'b00000;
        endcase
      end
      `CEIL_L_KEY: begin
        case (row)
          3'd0: bits = 5'b01111;
          3'd1: bits = 5'b01000;
          3'd2: bits = 5'b01000;
          3'd3: bits = 5'b01000;
          3'd4: bits = 5'b01000;
          3'd5: bits = 5'b01000;
          3'd6: bits = 5'b01000;
          default: bits = 5'b00000;
        endcase
      end
      `CEIL_R_KEY: begin
        case (row)
          3'd0: bits = 5'b11110;
          3'd1: bits = 5'b00010;
          3'd2: bits = 5'b00010;
          3'd3: bits = 5'b00010;
          3'd4: bits = 5'b00010;
          3'd5: bits = 5'b00010;
          3'd6: bits = 5'b00010;
          default: bits = 5'b00000;
        endcase
      end
      `FLOOR_L_KEY: begin
        case (row)
          3'd0: bits = 5'b01000;
          3'd1: bits = 5'b01000;
          3'd2: bits = 5'b01000;
          3'd3: bits = 5'b01000;
          3'd4: bits = 5'b01000;
          3'd5: bits = 5'b01000;
          3'd6: bits = 5'b01111;
          default: bits = 5'b00000;
        endcase
      end
      `FLOOR_R_KEY: begin
        case (row)
          3'd0: bits = 5'b00010;
          3'd1: bits = 5'b00010;
          3'd2: bits = 5'b00010;
          3'd3: bits = 5'b00010;
          3'd4: bits = 5'b00010;
          3'd5: bits = 5'b00010;
          3'd6: bits = 5'b11110;
          default: bits = 5'b00000;
        endcase
      end
      `BACK_KEY: begin
        case (row)
          3'd0: bits = 5'b00000;
          3'd1: bits = 5'b00100;
          3'd2: bits = 5'b01000;
          3'd3: bits = 5'b11111;
          3'd4: bits = 5'b01000;
          3'd5: bits = 5'b00100;
          3'd6: bits = 5'b00000;
          default: bits = 5'b00000;
        endcase
      end
      "%": begin
        case (row)
          3'd0: bits = 5'b11001;
          3'd1: bits = 5'b11010;
          3'd2: bits = 5'b00010;
          3'd3: bits = 5'b00100;
          3'd4: bits = 5'b01000;
          3'd5: bits = 5'b01011;
          3'd6: bits = 5'b10011;
          default: bits = 5'b00000;
        endcase
      end
      default: begin
        bits = 5'b00000;
      end
    endcase
  end
endmodule
// glyph_blitter.v — Verilog-2001
// Reports whether the current pixel (x,y) lies on a scaled 5x7 glyph placed at (gx,gy).
// - FONT_SCALE scales each font pixel to an SxS block (S = FONT_SCALE).
// - Uses font5x7_rom (ASCII -> 5-bit row pattern).
module glyph_blitter #(
    parameter integer FONT_SCALE = 2  // 1,2,3,...
) (
    input  wire [6:0] x,      // current pixel x (0..95)
    input  wire [6:0] y,      // current pixel y (0..63)
    input  wire [6:0] gx,     // glyph top-left x
    input  wire [6:0] gy,     // glyph top-left y
    input  wire [7:0] ascii,  // ASCII code to draw
    output reg        on      // 1 if this pixel is part of the glyph
);
  // Derived glyph box size
  localparam integer GLYPH_W = 5 * FONT_SCALE;
  localparam integer GLYPH_H = 7 * FONT_SCALE;

  // Local coordinates relative to glyph origin (signed to detect negatives)
  wire signed [7:0] lx = $signed({1'b0, x}) - $signed({1'b0, gx});
  wire signed [7:0] ly = $signed({1'b0, y}) - $signed({1'b0, gy});

  // Check if (x,y) is inside the scaled glyph box
  wire in_box = (lx >= 0) && (ly >= 0) && (lx < GLYPH_W) && (ly < GLYPH_H);

  // Map to 5x7 cell coordinates
  // (safe because in_box guarantees bounds)
  wire [2:0] cell_x = (in_box) ? (lx / FONT_SCALE) : 3'd0;  // 0..4
  wire [2:0] cell_y = (in_box) ? (ly / FONT_SCALE) : 3'd0;  // 0..6

  // Fetch the 5-bit row bitmap for this ASCII and row
  wire [4:0] row_bits;
  font5x7_rom u_rom (
      .ascii(ascii),
      .row  (cell_y),
      .bits (row_bits)
  );

  // Select bit: bit[4] = leftmost pixel of the 5-bit row
  always @* begin
    if (!in_box) begin
      on = 1'b0;
    end else begin
      // Guard not strictly necessary due to in_box, but safe:
      if (cell_x <= 3'd4) on = row_bits[4-cell_x];
      else on = 1'b0;
    end
  end

endmodule
