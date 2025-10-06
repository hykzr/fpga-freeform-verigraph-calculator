`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME: 
//  STUDENT B NAME:
//  STUDENT C NAME: 
//
//////////////////////////////////////////////////////////////////////////////////

module Top_Student (
    input basys_clock,
    input btnL,
    input btnC,
    input btnR,
    input [15:0] sw,
    output [7:0] JA,  
    output [7:0] JB,  
    output [7:0] JC,
    output [6:0] seg,
    output [3:0] an,
    output dp
);

    // ===============================================
    // Shared Clock Generation
    // ===============================================
    wire clk_6p25Mhz;
    clock_divider unit_6p25m (.basys_clock(basys_clock), .m(7), .my_clock(clk_6p25Mhz));
    
    wire t1ms;
    tick_1ms u_1ms (.basys_clock(basys_clock), .tick(t1ms));
    
    // ===============================================
    // Task Selection Logic (Priority Encoding)
    // SW14=1 -> Task R (highest priority)
    // SW13=1 -> Task Q (medium priority)
    // SW12=1 -> Task P (lowest priority)
    // All switches OFF -> No task active
    // ===============================================
    wire task_R_enable = sw[14];                    // Highest priority
    wire task_Q_enable = sw[13] && !sw[14];         // Medium priority
    wire task_P_enable = sw[12] && !sw[13] && !sw[14]; // Lowest priority
    
    wire any_task_active = task_P_enable || task_Q_enable || task_R_enable;
    
    // ===============================================
    // Seven Segment Display: "S2.14"
    // Display on Basys3 board showing group ID
    // ===============================================
    Seven_Segment_Display ssd (
        .basys_clock(basys_clock),
        .seg(seg),
        .an(an),
        .dp(dp)
    );
    
    // ===============================================
    // TASK P INSTANTIATION (JC Port)
    // Active when: SW14=0, SW13=0, SW12=1
    // ===============================================
    wire [7:0] JC_internal;
    
    Subtask_P subtask_p_inst (
        .basys_clock(basys_clock),
        .clk_6p25Mhz(clk_6p25Mhz),
        .t1ms(t1ms),
        .btnL(btnL),
        .btnR(btnR),
        .enable(task_P_enable),
        .JC(JC_internal)
    );
    
    assign JC = task_P_enable ? JC_internal : 8'h00;
    
    // ===============================================
    // TASK Q INSTANTIATION (JB Port)
    // Active when: SW14=0, SW13=1, SW12=X
    // ===============================================
    wire [7:0] JB_internal;
    
    Subtask_Q subtask_q_inst (
        .basys_clock(basys_clock),
        .clk_6p25Mhz(clk_6p25Mhz),
        .btnL(btnL),
        .btnC(btnC),
        .btnR(btnR),
        .enable(task_Q_enable),
        .JB(JB_internal)
    );
    
    assign JB = task_Q_enable ? JB_internal : 8'h00;
    
    // ===============================================
    // TASK R INSTANTIATION (JA Port)
    // Active when: SW14=1, SW13=X, SW12=X
    // ===============================================
    wire [7:0] JA_internal;
    
    Subtask_R subtask_r_inst (
        .basys_clock(basys_clock),
        .clk_6p25Mhz(clk_6p25Mhz),
        .sw(sw),
        .enable(task_R_enable),
        .JA(JA_internal)
    );
    
    assign JA = task_R_enable ? JA_internal : 8'h00;
    
endmodule

// ===============================================
// Seven Segment Display Module: Shows "S2.14"
// ===============================================
module Seven_Segment_Display (
    input basys_clock,
    output reg [6:0] seg,
    output reg [3:0] an,
    output reg dp
);
    // Refresh counter for multiplexing
    // 100MHz / 250000 = 400Hz refresh rate for full cycle (4 digits)
    // Each digit displays at 100Hz (well within persistence of vision)
    reg [17:0] refresh_counter = 0;
    wire [1:0] digit_select;
    
    always @(posedge basys_clock) begin
        refresh_counter <= refresh_counter + 1;
    end
    
    // Cycle through digits every ~2.5ms (400Hz for all 4 digits)
    assign digit_select = refresh_counter[17:16];
    
    // Digit patterns for "S2.14"
    // Display: [S] [2.] [1] [4]
    // Anodes:  AN3 AN2  AN1 AN0
    
    always @(*) begin
        case (digit_select)
            2'b00: begin // AN0 (rightmost): "4"
                an = 4'b1110;
                seg = 7'b0011001; // 4
                dp = 1'b1; // DP off
            end
            2'b01: begin // AN1: "1"
                an = 4'b1101;
                seg = 7'b1111001; // 1
                dp = 1'b1; // DP off
            end
            2'b10: begin // AN2: "2" with decimal point
                an = 4'b1011;
                seg = 7'b0100100; // 2
                dp = 1'b0; // DP ON (shows as "2.")
            end
            2'b11: begin // AN3 (leftmost): "S"
                an = 4'b0111;
                seg = 7'b0010010; // S (same as 5)
                dp = 1'b1; // DP off
            end
        endcase
    end
endmodule

// ===============================================
// SUBTASK P MODULE: Seven-segment digits 8 and 2
// ===============================================
module Subtask_P (
    input basys_clock,
    input clk_6p25Mhz,
    input t1ms,
    input btnL,
    input btnR,
    input enable,
    output [7:0] JC
);
    wire fb_p, samp_pix_p, send_pix_p;
    reg [15:0] oled_colour_p;
    wire [12:0] pixel_index_p;
    wire [6:0] x_p = pixel_index_p % 96;
    wire [5:0] y_p = pixel_index_p / 96;
    
    localparam [3:0] DIG_LEFT_P = 4'd8;
    localparam [3:0] DIG_RIGHT_P = 4'd2;
    localparam integer H_P=48, W_P=28, TH_P=6;
    localparam integer L_X0_P = (96/2 - W_P - 4);
    localparam integer L_Y0_P = (64 - H_P)/2;
    localparam integer R_X0_P = (96/2 + 4);
    localparam integer R_Y0_P = (64 - H_P)/2;
    localparam integer CX_P = 8, CY_P = 8, R_P = 5;
    
    localparam [15:0] C_BLACK_P=16'h0000, C_WHITE_P=16'hFFFF,
                      C_RED_P=16'hF800, C_GREEN_P=16'h07E0,
                      C_PINK_P=16'hF81F;
    
    reg show_left_p = 1'b1;
    reg show_right_p = 1'b1;
    
    wire btnL_pulse_p, btnR_pulse_p;
    wire l_level_p, r_level_p;
    
    debouncer_tick db_left_p (
        .basys_clock(basys_clock),
        .tick_1ms(t1ms),
        .btn(btnL),
        .btn_level(l_level_p),
        .btn_pulse(btnL_pulse_p)
    );
    
    debouncer_tick db_right_p (
        .basys_clock(basys_clock),
        .tick_1ms(t1ms),
        .btn(btnR),
        .btn_level(r_level_p),
        .btn_pulse(btnR_pulse_p)
    );
    
    always @(posedge basys_clock) begin
        if (enable && btnL_pulse_p) show_left_p <= ~show_left_p;
        if (enable && btnR_pulse_p) show_right_p <= ~show_right_p;
    end
    
    wire any_pressed_p = l_level_p | r_level_p;
    
    function automatic in_rect_p;
        input [6:0] xx; input [5:0] yy;
        input integer x0,y0,x1,y1;
        begin
            in_rect_p = (xx>=x0 && xx<x1 && yy>=y0 && yy<y1);
        end
    endfunction
    
    function automatic [6:0] segmask_p;
        input [3:0] d;
        begin
            case (d)
                4'd0: segmask_p=7'b1011111;
                4'd1: segmask_p=7'b0000101;
                4'd2: segmask_p=7'b1110110;
                4'd3: segmask_p=7'b1110101;
                4'd4: segmask_p=7'b0101101;
                4'd5: segmask_p=7'b1111001;
                4'd6: segmask_p=7'b1111011;
                4'd7: segmask_p=7'b1000101;
                4'd8: segmask_p=7'b1111111;
                4'd9: segmask_p=7'b1111101;
                default: segmask_p=7'b0000000;
            endcase
        end
    endfunction
    
    function automatic seg_on_p;
        input [6:0] xx; input [5:0] yy;
        input integer x0,y0; input [6:0] mask;
        integer x1,y1,mid0,mid1;
        reg top,mid,bot,lt,lb,rt,rb;
        begin
            x1=x0+W_P; y1=y0+H_P;
            mid0=y0+(H_P/2-TH_P/2); mid1=mid0+TH_P;
            top=in_rect_p(xx,yy,x0,y0,x1,y0+TH_P);
            bot=in_rect_p(xx,yy,x0,y1-TH_P,x1,y1);
            mid=in_rect_p(xx,yy, x0,mid0,x1,mid1);
            lt=in_rect_p(xx,yy,x0,y0,x0+TH_P,y0+H_P/2);
            lb=in_rect_p(xx,yy,x0,y0+H_P/2,x0+TH_P,y1);
            rt=in_rect_p(xx,yy,x1-TH_P,y0,x1,y0+H_P/2);
            rb=in_rect_p(xx,yy,x1-TH_P,y0+H_P/2,x1,y1);
            seg_on_p = (mask[6] && top) || (mask[5] && mid) || (mask[4] && bot) || 
                       (mask[3] && lt) || (mask[2] && rt) || (mask[1] && lb) || (mask[0] && rb);
        end
    endfunction
    
    always @(posedge clk_6p25Mhz) begin
        oled_colour_p <= C_BLACK_P;
        
        if (enable) begin
            if (((x_p-CX_P)*(x_p-CX_P)+(y_p-CY_P)*(y_p-CY_P)) <= (R_P*R_P))
                oled_colour_p <= any_pressed_p ? C_PINK_P : C_WHITE_P;
            
            if (show_left_p && seg_on_p(x_p,y_p,L_X0_P,L_Y0_P,segmask_p(DIG_LEFT_P)))
                oled_colour_p <= C_RED_P;
            
            if (show_right_p && seg_on_p(x_p,y_p,R_X0_P,R_Y0_P,segmask_p(DIG_RIGHT_P)))
                oled_colour_p <= C_GREEN_P;
        end
    end
    
    Oled_Display oled_p (
        .clk(clk_6p25Mhz),
        .reset(~enable),
        .frame_begin(fb_p),
        .sending_pixels(send_pix_p),
        .sample_pixel(samp_pix_p),
        .pixel_index(pixel_index_p),
        .pixel_data(oled_colour_p),
        .cs(JC[0]), .sdin(JC[1]), .sclk(JC[3]),
        .d_cn(JC[4]), .resn(JC[5]), .vccen(JC[6]), .pmoden(JC[7])
    );
endmodule

// ===============================================
// SUBTASK Q MODULE: Three color-changing squares
// ===============================================
module Subtask_Q (
    input basys_clock,
    input clk_6p25Mhz,
    input btnL,
    input btnC,
    input btnR,
    input enable,
    output [7:0] JB
);
    wire fb_q, samp_pix_q, send_pix_q;
    reg [15:0] oled_colour_q;
    wire [12:0] pixel_index_q;
    wire [6:0] x_q = pixel_index_q % 96;
    wire [5:0] y_q = pixel_index_q / 96;
    
    localparam RED_Q    = 16'hF800;
    localparam BLUE_Q   = 16'h001F;
    localparam YELLOW_Q = 16'hFFE0;
    localparam GREEN_Q  = 16'h07E0;
    localparam WHITE_Q  = 16'hFFFF;
    localparam BLACK_Q  = 16'h0000;
    localparam MAGENTA_Q = 16'hF81F;
    
    reg [2:0] left_color_state = 0;
    reg [2:0] middle_color_state = 3;
    reg [2:0] right_color_state = 1;
    
    wire btnL_pulse_q, btnC_pulse_q, btnR_pulse_q;
    
    debouncer_simple db_left_q (
        .clk(clk_6p25Mhz),
        .btn_in(btnL),
        .btn_pulse(btnL_pulse_q)
    );
    
    debouncer_simple db_center_q (
        .clk(clk_6p25Mhz),
        .btn_in(btnC),
        .btn_pulse(btnC_pulse_q)
    );
    
    debouncer_simple db_right_q (
        .clk(clk_6p25Mhz),
        .btn_in(btnR),
        .btn_pulse(btnR_pulse_q)
    );
    
    always @(posedge clk_6p25Mhz) begin
        if (enable && btnL_pulse_q) begin
            left_color_state <= (left_color_state == 4) ? 0 : left_color_state + 1;
        end
        if (enable && btnC_pulse_q) begin
            middle_color_state <= (middle_color_state == 4) ? 0 : middle_color_state + 1;
        end
        if (enable && btnR_pulse_q) begin
            right_color_state <= (right_color_state == 4) ? 0 : right_color_state + 1;
        end
    end
    
    reg [15:0] left_color, middle_color, right_color;
    
    always @(*) begin
        case(left_color_state)
            0: left_color = RED_Q;
            1: left_color = BLUE_Q;
            2: left_color = YELLOW_Q;
            3: left_color = GREEN_Q;
            4: left_color = WHITE_Q;
            default: left_color = BLACK_Q;
        endcase
    end
    
    always @(*) begin
        case(middle_color_state)
            0: middle_color = RED_Q;
            1: middle_color = BLUE_Q;
            2: middle_color = YELLOW_Q;
            3: middle_color = GREEN_Q;
            4: middle_color = WHITE_Q;
            default: middle_color = BLACK_Q;
        endcase
    end
    
    always @(*) begin
        case(right_color_state)
            0: right_color = RED_Q;
            1: right_color = BLUE_Q;
            2: right_color = YELLOW_Q;
            3: right_color = GREEN_Q;
            4: right_color = WHITE_Q;
            default: right_color = BLACK_Q;
        endcase
    end
    
    wire colors_match = (left_color_state == 4) && (middle_color_state == 1) && (right_color_state == 1);
    wire in_digit_region_q = (x_q >= 84) && (x_q <= 89) && (y_q >= 2) && (y_q <= 13);
    wire digit_pixel_q;
    
    digit_7_display d7 (
        .x(x_q - 84),
        .y(y_q - 2),
        .pixel_on(digit_pixel_q)
    );
    
    always @(*) begin
        oled_colour_q = BLACK_Q;
        
        if (enable) begin
            if (x_q >= 10 && x_q <= 29 && y_q >= 44 && y_q <= 63) begin
                oled_colour_q = left_color;
            end
            else if (x_q >= 38 && x_q <= 57 && y_q >= 44 && y_q <= 63) begin
                oled_colour_q = middle_color;
            end
            else if (x_q >= 66 && x_q <= 85 && y_q >= 44 && y_q <= 63) begin
                oled_colour_q = right_color;
            end
            else if (colors_match && in_digit_region_q && digit_pixel_q) begin
                oled_colour_q = MAGENTA_Q;
            end
        end
    end
    
    Oled_Display oled_q (
        .clk(clk_6p25Mhz),
        .reset(~enable),
        .frame_begin(fb_q),
        .sending_pixels(send_pix_q),
        .sample_pixel(samp_pix_q),
        .pixel_index(pixel_index_q),
        .pixel_data(oled_colour_q),
        .cs(JB[0]), .sdin(JB[1]), .sclk(JB[3]), .d_cn(JB[4]), 
        .resn(JB[5]), .vccen(JB[6]), .pmoden(JB[7])
    );
endmodule

// ===============================================
// SUBTASK R MODULE: Two moving "8" digits
// ===============================================
module Subtask_R (
    input basys_clock,
    input clk_6p25Mhz,
    input [15:0] sw,
    input enable,
    output [7:0] JA
);
    wire fb_r, samp_pix_r, send_pix_r;
    reg [15:0] oled_colour_r;
    wire [12:0] pixel_index_r;
    wire [6:0] x_r = pixel_index_r % 96;
    wire [5:0] y_r = pixel_index_r / 96;
    
    localparam NumberWidth = 17;
    localparam NumberHeight = 30;
    localparam Width = 96;
    localparam Height = 64;
    localparam LightBlue = 16'b00100_000100_11111;
    localparam LightOrange = 16'b11111_110000_01000;
    localparam BLACK_R = 16'h0000;
    
    wire [6:0] x0_r, y0_r;
    wire [6:0] dx1_r, dy1_r, dx2_r, dy2_r;
    wire show1_r, show2_r;
    
    assign dx1_r = x_r - x0_r;
    assign dy1_r = y_r - (Height - NumberHeight) / 2;
    assign dx2_r = x_r - (Width - NumberWidth) / 2;
    assign dy2_r = y_r - y0_r;
    
    move_x mx(.clk(basys_clock), .enable(enable && sw[1]), .x(x0_r));
    move_y my(.clk(basys_clock), .enable(enable && sw[3]), .y(y0_r));
    show_8 checker1(.dx(dx1_r), .dy(dy1_r), .show(show1_r));
    show_8 checker2(.dx(dx2_r), .dy(dy2_r), .show(show2_r));
    
    always @(posedge basys_clock) begin
        if (enable) begin
            if (show1_r) begin 
                oled_colour_r <= LightBlue; 
            end else if (show2_r) begin
                oled_colour_r <= LightOrange;
            end
            else begin
                oled_colour_r <= BLACK_R; 
            end
        end else begin
            oled_colour_r <= BLACK_R;
        end
    end
    
    Oled_Display oled_r (
        .clk(clk_6p25Mhz), 
        .reset(~enable),
        .frame_begin(fb_r), 
        .sending_pixels(send_pix_r),
        .sample_pixel(samp_pix_r), 
        .pixel_index(pixel_index_r), 
        .pixel_data(oled_colour_r), 
        .cs(JA[0]), 
        .sdin(JA[1]), 
        .sclk(JA[3]), 
        .d_cn(JA[4]), 
        .resn(JA[5]), 
        .vccen(JA[6]),
        .pmoden(JA[7])
    );
endmodule

// ===============================================
// Supporting Modules
// ===============================================

module clock_divider(input basys_clock, input [31:0] m, output reg my_clock = 0);
    reg [31:0] count = 0;
    always @(posedge basys_clock) begin
        count <= (count == m) ? 0 : count + 1;
        my_clock <= (count == 0) ? ~my_clock : my_clock;
    end
endmodule

module tick_1ms(input basys_clock, output reg tick = 1'b0);
    reg [16:0] count = 0;
    localparam integer one_ms = 99999;
    always @(posedge basys_clock) begin
        if (count == one_ms) begin
            count <= 0;
            tick <= 1'b1;
        end else begin
            count <= count + 1;
            tick <= 1'b0;
        end
    end
endmodule

module debouncer_tick(
    input basys_clock,
    input tick_1ms,
    input btn,
    output reg btn_level,
    output reg btn_pulse
);
    reg s0 = 0;
    reg s1 = 0;
    
    always @(posedge basys_clock) begin
        s0 <= btn;
        s1 <= s0;
    end
    
    reg prev = 0;
    reg pressed = 0;
    reg [7:0] wait_200ms = 0;
    
    always @(posedge basys_clock) begin
        btn_pulse <= 1'b0;
        if(tick_1ms) begin
            btn_level <= s1;
            if(!pressed && (s1 == 1'b1) && (prev==1'b0)) begin
                btn_pulse <= 1'b1;
                pressed <= 1'b1;
                wait_200ms <= 8'd200;
            end
            
            if(pressed) begin
                wait_200ms <= (wait_200ms ==0) ? 0 : (wait_200ms - 1);
                if((wait_200ms == 0) && (s1 == 1'b0)) begin
                    pressed <= 1'b0;
                end
            end
            
            prev <= s1;
        end
    end
endmodule

module debouncer_simple (
    input clk,
    input btn_in,
    output reg btn_pulse
);
    parameter IDLE = 2'b00;
    parameter PRESSED = 2'b01;
    parameter DEBOUNCE = 2'b10;
    
    reg [1:0] state = IDLE;
    reg [19:0] debounce_counter = 0;
    reg [12:0] sample_counter = 0;
    reg btn_sampled = 0;
    
    parameter SAMPLE_PERIOD = 13'd6250;
    parameter DEBOUNCE_TIME = 20'd1250000;
    
    always @(posedge clk) begin
        btn_pulse <= 0;
        
        if (sample_counter == SAMPLE_PERIOD - 1) begin
            sample_counter <= 0;
            btn_sampled <= btn_in;
        end else begin
            sample_counter <= sample_counter + 1;
        end
        
        case (state)
            IDLE: begin
                if (btn_sampled) begin
                    btn_pulse <= 1;
                    state <= DEBOUNCE;
                    debounce_counter <= 0;
                end
            end
            
            DEBOUNCE: begin
                if (debounce_counter == DEBOUNCE_TIME - 1) begin
                    debounce_counter <= 0;
                    if (btn_sampled) begin
                        state <= PRESSED;
                    end else begin
                        state <= IDLE;
                    end
                end else begin
                    debounce_counter <= debounce_counter + 1;
                end
            end
            
            PRESSED: begin
                if (!btn_sampled) begin
                    state <= IDLE;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
endmodule

module digit_7_display (
    input [6:0] x,
    input [5:0] y,
    output reg pixel_on
);
    always @(*) begin
        pixel_on = 0;
        
        if (y >= 0 && y <= 1 && x >= 0 && x <= 5) begin
            pixel_on = 1;
        end
        else if (x >= 4 && x <= 5 && y >= 2 && y <= 11) begin
            pixel_on = 1;
        end
    end
endmodule

module show_8(input [6:0] dx, dy, output show);
    localparam LineWidth = 4;
    localparam NumberWidth = 17;
    localparam NumberHeight = 30;
    localparam InnerWidth = NumberWidth - 2 * LineWidth;
    localparam InnerHeight = (NumberHeight - 3 * LineWidth) / 2;
    
    localparam InnerSquare1Top = LineWidth;
    localparam InnerSquare1Bottom = InnerSquare1Top + InnerHeight;
    localparam InnerSquare2Top = InnerSquare1Bottom + LineWidth;
    localparam InnerSquare2Bottom = InnerSquare2Top + InnerHeight;
    localparam InnerSquareLeft = LineWidth;
    localparam InnerSquareRight = InnerSquareLeft + InnerWidth;
    
    assign show = dx < NumberWidth && dy < NumberHeight 
                  && ~((dx > InnerSquareLeft && dx < InnerSquareRight)
                       &&((dy > InnerSquare1Top && dy < InnerSquare1Bottom)
                       || (dy > InnerSquare2Top && dy < InnerSquare2Bottom)));
endmodule

module move_x(input clk, enable, output reg [6:0] x = 0);
    localparam NumberWidth = 17;
    localparam Width = 96;
    localparam max = Width - NumberWidth;
    localparam total_time_second = 3;
    localparam cycle = 100_000_000 / (max / total_time_second);
    reg [$clog2(cycle) - 1:0] cnt = 0;
    reg dir = 0;
    
    always @(posedge clk) begin
        if (enable) begin
            if (cnt == cycle - 1) begin
                cnt <= 0;
                dir <= (x <= 1) ? 0 : ((x >= max - 1) ? 1 : dir);
                x <= dir ? x - 1 : x + 1;
            end else begin
                cnt <= cnt + 1;
            end
        end
    end
endmodule

module move_y(input wire clk, input wire enable, output reg [6:0] y = 0);
    localparam NumberHeight = 30;
    localparam Height = 64;
    localparam max = Height - NumberHeight;
    localparam total_time_second = 3;
    localparam cycle = 100_000_000 / (max / total_time_second);

    reg [$clog2(cycle) - 1:0] cnt = 0;
    reg dir = 0;

    always @(posedge clk) begin
        if (enable) begin
            if (cnt == cycle - 1) begin
                cnt <= 0;
                dir <= (y <= 1) ? 0 : ((y >= max - 1) ? 1 : dir);
                y <= dir ? y - 1 : y + 1;
            end else begin
                cnt <= cnt + 1;
            end
        end
    end
endmodule