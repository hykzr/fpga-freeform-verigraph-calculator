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

  // -----------------------------
  // Expression evaluator (Q16.16)
  // -----------------------------
  reg                          eval_start;
  wire signed [          31:0] eval_result;  // Q16.16 format
  wire        [           7:0] eval_error;
  wire                         eval_done;

  // Soft-reset plumbing for submodules
  reg eval_soft_rst, conv_soft_rst;
  wire eval_rst = rst | eval_soft_rst;
  wire conv_rst = rst | conv_soft_rst;

  expression_evaluator #(
      .MAX_LEN(MAX_LEN),
      .MAX_TOKENS(MAX_TOKENS)
  ) evaluator (
      .clk(clk),
      .rst(eval_rst),
      .start(eval_start),
      .expr_in(stored_expr_bus),
      .expr_len(stored_expr_len),
      .x_value(graph_x_q16_16),
      .result(eval_result),
      .error_flags(eval_error),
      .done(eval_done)
  );

  // -----------------------------
  // Q16.16 -> ASCII (3 decimals)
  // -----------------------------
  reg                         conv_start;
  wire                        conv_done;
  wire       [           7:0] conv_len;
  wire       [      8*10-1:0] conv_str_le;  // Up to 10 characters
  reg signed [          31:0] eval_result_latched;

  // Extend to MAX_DATA width for compatibility
  wire       [8*MAX_DATA-1:0] conv_bus;
  assign conv_bus = {{(8 * (MAX_DATA - 10)) {1'b0}}, conv_str_le};

  q16_to_str3 converter (
      .clk(clk),
      .rst(conv_rst),
      .start(conv_start),
      .val_q16(eval_result_latched),
      .str_le(conv_str_le),
      .str_len(conv_len),
      .done(conv_done)
  );

  // -----------------------------
  // State machine
  // -----------------------------
  localparam [2:0] S_IDLE = 3'd0, S_WAIT_EVAL = 3'd1,  // graph point evaluation
  S_CONVERT = 3'd2,  // wait eval_done for text display
  S_WAIT_CONV = 3'd3, S_LOAD = 3'd4, S_RESET = 3'd5;  // soft reset submodules before any eval/conv

  // Action after reset sequencing
  localparam [1:0]
      AR_NONE              = 2'd0,
      AR_TEXT_EVAL         = 2'd1,
      AR_GRAPH_EVAL        = 2'd2,
      AR_ENTER_GRAPH_ONLY  = 2'd3;

  localparam integer RESET_CYCLES = 2;

  reg [2:0] state;
  reg [1:0] after_reset_action;
  reg [1:0] reset_cnt;

  reg pending_compute;
  reg [7:0] req_count;
  reg graph_y_ready_internal;

  // Latch converter outputs to ensure stable values when loading
  reg [7:0] latched_conv_len;
  reg [8*MAX_DATA-1:0] latched_conv_bus;

  reg expr_has_x;

  assign graph_y_ready   = graph_y_ready_internal & ~graph_start;
  assign debug_state     = {5'd0, state};
  assign debug_req_count = req_count;

  // -----------------------------
  // Utility: detect 'x'/'X' in expr
  // -----------------------------
  function has_x_in_expr;
    input [8*MAX_DATA-1:0] bus;
    input [7:0] len;
    integer k;
    reg hit;
    begin
      hit = 1'b0;
      for (k = 0; k < MAX_DATA; k = k + 1) begin
        if (k < len) begin
          if (bus[8*k+:8] == "x") hit = 1'b1;
        end
      end
      has_x_in_expr = hit;
    end
  endfunction

  integer i;

  always @(posedge clk) begin
    if (rst) begin
      state                  <= S_IDLE;
      eval_start             <= 1'b0;
      conv_start             <= 1'b0;
      pending_compute        <= 1'b0;
      load_buf               <= 1'b0;
      load_len               <= 8'd0;
      load_bus               <= {8 * MAX_DATA{1'b0}};
      graph_mode             <= 1'b0;
      stored_expr_len        <= 8'd0;
      stored_expr_bus        <= {8 * MAX_DATA{1'b0}};
      graph_y_q16_16         <= 32'sd0;
      graph_y_valid          <= 1'b0;
      graph_y_ready_internal <= 1'b0;
      req_count              <= 8'd0;
      latched_conv_len       <= 8'd0;
      latched_conv_bus       <= {8 * MAX_DATA{1'b0}};
      eval_result_latched    <= 32'sd0;
      expr_has_x             <= 1'b0;
      eval_soft_rst          <= 1'b0;
      conv_soft_rst          <= 1'b0;
      after_reset_action     <= AR_NONE;
      reset_cnt              <= 2'd0;
    end else begin
      // Defaults each cycle
      eval_start    <= 1'b0;
      conv_start    <= 1'b0;
      load_buf      <= 1'b0;
      graph_y_valid <= 1'b0;

      // Handle clear — keep simple and non-intrusive
      if (is_clear && (state == S_IDLE || (state == S_WAIT_EVAL && graph_mode))) begin
        graph_mode             <= 1'b0;
        graph_y_ready_internal <= 1'b0;
        pending_compute        <= 1'b0;
        if (state == S_WAIT_EVAL) state <= S_IDLE;
      end

      // '=' queues a compute; do not interrupt ongoing ops
      if (is_equal) begin
        pending_compute <= 1'b1;
        if (graph_mode && state == S_IDLE) begin
          graph_mode             <= 1'b0;
          graph_y_ready_internal <= 1'b0;
        end
      end

      case (state)
        // -----------------------------------
        // IDLE: wait for '=' or graph sample
        // -----------------------------------
        S_IDLE: begin
          // New compute request?
          if (pending_compute) begin
            // Capture current expression
            stored_expr_len <= (expr_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : expr_len;
            stored_expr_bus <= expr_bus;
            expr_has_x <= has_x_in_expr(
                expr_bus, ((expr_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : expr_len)
            );
            pending_compute <= 1'b0;
            req_count <= 8'd0;

            // Prepare a clean slate: soft reset both submodules
            eval_soft_rst <= 1'b1;
            conv_soft_rst <= 1'b1;
            reset_cnt <= 2'd0;
            after_reset_action <= has_x_in_expr(
                expr_bus, ((expr_len > MAX_DATA[7:0]) ? MAX_DATA[7:0] : expr_len)
            ) ? AR_ENTER_GRAPH_ONLY : AR_TEXT_EVAL;
            state <= S_RESET;

          end else if (graph_mode) begin
            // Graph mode: wait for sample requests
            graph_y_ready_internal <= 1'b1;
            if (graph_start) begin
              // Reset before each graph evaluation to avoid stuck state
              graph_y_ready_internal <= 1'b0;
              req_count              <= req_count + 8'd1;

              eval_soft_rst          <= 1'b1;
              conv_soft_rst          <= 1'b1;  // harmless to reset converter too
              reset_cnt              <= 2'd0;
              after_reset_action     <= AR_GRAPH_EVAL;
              state                  <= S_RESET;
            end
          end
        end

        // -----------------------------------
        // Soft reset both submodules
        // -----------------------------------
        S_RESET: begin
          // Hold soft reset for a few cycles
          eval_soft_rst <= 1'b1;
          conv_soft_rst <= 1'b1;

          if (reset_cnt < (RESET_CYCLES - 1)) begin
            reset_cnt <= reset_cnt + 2'd1;
          end else begin
            // Release soft resets and perform the queued action
            eval_soft_rst <= 1'b0;
            conv_soft_rst <= 1'b0;
            reset_cnt     <= 2'd0;

            case (after_reset_action)
              AR_TEXT_EVAL: begin
                eval_start <= 1'b1;
                state      <= S_CONVERT;  // wait for eval_done then convert
              end
              AR_GRAPH_EVAL: begin
                eval_start <= 1'b1;
                state      <= S_WAIT_EVAL;  // graph point path
              end
              AR_ENTER_GRAPH_ONLY: begin
                // Enter graph mode without touching the text buffer
                graph_mode             <= 1'b1;
                graph_y_ready_internal <= 1'b1;
                state                  <= S_IDLE;
              end
              default: state <= S_IDLE;
            endcase

            after_reset_action <= AR_NONE;
          end
        end

        // -----------------------------------
        // Graph: wait for eval completion
        // -----------------------------------
        S_WAIT_EVAL: begin
          if (eval_done) begin
            graph_y_q16_16         <= eval_result;
            eval_result_latched    <= eval_result;
            graph_y_valid          <= (eval_error == 8'd0);
            graph_y_ready_internal <= 1'b1;
            state                  <= S_IDLE;
          end
        end

        // -----------------------------------
        // Text display path: wait eval, then convert
        // -----------------------------------
        S_CONVERT: begin
          if (eval_done) begin
            eval_result_latched <= eval_result;
            // (converter already soft-reset earlier)
            conv_start          <= 1'b1;
            state               <= S_WAIT_CONV;
          end
        end

        S_WAIT_CONV: begin
          if (conv_done) begin
            latched_conv_len <= conv_len;
            latched_conv_bus <= conv_bus;
            state            <= S_LOAD;
          end
        end

        // -----------------------------------
        // Load result string back into text buffer (only when no 'x')
        // -----------------------------------
        S_LOAD: begin
          load_buf   <= 1'b1;
          load_len   <= latched_conv_len;
          load_bus   <= latched_conv_bus;

          // After showing numeric result, enable graphing this expression
          graph_mode <= 1'b1;
          state      <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
