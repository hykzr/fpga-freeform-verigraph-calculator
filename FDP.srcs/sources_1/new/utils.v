module toggle_on_pulse (
    input  wire clk,        // real system clock
    input  wire rst,        // active high reset
    input  wire pulse_in,   // occasional pulse
    output reg  toggle_out  // toggled output
);

  // Step 1: synchronize the pulse input to clk domain
  reg pulse_sync_0, pulse_sync_1;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      pulse_sync_0 <= 0;
      pulse_sync_1 <= 0;
    end else begin
      pulse_sync_0 <= pulse_in;
      pulse_sync_1 <= pulse_sync_0;
    end
  end

  // Step 2: detect rising edge
  wire pulse_rise = pulse_sync_0 & ~pulse_sync_1;

  // Step 3: toggle output on pulse
  always @(posedge clk or posedge rst) begin
    if (rst) toggle_out <= 0;
    else if (pulse_rise) toggle_out <= ~toggle_out;
  end

endmodule
