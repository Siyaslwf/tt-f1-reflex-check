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
        input [8:0] px
