// src/project.v
`default_nettype none

module tt_um_vga_example (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // VGA timing: 640x480 active image at one 25 MHz clock per pixel.
    wire       hsync;
    wire       vsync;
    wire       display_on;
    wire [9:0] pix_x;
    wire [9:0] pix_y;

    hvsync_generator hvsync_gen (
        .clk        (clk),
        .reset      (~rst_n),
        .hsync      (hsync),
        .vsync      (vsync),
        .display_on (display_on),
        .hpos       (pix_x),
        .vpos       (pix_y)
    );

    // Render at 320x240 logical resolution. Each logical pixel is 2x2 VGA pixels.
    // Narrower coordinate comparisons reduce combinational rendering logic.
    wire [8:0] x;
    wire [7:0] y;

    assign x = pix_x[9:1];
    assign y = pix_y[9:1];

    // ui_in[0]: start/restart.
    // ui_in[1]: reaction button.
    reg [1:0] button_meta;
    reg [1:0] button_sync;
    reg [1:0] button_prev;

    wire start_press;
    wire react_press;

    assign start_press = button_sync[0] & ~button_prev[0];
    assign react_press = button_sync[1] & ~button_prev[1];

    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_LIGHT = 3'd1;
    localparam [2:0] ST_RUN   = 3'd2;
    localparam [2:0] ST_DONE  = 3'd3;
    localparam [2:0] ST_FALSE = 3'd4;
    localparam [2:0] ST_SLOW  = 3'd5;

    // 25 MHz Playground clock: 25,000,000 clock cycles equal one second.
    localparam [24:0] LIGHT_TICKS = 25'd25000000;

    // Fixed requested target: 227 ms, displayed as MAX 227.
    localparam [3:0] MAX_HUNDREDS = 4'd2;
    localparam [3:0] MAX_TENS     = 4'd2;
    localparam [3:0] MAX_ONES     = 4'd7;

    reg [2:0]  state;
    reg [2:0]  lights_on;
    reg [24:0] light_counter;

    // Current score: S.MMM, up to 9.999 seconds.
    reg [14:0] ms_counter;
    reg [3:0]  run_seconds;
    reg [3:0]  run_hundreds;
    reg [3:0]  run_tens;
    reg [3:0]  run_ones;

    // Personal best, held until reset.
    reg [3:0] best_hundreds;
    reg [3:0] best_tens;
    reg [3:0] best_ones;
    reg       best_valid;

    wire current_is_best;

    assign current_is_best =
        (run_seconds == 4'd0) &&
        ((run_hundreds < best_hundreds) ||
         ((run_hundreds == best_hundreds) && (run_tens < best_tens)) ||
         ((run_hundreds == best_hundreds) &&
          (run_tens == best_tens) &&
          (run_ones < best_ones)));

    always @(posedge clk) begin
        if (!rst_n) begin
            button_meta   <= 2'b00;
            button_sync   <= 2'b00;
            button_prev   <= 2'b00;

            state         <= ST_IDLE;
            lights_on     <= 3'd0;
            light_counter <= 25'd0;

            ms_counter    <= 15'd0;
            run_seconds   <= 4'd0;
            run_hundreds  <= 4'd0;
            run_tens      <= 4'd0;
            run_ones      <= 4'd0;

            best_hundreds <= 4'd0;
            best_tens     <= 4'd0;
            best_ones     <= 4'd0;
            best_valid    <= 1'b0;
        end else begin
            // Synchronize only the two buttons used by this design.
            button_meta <= ui_in[1:0];
            button_sync <= button_meta;
            button_prev <= button_sync;

            // 25,000 cycles equal one millisecond at 25 MHz.
            if (state == ST_RUN) begin
                if (ms_counter == 15'd24999) begin
                    ms_counter <= 15'd0;

                    if (run_ones != 4'd9) begin
                        run_ones <= run_ones + 4'd1;
                    end else begin
                        run_ones <= 4'd0;

                        if (run_tens != 4'd9) begin
                            run_tens <= run_tens + 4'd1;
                        end else begin
                            run_tens <= 4'd0;

                            if (run_hundreds != 4'd9) begin
                                run_hundreds <= run_hundreds + 4'd1;
                            end else begin
                                run_hundreds <= 4'd0;

                                if (run_seconds != 4'd9)
                                    run_seconds <= run_seconds + 4'd1;
                            end
                        end
                    end
                end else begin
                    ms_counter <= ms_counter + 15'd1;
                end
            end else begin
                ms_counter <= 15'd0;
            end

            case (state)
                ST_IDLE: begin
                    if (start_press) begin
                        // First lamp appears immediately.
                        state         <= ST_LIGHT;
                        lights_on     <= 3'd1;
                        light_counter <= 25'd0;

                        run_seconds   <= 4'd0;
                        run_hundreds  <= 4'd0;
                        run_tens      <= 4'd0;
                        run_ones      <= 4'd0;
                    end
                end

                ST_LIGHT: begin
                    // Reaction before lamp 5 is a false start.
                    if (react_press) begin
                        state <= ST_FALSE;
                    end else if (light_counter == (LIGHT_TICKS - 25'd1)) begin
                        light_counter <= 25'd0;

                        // Lamp 5 starts the requested reaction timer.
                        if (lights_on == 3'd4) begin
                            lights_on <= 3'd5;
                            state     <= ST_RUN;
                        end else begin
                            lights_on <= lights_on + 3'd1;
                        end
                    end else begin
                        light_counter <= light_counter + 25'd1;
                    end
                end

                ST_RUN: begin
                    if (react_press) begin
                        state <= ST_DONE;

                        // Only sub-second results are stored as a best score.
                        if ((!best_valid && (run_seconds == 4'd0)) ||
                            (best_valid && current_is_best)) begin
                            best_hundreds <= run_hundreds;
                            best_tens     <= run_tens;
                            best_ones     <= run_ones;
                            best_valid    <= 1'b1;
                        end
                    end else if ((run_seconds == 4'd1) &&
                                 (run_hundreds == 4'd9) &&
                                 (run_tens == 4'd9) &&
                                 (run_ones == 4'd9)) begin
                        // Timeout at 2.000 seconds.
                        state <= ST_SLOW;
                    end
                end

                ST_DONE: begin
                    if (start_press)
                        state <= ST_IDLE;
                end

                ST_FALSE: begin
                    if (start_press)
                        state <= ST_IDLE;
                end

                ST_SLOW: begin
                    if (start_press)
                        state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    // 3x5 font rows.
    // Supported: 0-9, A, B, E, F, M, S, T, X, Y.
    function [2:0] font_row;
        input [7:0] character;
        input [2:0] row;
        begin
            font_row = 3'b000;

            case (character)
                8'h30: begin // 0
                    case (row)
                        3'd0: font_row = 3'b111;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b101;
                        3'd3: font_row = 3'b101;
                        3'd4: font_row = 3'b111;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h31: begin // 1
                    case (row)
                        3'd0: font_row = 3'b010;
                        3'd1: font_row = 3'b110;
                        3'd2: font_row = 3'b010;
                        3'd3: font_row = 3'b010;
                        3'd4: font_row = 3'b111;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h32: begin // 2
                    case (row)
                        3'd0: font_row = 3'b110;
                        3'd1: font_row = 3'b001;
                        3'd2: font_row = 3'b010;
                        3'd3: font_row = 3'b100;
                        3'd4: font_row = 3'b111;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h33: begin // 3
                    case (row)
                        3'd0: font_row = 3'b110;
                        3'd1: font_row = 3'b001;
                        3'd2: font_row = 3'b010;
                        3'd3: font_row = 3'b001;
                        3'd4: font_row = 3'b110;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h34: begin // 4
                    case (row)
                        3'd0: font_row = 3'b101;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b111;
                        3'd3: font_row = 3'b001;
                        3'd4: font_row = 3'b001;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h35: begin // 5
                    case (row)
                        3'd0: font_row = 3'b111;
                        3'd1: font_row = 3'b100;
                        3'd2: font_row = 3'b110;
                        3'd3: font_row = 3'b001;
                        3'd4: font_row = 3'b110;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h36: begin // 6
                    case (row)
                        3'd0: font_row = 3'b011;
                        3'd1: font_row = 3'b100;
                        3'd2: font_row = 3'b111;
                        3'd3: font_row = 3'b101;
                        3'd4: font_row = 3'b111;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h37: begin // 7
                    case (row)
                        3'd0: font_row = 3'b111;
                        3'd1: font_row = 3'b001;
                        3'd2: font_row = 3'b010;
                        3'd3: font_row = 3'b010;
                        3'd4: font_row = 3'b010;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h38: begin // 8
                    case (row)
                        3'd0: font_row = 3'b111;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b111;
                        3'd3: font_row = 3'b101;
                        3'd4: font_row = 3'b111;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h39: begin // 9
                    case (row)
                        3'd0: font_row = 3'b111;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b111;
                        3'd3: font_row = 3'b001;
                        3'd4: font_row = 3'b110;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h41: begin // A
                    case (row)
                        3'd0: font_row = 3'b010;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b111;
                        3'd3: font_row = 3'b101;
                        3'd4: font_row = 3'b101;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h42: begin // B
                    case (row)
                        3'd0: font_row = 3'b110;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b110;
                        3'd3: font_row = 3'b101;
                        3'd4: font_row = 3'b110;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h45: begin // E
                    case (row)
                        3'd0: font_row = 3'b111;
                        3'd1: font_row = 3'b100;
                        3'd2: font_row = 3'b110;
                        3'd3: font_row = 3'b100;
                        3'd4: font_row = 3'b111;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h46: begin // F
                    case (row)
                        3'd0: font_row = 3'b111;
                        3'd1: font_row = 3'b100;
                        3'd2: font_row = 3'b110;
                        3'd3: font_row = 3'b100;
                        3'd4: font_row = 3'b100;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h4D: begin // M
                    case (row)
                        3'd0: font_row = 3'b101;
                        3'd1: font_row = 3'b111;
                        3'd2: font_row = 3'b111;
                        3'd3: font_row = 3'b101;
                        3'd4: font_row = 3'b101;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h53: begin // S
                    case (row)
                        3'd0: font_row = 3'b111;
                        3'd1: font_row = 3'b100;
                        3'd2: font_row = 3'b111;
                        3'd3: font_row = 3'b001;
                        3'd4: font_row = 3'b111;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h54: begin // T
                    case (row)
                        3'd0: font_row = 3'b111;
                        3'd1: font_row = 3'b010;
                        3'd2: font_row = 3'b010;
                        3'd3: font_row = 3'b010;
                        3'd4: font_row = 3'b010;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h58: begin // X
                    case (row)
                        3'd0: font_row = 3'b101;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b010;
                        3'd3: font_row = 3'b101;
                        3'd4: font_row = 3'b101;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h59: begin // Y
                    case (row)
                        3'd0: font_row = 3'b101;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b010;
                        3'd3: font_row = 3'b010;
                        3'd4: font_row = 3'b010;
                        default: font_row = 3'b000;
                    endcase
                end
                default: font_row = 3'b000;
            endcase
        end
    endfunction

    // Small 3x5 glyph: 6x10 logical pixels.
    function label_pixel;
        input [8:0] px;
        input [7:0] py;
        input [8:0] base_x;
        input [7:0] base_y;
        input [7:0] character;
        reg [8:0] dx;
        reg [7:0] dy;
        reg [2:0] row;
        reg [1:0] col;
        reg [2:0] bitmap_row;
        begin
            label_pixel = 1'b0;

            if ((px >= base_x) && (px < (base_x + 9'd6)) &&
                (py >= base_y) && (py < (base_y + 8'd10))) begin

                dx = px - base_x;
                dy = py - base_y;

                if (dx < 9'd2)
                    col = 2'd0;
                else if (dx < 9'd4)
                    col = 2'd1;
                else
                    col = 2'd2;

                if (dy < 8'd2)
                    row = 3'd0;
                else if (dy < 8'd4)
                    row = 3'd1;
                else if (dy < 8'd6)
                    row = 3'd2;
                else if (dy < 8'd8)
                    row = 3'd3;
                else
                    row = 3'd4;

                bitmap_row = font_row(character, row);
                label_pixel = bitmap_row[2 - col];
            end
        end
    endfunction

    // Large 3x5 digit: 12x20 logical pixels.
    function digit_pixel;
        input [8:0] px;
        input [7:0] py;
        input [8:0] base_x;
        input [7:0] base_y;
        input [3:0] digit;
        reg [8:0] dx;
        reg [7:0] dy;
        reg [2:0] row;
        reg [1:0] col;
        reg [2:0] bitmap_row;
        reg [7:0] character;
        begin
            digit_pixel = 1'b0;
            character = 8'h30 + {4'd0, digit};

            if ((px >= base_x) && (px < (base_x + 9'd12)) &&
                (py >= base_y) && (py < (base_y + 8'd20))) begin

                dx = px - base_x;
                dy = py - base_y;

                if (dx < 9'd4)
                    col = 2'd0;
                else if (dx < 9'd8)
                    col = 2'd1;
                else
                    col = 2'd2;

                if (dy < 8'd4)
                    row = 3'd0;
                else if (dy < 8'd8)
                    row = 3'd1;
                else if (dy < 8'd12)
                    row = 3'd2;
                else if (dy < 8'd16)
                    row = 3'd3;
                else
                    row = 3'd4;

                bitmap_row = font_row(character, row);
                digit_pixel = bitmap_row[2 - col];
            end
        end
    endfunction

    function lamp_box;
        input [8:0] px;
        input [7:0] py;
        input [8:0] base_x;
        begin
            lamp_box = (px >= base_x) &&
                       (px < (base_x + 9'd42)) &&
                       (py >= 8'd45) &&
                       (py < 8'd75);
        end
    endfunction

    function lamp_inner;
        input [8:0] px;
        input [7:0] py;
        input [8:0] base_x;
        begin
            lamp_inner = (px >= (base_x + 9'd6)) &&
                         (px < (base_x + 9'd36)) &&
                         (py >= 8'd50) &&
                         (py < 8'd70);
        end
    endfunction

    reg [1:0] red;
    reg [1:0] green;
    reg [1:0] blue;
    reg       lamp_here;
    reg       lamp_is_red;
    reg       text_here;
    reg       dot_here;

    always @* begin
        // Black base colour. RGB uses black, white and red only.
        red         = 2'b00;
        green       = 2'b00;
        blue        = 2'b00;
        lamp_here   = 1'b0;
        lamp_is_red = 1'b0;
        text_here   = 1'b0;
        dot_here    = 1'b0;

        // Top status stripe.
        if (y < 8'd4) begin
            if (state == ST_RUN) begin
                red   = 2'b11;
                green = 2'b00;
                blue  = 2'b00;
            end else begin
                red   = 2'b11;
                green = 2'b11;
                blue  = 2'b11;
            end
        end

        // Compact heading: F1.
        text_here =
            label_pixel(x, y, 9'd148, 8'd14, 8'h46) | // F
            label_pixel(x, y, 9'd156, 8'd14, 8'h31);  // 1

        if (text_here) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // Five white-bordered black lamp housings.
        if (lamp_box(x, y, 9'd36)  ||
            lamp_box(x, y, 9'd92)  ||
            lamp_box(x, y, 9'd148) ||
            lamp_box(x, y, 9'd204) ||
            lamp_box(x, y, 9'd260)) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        if ((y >= 8'd47) && (y < 8'd73)) begin
            if (lamp_box(x, y, 9'd36)  ||
                lamp_box(x, y, 9'd92)  ||
                lamp_box(x, y, 9'd148) ||
                lamp_box(x, y, 9'd204) ||
                lamp_box(x, y, 9'd260)) begin
                red   = 2'b00;
                green = 2'b00;
                blue  = 2'b00;
            end
        end

        // Lamp activation order.
        if (lamp_inner(x, y, 9'd36)) begin
            lamp_here   = 1'b1;
            lamp_is_red = ((state == ST_LIGHT) || (state == ST_RUN)) &&
                          (lights_on > 3'd0);
        end

        if (lamp_inner(x, y, 9'd92)) begin
            lamp_here   = 1'b1;
            lamp_is_red = ((state == ST_LIGHT) || (state == ST_RUN)) &&
                          (lights_on > 3'd1);
        end

        if (lamp_inner(x, y, 9'd148)) begin
            lamp_here   = 1'b1;
            lamp_is_red = ((state == ST_LIGHT) || (state == ST_RUN)) &&
                          (lights_on > 3'd2);
        end

        if (lamp_inner(x, y, 9'd204)) begin
            lamp_here   = 1'b1;
            lamp_is_red = ((state == ST_LIGHT) || (state == ST_RUN)) &&
                          (lights_on > 3'd3);
        end

        if (lamp_inner(x, y, 9'd260)) begin
            lamp_here   = 1'b1;
            lamp_is_red = ((state == ST_LIGHT) || (state == ST_RUN)) &&
                          (lights_on > 3'd4);
        end

        if (lamp_here) begin
            if (lamp_is_red) begin
                red   = 2'b11;
                green = 2'b00;
                blue  = 2'b00;
            end else begin
                red   = 2'b01;
                green = 2'b01;
                blue  = 2'b01;
            end
        end

        // Current time panel.
        if ((x >= 9'd105) && (x < 9'd215) &&
            (y >= 8'd94) && (y < 8'd132)) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        if ((x >= 9'd107) && (x < 9'd213) &&
            (y >= 8'd96) && (y < 8'd130)) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end

        // Current timer: S.MMM.
        text_here =
            digit_pixel(x, y, 9'd125, 8'd102, run_seconds) |
            digit_pixel(x, y, 9'd145, 8'd102, run_hundreds) |
            digit_pixel(x, y, 9'd159, 8'd102, run_tens) |
            digit_pixel(x, y, 9'd173, 8'd102, run_ones);

        dot_here = (x >= 9'd139) && (x < 9'd143) &&
                   (y >= 8'd117) && (y < 8'd121);

        if (text_here || dot_here) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // BEST row: label and three milliseconds only.
        if ((x >= 9'd72) && (x < 9'd248) &&
            (y >= 8'd150) && (y < 8'd174)) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        if ((x >= 9'd74) && (x < 9'd246) &&
            (y >= 8'd152) && (y < 8'd172)) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end

        text_here =
            label_pixel(x, y, 9'd82, 8'd157, 8'h42) | // B
            label_pixel(x, y, 9'd90, 8'd157, 8'h45) | // E
            label_pixel(x, y, 9'd98, 8'd157, 8'h53) | // S
            label_pixel(x, y, 9'd106, 8'd157, 8'h54);  // T

        if (text_here) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        if (best_valid) begin
            text_here =
                digit_pixel(x, y, 9'd184, 8'd152, best_hundreds) |
                digit_pixel(x, y, 9'd198, 8'd152, best_tens) |
                digit_pixel(x, y, 9'd212, 8'd152, best_ones);
        end else begin
            text_here = 1'b0;
        end

        if (text_here) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // MAX row: red border and three-digit 227 target.
        if ((x >= 9'd72) && (x < 9'd248) &&
            (y >= 8'd184) && (y < 8'd208)) begin
            red   = 2'b11;
            green = 2'b00;
            blue  = 2'b00;
        end

        if ((x >= 9'd74) && (x < 9'd246) &&
            (y >= 8'd186) && (y < 8'd206)) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end

        text_here =
            label_pixel(x, y, 9'd82, 8'd191, 8'h4D) | // M
            label_pixel(x, y, 9'd90, 8'd191, 8'h41) | // A
            label_pixel(x, y, 9'd98, 8'd191, 8'h58);  // X

        if (text_here) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        text_here =
            digit_pixel(x, y, 9'd184, 8'd186, MAX_HUNDREDS) |
            digit_pixel(x, y, 9'd198, 8'd186, MAX_TENS) |
            digit_pixel(x, y, 9'd212, 8'd186, MAX_ONES);

        if (text_here) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // Compact false-start / timeout state markers.
        if (state == ST_FALSE) begin
            if ((x >= 9'd140) && (x < 9'd180) &&
                (y >= 8'd84) && (y < 8'd88)) begin
                red   = 2'b11;
                green = 2'b00;
                blue  = 2'b00;
            end
        end

        if (state == ST_SLOW) begin
            if ((x >= 9'd140) && (x < 9'd180) &&
                (y >= 8'd84) && (y < 8'd88)) begin
                red   = 2'b11;
                green = 2'b11;
                blue  = 2'b11;
            end
        end

        // VGA blanking is always black.
        if (!display_on) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end
    end

    // TinyVGA PMOD order: R1 G1 B1 VSYNC R0 G0 B0 HSYNC.
    assign uo_out  = {hsync, blue[0], green[0], red[0],
                      vsync, blue[1], green[1], red[1]};
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    wire unused;
    assign unused = &{ena, uio_in, 1'b0};

endmodule


// Embedded to keep this submission as one complete Verilog file.
module hvsync_generator (
    input  wire       clk,
    input  wire       reset,
    output wire       hsync,
    output wire       vsync,
    output wire       display_on,
    output wire [9:0] hpos,
    output wire [9:0] vpos
);

    reg [9:0] hcount;
    reg [9:0] vcount;

    always @(posedge clk) begin
        if (reset) begin
            hcount <= 10'd0;
            vcount <= 10'd0;
        end else begin
            if (hcount == 10'd799) begin
                hcount <= 10'd0;

                if (vcount == 10'd524)
                    vcount <= 10'd0;
                else
                    vcount <= vcount + 10'd1;
            end else begin
                hcount <= hcount + 10'd1;
            end
        end
    end

    assign hpos = hcount;
    assign vpos = vcount;

    // 640 active + 16 front porch + 96 active-low sync + 48 back porch.
    assign hsync = !((hcount >= 10'd656) && (hcount < 10'd752));

    // 480 active + 10 front porch + 2 active-low sync + 33 back porch.
    assign vsync = !((vcount >= 10'd490) && (vcount < 10'd492));

    assign display_on = (hcount < 10'd640) && (vcount < 10'd480);

endmodule
