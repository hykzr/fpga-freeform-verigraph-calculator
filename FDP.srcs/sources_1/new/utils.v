module int32_to_ascii #(
    parameter integer MAX_LEN = 12
) (
    input  wire                        clk,
    input  wire                        rst,
    input  wire                        start,
    input  wire signed [         31:0] value,
    output reg                         done,
    output reg         [          7:0] out_len,
    output reg         [8*MAX_LEN-1:0] out_bus
);
  localparam S_IDLE = 0, S_MIN = 1, S_ZERO = 2, S_PREP = 3, S_DIV = 4, S_PACK = 5, S_DONE = 6;
  reg     [ 2:0] st;
  reg            neg;
  reg     [31:0] mag;
  reg     [ 3:0] dcount;
  reg     [ 7:0] digits [0:10];
  integer        i;
  localparam [8*11-1:0] MIN_STR = {
    8'h2D, 8'h32, 8'h31, 8'h34, 8'h37, 8'h34, 8'h38, 8'h33, 8'h36, 8'h34, 8'h38
  };
  task clear_bus;
    begin
      for (i = 0; i < MAX_LEN; i = i + 1) out_bus[8*i+:8] = 8'h00;
    end
  endtask

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      st <= S_IDLE;
      done <= 1'b0;
      out_len <= 8'd0;
      clear_bus();
      neg <= 1'b0;
      mag <= 32'd0;
      dcount <= 4'd0;
      for (i = 0; i < 11; i = i + 1) digits[i] <= 8'd0;
    end else begin
      done <= 1'b0;
      case (st)
        S_IDLE:
        if (start) begin
          if (value == 32'sh8000_0000) st <= S_MIN;
          else if (value == 0) st <= S_ZERO;
          else begin
            neg <= (value < 0);
            mag <= (value < 0) ? -value : value;
            dcount <= 0;
            st <= S_PREP;
          end
        end
        S_MIN: begin
          clear_bus();
          for (i = 0; i < 11; i = i + 1) out_bus[8*i+:8] <= MIN_STR[8*(11-1-i)+:8];
          out_len <= 8'd11;
          st <= S_DONE;
        end
        S_ZERO: begin
          clear_bus();
          out_bus[7:0] <= 8'h30;
          out_len <= 8'd1;
          st <= S_DONE;
        end
        S_PREP: st <= S_DIV;
        S_DIV: begin
          digits[dcount] <= 8'h30 + (mag % 10);
          mag <= mag / 10;
          dcount <= dcount + 1'b1;
          if (mag == 0) st <= S_PACK;
        end
        S_PACK: begin
          clear_bus();
          if (neg) begin
            out_bus[7:0] <= 8'h2D;
            for (i = 0; i < 11; i = i + 1)
            if (i < dcount) out_bus[8*(1+i)+:8] <= digits[dcount-1-i];
            out_len <= dcount + 8'd1;
          end else begin
            for (i = 0; i < 11; i = i + 1) if (i < dcount) out_bus[8*i+:8] <= digits[dcount-1-i];
            out_len <= dcount;
          end
          st <= S_DONE;
        end
        S_DONE: begin
          done <= 1'b1;
          st   <= S_IDLE;
        end
      endcase
    end
  end
endmodule
