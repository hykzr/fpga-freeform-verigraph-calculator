module compute_link #(
    parameter integer CLK_HZ   = 100_000_000,
    parameter integer MAX_DATA = 32
) (
    input wire clk,
    input wire rst,

    // From input_core
    input wire                  is_equal,
    input wire                  is_clear,
    input wire [           7:0] expr_len,
    input wire [8*MAX_DATA-1:0] expr_bus,

    // To text_buffer
    output reg                  load_buf,
    output reg [           7:0] load_len,
    output reg [8*MAX_DATA-1:0] load_bus,

    // Graph interface
    input  wire               graph_start,
    input  wire signed [31:0] graph_x_q16_16,
    output reg signed  [31:0] graph_y_q16_16,
    output reg                graph_y_valid,
    output wire               graph_y_ready,
    output reg                graph_mode,

    // Debug outputs
    output wire [7:0] debug_state,
    output wire [7:0] debug_req_count
);

  // Derive internal parameters
  localparam MAX_LEN = MAX_DATA;
  localparam MAX_TOKENS = MAX_DATA / 2;

  reg         [           7:0] stored_expr_len;
  reg         [8*MAX_DATA-1:0] stored_expr_bus;

  // Expression evaluator (now returns Q16.16)
  reg                          eval_start;
  wire signed [          31:0] eval_result;  // Q16.16 format
  wire        [           7:0] eval_error;
  wire                         eval_done;

  expression_evaluator #(
      .MAX_LEN(MAX_LEN),
      .MAX_TOKENS(MAX_TOKENS)
  ) evaluator (
      .clk(clk),
      .rst(rst),
      .start(eval_start),
      .expr_in(stored_expr_bus),
      .expr_len(stored_expr_len),
      .x_value(graph_x_q16_16),
      .result(eval_result),
      .error_flags(eval_error),
      .done(eval_done)
  );

  // Q16.16 to ASCII converter (3 decimal places, trimmed)
  reg conv_start;
  wire conv_done;
  wire [7:0] conv_len;
  wire [8*10-1:0] conv_str_le;  // Up to 10 characters

  // Extend to MAX_DATA width for compatibility
  wire [8*MAX_DATA-1:0] conv_bus;
  assign conv_bus = {{(8 * (MAX_DATA - 10)) {1'b0}}, conv_str_le};

  q16_to_str3 converter (
      .clk(clk),
      .rst(rst),
      .start(conv_start),
      .val_q16(eval_result),
      .str_le(conv_str_le),
      .str_len(conv_len),
      .done(conv_done)
  );

  localparam S_IDLE = 3'd0;
  localparam S_WAIT_EVAL = 3'd1;
  localparam S_CONVERT = 3'd2;
  localparam S_WAIT_CONV = 3'd3;

  reg [2:0] state;
  reg pending_clear, pending_compute;
  reg [7:0] req_count;
  reg graph_y_ready_internal;

  assign graph_y_ready = graph_y_ready_internal & ~graph_start;
  assign debug_state = {5'd0, state};
  assign debug_req_count = req_count;

  integer i;

  always @(posedge clk) begin
    if (rst) begin
      state <= S_IDLE;
      eval_start <= 1'b0;
      conv_start <= 1'b0;
      pending_clear <= 1'b0;
      pending_compute <= 1'b0;
      load_buf <= 1'b0;
      load_len <= 8'd0;
      load_bus <= 0;
      graph_mode <= 1'b0;
      stored_expr_len <= 8'd0;
      stored_expr_bus <= 0;
      graph_y_q16_16 <= 32'sd0;
      graph_y_valid <= 1'b0;
      graph_y_ready_internal <= 1'b0;
      req_count <= 8'd0;
    end else begin
      eval_start <= 1'b0;
      conv_start <= 1'b0;
      load_buf <= 1'b0;
      graph_y_valid <= 1'b0;

      if (is_clear) begin
        pending_clear <= 1'b1;
        graph_mode <= 1'b0;
        state <= S_IDLE;
      end
      if (is_equal) pending_compute <= 1'b1;

      case (state)
        S_IDLE: begin
          if (graph_mode) begin
            graph_y_ready_internal <= 1'b1;
            if (graph_start) begin
              eval_start <= 1'b1;
              req_count <= req_count + 8'd1;
              graph_y_ready_internal <= 1'b0;
              state <= S_WAIT_EVAL;
            end
          end else if (pending_clear) begin
            pending_clear <= 1'b0;
          end else if (pending_compute) begin
            graph_mode <= 1'b1;
            stored_expr_len <= (expr_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : expr_len;
            stored_expr_bus <= expr_bus;
            pending_compute <= 1'b0;
            req_count <= 8'd0;
            graph_y_ready_internal <= 1'b1;
            // Evaluate once for display
            eval_start <= 1'b1;
            state <= S_CONVERT;
          end
        end

        S_WAIT_EVAL: begin
          if (eval_done) begin
            graph_y_q16_16 <= eval_result;
            graph_y_valid <= 1'b1;
            graph_y_ready_internal <= 1'b1;
            state <= S_IDLE;
          end
        end

        S_CONVERT: begin
          if (eval_done) begin
            conv_start <= 1'b1;
            state <= S_WAIT_CONV;
          end
        end

        S_WAIT_CONV: begin
          if (conv_done) begin
            load_buf <= 1'b1;
            load_len <= conv_len;
            load_bus <= conv_bus;
            state <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
