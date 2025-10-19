// button_debouncer.v
// Debounce + WM_CHAR-like auto-repeat
// - One pulse on press
// - After REPEAT_START, pulses every REPEAT_INTERVAL while held
// - Parameterized by clock/intervals
module button_debouncer #(
    // Clock and timing parameters
    parameter integer CLK_HZ             = 100_000_000,
    parameter integer DEBOUNCE_MS        = 20,           // mechanical debounce window
    parameter integer REPEAT_START_MS    = 500,          // delay before auto-repeat begins
    parameter integer REPEAT_INTERVAL_MS = 50            // period between repeat pulses
) (
    input  wire clk,
    input  wire rst,         // sync reset, active-high
    input  wire btn_in_raw,  // raw button (bounce-y)
    output reg  pressed,     // debounced level (1 while held)
    output reg  char_pulse   // WM_CHAR-like pulse (1 clk wide)
);

  // ---------------------------------------------------------------------------
  // Derived constants (sized counters)
  // ---------------------------------------------------------------------------
  localparam integer ONE_MS_CLKS = (CLK_HZ / 1000);
  localparam integer DB_CLKS = (DEBOUNCE_MS < 1) ? 1 : (ONE_MS_CLKS * DEBOUNCE_MS);
  localparam integer RPT_START = (REPEAT_START_MS < 1) ? 1 : (ONE_MS_CLKS * REPEAT_START_MS);
  localparam integer RPT_INTERVAL = (REPEAT_INTERVAL_MS < 1) ? 1 : (ONE_MS_CLKS * REPEAT_INTERVAL_MS);

  localparam integer DBW = (DB_CLKS > 1) ? $clog2(DB_CLKS + 1) : 1;
  localparam integer RSW = (RPT_START > 1) ? $clog2(RPT_START + 1) : 1;
  localparam integer RIW = (RPT_INTERVAL > 1) ? $clog2(RPT_INTERVAL + 1) : 1;

  // ---------------------------------------------------------------------------
  // 2-FF synchronizer + optional inversion to get a clean sampled button
  // ---------------------------------------------------------------------------
  reg s0, s1;
  always @(posedge clk) begin
    if (rst) begin
      s0 <= 1'b0;
      s1 <= 1'b0;
    end else begin
      s0 <= btn_in_raw;
      s1 <= s0;
    end
  end
  wire           btn_sync = s1;

  // ---------------------------------------------------------------------------
  // Debounce: require the signal to stay different for DEBOUNCE_MS before toggling
  // ---------------------------------------------------------------------------
  reg  [DBW-1:0] db_cnt = {DBW{1'b0}};
  reg            debounced = 1'b0;

  always @(posedge clk) begin
    if (rst) begin
      db_cnt    <= {DBW{1'b0}};
      debounced <= 1'b0;
    end else begin
      if (btn_sync != debounced) begin
        // counting stability window
        if (db_cnt == DB_CLKS[DBW-1:0]) begin
          debounced <= btn_sync;
          db_cnt    <= {DBW{1'b0}};
        end else begin
          db_cnt <= db_cnt + 1'b1;
        end
      end else begin
        db_cnt <= {DBW{1'b0}};  // stable again
      end
    end
  end

  // Expose debounced level
  always @(posedge clk) begin
    if (rst) pressed <= 1'b0;
    else pressed <= debounced;
  end

  // ---------------------------------------------------------------------------
  // WM_CHAR-like pulse generation:
  //  - rising edge -> immediate 1-cycle pulse
  //  - while held  -> after REPEAT_START, emit a pulse every REPEAT_INTERVAL
  // ---------------------------------------------------------------------------
  reg           pressed_d;  // for edge detect
  reg [RSW-1:0] rpt_start_cnt;  // initial delay
  reg [RIW-1:0] rpt_int_cnt;  // interval counter
  reg           in_repeat_phase;  // 0 until initial delay elapsed

  always @(posedge clk) begin
    if (rst) begin
      pressed_d       <= 1'b0;
      char_pulse      <= 1'b0;
      rpt_start_cnt   <= {RSW{1'b0}};
      rpt_int_cnt     <= {RIW{1'b0}};
      in_repeat_phase <= 1'b0;
    end else begin
      pressed_d  <= pressed;
      char_pulse <= 1'b0;  // default

      // Rising edge -> immediate pulse, reset repeat machinery
      if (pressed && !pressed_d) begin
        char_pulse      <= 1'b1;
        rpt_start_cnt   <= {RSW{1'b0}};
        rpt_int_cnt     <= {RIW{1'b0}};
        in_repeat_phase <= 1'b0;
      end  // Held
      else if (pressed) begin
        if (!in_repeat_phase) begin
          // Wait initial repeat start
          if (rpt_start_cnt >= RPT_START[RSW-1:0]) begin
            in_repeat_phase <= 1'b1;
            rpt_int_cnt     <= {RIW{1'b0}};
            // (no pulse this cycle; first repeat will be after interval)
          end else begin
            rpt_start_cnt <= rpt_start_cnt + 1'b1;
          end
        end else begin
          // Repeat at fixed interval
          if (rpt_int_cnt >= RPT_INTERVAL[RIW-1:0]) begin
            char_pulse  <= 1'b1;
            rpt_int_cnt <= {RIW{1'b0}};
          end else begin
            rpt_int_cnt <= rpt_int_cnt + 1'b1;
          end
        end
      end  // Released -> reset counters
      else begin
        rpt_start_cnt   <= {RSW{1'b0}};
        rpt_int_cnt     <= {RIW{1'b0}};
        in_repeat_phase <= 1'b0;
      end
    end
  end

endmodule
// nav_keys: minimal wrapper around 5 debouncers
module nav_keys #(
    parameter CLK_HZ = 100_000_000,
    DB_MS = 20,
    RPT_START_MS = 500,
    RPT_MS = 60,
    ACTIVE_LOW = 1
) (
    input  wire clk,
    input  wire rst,
    input  wire btnU,
    input  wire btnD,
    input  wire btnL,
    input  wire btnR,
    input  wire btnC,
    output wire up_p,
    output wire down_p,
    output wire left_p,
    output wire right_p,
    output wire confirm_p
);
  button_debouncer #(
      .CLK_HZ(CLK_HZ),
      .DEBOUNCE_MS(DB_MS),
      .REPEAT_START_MS(RPT_START_MS),
      .REPEAT_INTERVAL_MS(RPT_MS)
  ) u (
      .clk(clk),
      .rst(rst),
      .btn_in_raw(btnU),
      .pressed(),
      .char_pulse(up_p)
  );
  button_debouncer #(
      .CLK_HZ(CLK_HZ),
      .DEBOUNCE_MS(DB_MS),
      .REPEAT_START_MS(RPT_START_MS),
      .REPEAT_INTERVAL_MS(RPT_MS)
  ) d (
      .clk(clk),
      .rst(rst),
      .btn_in_raw(btnD),
      .pressed(),
      .char_pulse(down_p)
  );
  button_debouncer #(
      .CLK_HZ(CLK_HZ),
      .DEBOUNCE_MS(DB_MS),
      .REPEAT_START_MS(RPT_START_MS),
      .REPEAT_INTERVAL_MS(RPT_MS)
  ) l (
      .clk(clk),
      .rst(rst),
      .btn_in_raw(btnL),
      .pressed(),
      .char_pulse(left_p)
  );
  button_debouncer #(
      .CLK_HZ(CLK_HZ),
      .DEBOUNCE_MS(DB_MS),
      .REPEAT_START_MS(RPT_START_MS),
      .REPEAT_INTERVAL_MS(RPT_MS)
  ) r (
      .clk(clk),
      .rst(rst),
      .btn_in_raw(btnR),
      .pressed(),
      .char_pulse(right_p)
  );
  button_debouncer #(
      .CLK_HZ(CLK_HZ),
      .DEBOUNCE_MS(DB_MS),
      .REPEAT_START_MS(RPT_START_MS),
      .REPEAT_INTERVAL_MS(RPT_MS)
  ) c (
      .clk(clk),
      .rst(rst),
      .btn_in_raw(btnC),
      .pressed(),
      .char_pulse(confirm_p)
  );
endmodule
