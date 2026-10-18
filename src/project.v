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

    // ui_in[0] starts a new run.
    // ui_in[1] stops the timer after light 5.
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

    // VGA Playground clock: 25 MHz.
    // 25,000,000 cycles = 1 second between lamps.
    localparam [24:0] LIGHT_TICKS = 25'd25000000;

    // Fixed requested target: 00.227.
    localparam [3:0] MAX_SEC_TENS = 4'd0;
    localparam [3:0] MAX_SEC_ONES = 4'd0;
    localparam [3:0] MAX_MS_HUNDS = 4'd2;
    localparam [3:0] MAX_MS_TENS  = 4'd2;
    localparam [3:0] MAX_MS_ONES  = 4'd7;

    reg [2:0]  state;
    reg [2:0]  lights_on;
    reg [24:0] light_counter;

    // Timer digits: SS.MMM.
    reg [14:0] ms_counter;
    reg [3:0]  run_sec_tens;
    reg [3:0]  run_sec_ones;
    reg [3:0]  run_ms_hunds;
    reg [3:0]  run_ms_tens;
    reg [3:0]  run_ms_ones;

    reg [3:0] best_sec_tens;
    reg [3:0] best_sec_ones;
    reg [3:0] best_ms_hunds;
    reg [3:0] best_ms_tens;
    reg [3:0] best_ms_ones;
    reg       best_valid;

    wire current_is_best;

    assign current_is_best =
        (run_sec_tens < best_sec_tens) ||
        ((run_sec_tens == best_sec_tens) &&
         (run_sec_ones < best_sec_ones)) ||
        ((run_sec_tens == best_sec_tens) &&
         (run_sec_ones == best_sec_ones) &&
         (run_ms_hunds < best_ms_hunds)) ||
        ((run_sec_tens == best_sec_tens) &&
         (run_sec_ones == best_sec_ones) &&
         (run_ms_hunds == best_ms_hunds) &&
         (run_ms_tens < best_ms_tens)) ||
        ((run_sec_tens == best_sec_tens) &&
         (run_sec_ones == best_sec_ones) &&
         (run_ms_hunds == best_ms_hunds) &&
         (run_ms_tens == best_ms_tens) &&
         (run_ms_ones < best_ms_ones));

    always @(posedge clk) begin
        if (!rst_n) begin
            button_meta    <= 2'b00;
            button_sync    <= 2'b00;
            button_prev    <= 2'b00;

            state          <= ST_IDLE;
            lights_on      <= 3'd0;
            light_counter  <= 25'd0;

            ms_counter     <= 15'd0;
            run_sec_tens   <= 4'd0;
            run_sec_ones   <= 4'd0;
            run_ms_hunds   <= 4'd0;
            run_ms_tens    <= 4'd0;
            run_ms_ones    <= 4'd0;

            best_sec_tens  <= 4'd0;
            best_sec_ones  <= 4'd0;
            best_ms_hunds  <= 4'd0;
            best_ms_tens   <= 4'd0;
            best_ms_ones   <= 4'd0;
            best_valid     <= 1'b0;
        end else begin
            // Synchronize the two used button inputs.
            button_meta <= ui_in[1:0];
            button_sync <= button_meta;
            button_prev <= button_sync;

            // 25,000 pixel clocks = exactly 1 ms at 25 MHz.
            if (state == ST_RUN) begin
                if (ms_counter == 15'd24999) begin
                    ms_counter <= 15'd0;

                    if (run_ms_ones != 4'd9) begin
                        run_ms_ones <= run_ms_ones + 4'd1;
                    end else begin
                        run_ms_ones <= 4'd0;

                        if (run_ms_tens != 4'd9) begin
                            run_ms_tens <= run_ms_tens + 4'd1;
                        end else begin
                            run_ms_tens <= 4'd0;

                            if (run_ms_hunds != 4'd9) begin
                                run_ms_hunds <= run_ms_hunds + 4'd1;
                            end else begin
                                run_ms_hunds <= 4'd0;

                                if (run_sec_ones != 4'd9) begin
                                    run_sec_ones <= run_sec_ones + 4'd1;
                                end else begin
                                    run_sec_ones <= 4'd0;

                                    if (run_sec_tens != 4'd9)
                                        run_sec_tens <= run_sec_tens + 4'd1;
                                end
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
                        // First lamp turns on at once.
                        state         <= ST_LIGHT;
                        lights_on     <= 3'd1;
                        light_counter <= 25'd0;

                        run_sec_tens  <= 4'd0;
                        run_sec_ones  <= 4'd0;
                        run_ms_hunds  <= 4'd0;
                        run_ms_tens   <= 4'd0;
                        run_ms_ones   <= 4'd0;
                    end
                end

                ST_LIGHT: begin
                    // Button press before lamp 5 is a false start.
                    if (react_press) begin
                        state <= ST_FALSE;
                    end else if (light_counter == (LIGHT_TICKS - 25'd1)) begin
                        light_counter <= 25'd0;

                        // Lamp 5 turns red and starts the timer immediately.
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

                        if (!best_valid || current_is_best) begin
                            best_sec_tens <= run_sec_tens;
                            best_sec_ones <= run_sec_ones;
                            best_ms_hunds <= run_ms_hunds;
                            best_ms_tens  <= run_ms_tens;
                            best_ms_ones  <= run_ms_ones;
                            best_valid    <= 1'b1;
                        end
                    end else if ((run_sec_tens == 4'd0) &&
                                 (run_sec_ones == 4'd1) &&
                                 (run_ms_hunds == 4'd9) &&
                                 (run_ms_tens == 4'd9) &&
                                 (run_ms_ones == 4'd9)) begin
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

    // 3x5 font rows for digits and required uppercase letters.
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
                8'h4C: begin // L
                    case (row)
                        3'd0: font_row = 3'b100;
                        3'd1: font_row = 3'b100;
                        3'd2: font_row = 3'b100;
                        3'd3: font_row = 3'b100;
                        3'd4: font_row = 3'b111;
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
                8'h4E: begin // N
                    case (row)
                        3'd0: font_row = 3'b101;
                        3'd1: font_row = 3'b111;
                        3'd2: font_row = 3'b111;
                        3'd3: font_row = 3'b111;
                        3'd4: font_row = 3'b101;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h4F: begin // O
                    case (row)
                        3'd0: font_row = 3'b111;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b101;
                        3'd3: font_row = 3'b101;
                        3'd4: font_row = 3'b111;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h50: begin // P
                    case (row)
                        3'd0: font_row = 3'b110;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b110;
                        3'd3: font_row = 3'b100;
                        3'd4: font_row = 3'b100;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h52: begin // R
                    case (row)
                        3'd0: font_row = 3'b110;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b110;
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
                8'h55: begin // U
                    case (row)
                        3'd0: font_row = 3'b101;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b101;
                        3'd3: font_row = 3'b101;
                        3'd4: font_row = 3'b111;
                        default: font_row = 3'b000;
                    endcase
                end
                8'h56: begin // V
                    case (row)
                        3'd0: font_row = 3'b101;
                        3'd1: font_row = 3'b101;
                        3'd2: font_row = 3'b101;
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

    function label_pixel;
        input [9:0] px;
        input [9:0] py;
        input [9:0] base_x;
        input [9:0] base_y;
        input [7:0] character;
        reg [9:0] dx;
        reg [9:0] dy;
        reg [2:0] row;
        reg [1:0] col;
        reg [2:0] bitmap_row;
        begin
            label_pixel = 1'b0;

            if ((px >= base_x) && (px < (base_x + 10'd9)) &&
                (py >= base_y) && (py < (base_y + 10'd15))) begin

                dx = px - base_x;
                dy = py - base_y;

                if (dx < 10'd3)
                    col = 2'd0;
                else if (dx < 10'd6)
                    col = 2'd1;
                else
                    col = 2'd2;

                if (dy < 10'd3)
                    row = 3'd0;
                else if (dy < 10'd6)
                    row = 3'd1;
                else if (dy < 10'd9)
                    row = 3'd2;
                else if (dy < 10'd12)
                    row = 3'd3;
                else
                    row = 3'd4;

                bitmap_row = font_row(character, row);
                label_pixel = bitmap_row[2 - col];
            end
        end
    endfunction

    function digit_pixel;
        input [9:0] px;
        input [9:0] py;
        input [9:0] base_x;
        input [9:0] base_y;
        input [3:0] digit;
        reg [9:0] dx;
        reg [9:0] dy;
        reg [2:0] row;
        reg [1:0] col;
        reg [2:0] bitmap_row;
        reg [7:0] character;
        begin
            digit_pixel = 1'b0;
            character = 8'h30 + {4'd0, digit};

            if ((px >= base_x) && (px < (base_x + 10'd15)) &&
                (py >= base_y) && (py < (base_y + 10'd25))) begin

                dx = px - base_x;
                dy = py - base_y;

                if (dx < 10'd5)
                    col = 2'd0;
                else if (dx < 10'd10)
                    col = 2'd1;
                else
                    col = 2'd2;

                if (dy < 10'd5)
                    row = 3'd0;
                else if (dy < 10'd10)
                    row = 3'd1;
                else if (dy < 10'd15)
                    row = 3'd2;
                else if (dy < 10'd20)
                    row = 3'd3;
                else
                    row = 3'd4;

                bitmap_row = font_row(character, row);
                digit_pixel = bitmap_row[2 - col];
            end
        end
    endfunction

    function lamp_box;
        input [9:0] px;
        input [9:0] py;
        input [9:0] x;
        begin
            lamp_box = (px >= x) && (px < (x + 10'd84)) &&
                       (py >= 10'd90) && (py < 10'd150);
        end
    endfunction

    function lamp_inner;
        input [9:0] px;
        input [9:0] py;
        input [9:0] x;
        begin
            lamp_inner = (px >= (x + 10'd12)) &&
                         (px < (x + 10'd72)) &&
                         (py >= 10'd100) &&
                         (py < 10'd140);
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
        // Black background.
        red         = 2'b00;
        green       = 2'b00;
        blue        = 2'b00;
        lamp_here   = 1'b0;
        lamp_is_red = 1'b0;
        text_here   = 1'b0;
        dot_here    = 1'b0;

        // Header stripe.
        if (pix_y < 10'd8) begin
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

        // Heading: F1 REFLEX.
        text_here =
            label_pixel(pix_x, pix_y, 10'd255, 10'd30, 8'h46) |
            label_pixel(pix_x, pix_y, 10'd265, 10'd30, 8'h31) |
            label_pixel(pix_x, pix_y, 10'd285, 10'd30, 8'h52) |
            label_pixel(pix_x, pix_y, 10'd295, 10'd30, 8'h45) |
            label_pixel(pix_x, pix_y, 10'd305, 10'd30, 8'h46) |
            label_pixel(pix_x, pix_y, 10'd315, 10'd30, 8'h4C) |
            label_pixel(pix_x, pix_y, 10'd325, 10'd30, 8'h45) |
            label_pixel(pix_x, pix_y, 10'd335, 10'd30, 8'h58);

        if (text_here) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // Five lamp housings.
        if (lamp_box(pix_x, pix_y, 10'd100) ||
            lamp_box(pix_x, pix_y, 10'd200) ||
            lamp_box(pix_x, pix_y, 10'd300) ||
            lamp_box(pix_x, pix_y, 10'd400) ||
            lamp_box(pix_x, pix_y, 10'd500)) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        if ((pix_y >= 10'd94) && (pix_y < 10'd146)) begin
            if (lamp_box(pix_x, pix_y, 10'd100) ||
                lamp_box(pix_x, pix_y, 10'd200) ||
                lamp_box(pix_x, pix_y, 10'd300) ||
                lamp_box(pix_x, pix_y, 10'd400) ||
                lamp_box(pix_x, pix_y, 10'd500)) begin
                red   = 2'b00;
                green = 2'b00;
                blue  = 2'b00;
            end
        end

        // Five sequential lights.
        if (lamp_inner(pix_x, pix_y, 10'd100)) begin
            lamp_here   = 1'b1;
            lamp_is_red = ((state == ST_LIGHT) || (state == ST_RUN)) &&
                          (lights_on > 3'd0);
        end

        if (lamp_inner(pix_x, pix_y, 10'd200)) begin
            lamp_here   = 1'b1;
            lamp_is_red = ((state == ST_LIGHT) || (state == ST_RUN)) &&
                          (lights_on > 3'd1);
        end

        if (lamp_inner(pix_x, pix_y, 10'd300)) begin
            lamp_here   = 1'b1;
            lamp_is_red = ((state == ST_LIGHT) || (state == ST_RUN)) &&
                          (lights_on > 3'd2);
        end

        if (lamp_inner(pix_x, pix_y, 10'd400)) begin
            lamp_here   = 1'b1;
            lamp_is_red = ((state == ST_LIGHT) || (state == ST_RUN)) &&
                          (lights_on > 3'd3);
        end

        if (lamp_inner(pix_x, pix_y, 10'd500)) begin
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

        // Current-time card.
        if ((pix_x >= 10'd190) && (pix_x < 10'd450) &&
            (pix_y >= 10'd185) && (pix_y < 10'd255)) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        if ((pix_x >= 10'd194) && (pix_x < 10'd446) &&
            (pix_y >= 10'd189) && (pix_y < 10'd251)) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end

        // Current SS.MMM.
        text_here =
            digit_pixel(pix_x, pix_y, 10'd245, 10'd205, run_sec_tens) |
            digit_pixel(pix_x, pix_y, 10'd265, 10'd205, run_sec_ones) |
            digit_pixel(pix_x, pix_y, 10'd300, 10'd205, run_ms_hunds) |
            digit_pixel(pix_x, pix_y, 10'd320, 10'd205, run_ms_tens) |
            digit_pixel(pix_x, pix_y, 10'd340, 10'd205, run_ms_ones);

        dot_here = (pix_x >= 10'd287) && (pix_x < 10'd293) &&
                   (pix_y >= 10'd224) && (pix_y < 10'd230);

        if (text_here || dot_here) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // Your best panel.
        if ((pix_x >= 10'd110) && (pix_x < 10'd530) &&
            (pix_y >= 10'd300) && (pix_y < 10'd345)) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        if ((pix_x >= 10'd114) && (pix_x < 10'd526) &&
            (pix_y >= 10'd304) && (pix_y < 10'd341)) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end

        text_here =
            label_pixel(pix_x, pix_y, 10'd130, 10'd316, 8'h59) |
            label_pixel(pix_x, pix_y, 10'd140, 10'd316, 8'h4F) |
            label_pixel(pix_x, pix_y, 10'd150, 10'd316, 8'h55) |
            label_pixel(pix_x, pix_y, 10'd170, 10'd316, 8'h42) |
            label_pixel(pix_x, pix_y, 10'd180, 10'd316, 8'h45) |
            label_pixel(pix_x, pix_y, 10'd190, 10'd316, 8'h53) |
            label_pixel(pix_x, pix_y, 10'd200, 10'd316, 8'h54);

        if (text_here) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        if (best_valid) begin
            text_here =
                digit_pixel(pix_x, pix_y, 10'd380, 10'd310, best_sec_tens) |
                digit_pixel(pix_x, pix_y, 10'd398, 10'd310, best_sec_ones) |
                digit_pixel(pix_x, pix_y, 10'd428, 10'd310, best_ms_hunds) |
                digit_pixel(pix_x, pix_y, 10'd446, 10'd310, best_ms_tens) |
                digit_pixel(pix_x, pix_y, 10'd464, 10'd310, best_ms_ones);
        end else begin
            text_here = 1'b0;
        end

        dot_here = (pix_x >= 10'd419) && (pix_x < 10'd424) &&
                   (pix_y >= 10'd325) && (pix_y < 10'd330);

        if (text_here || (dot_here && best_valid)) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // Max target panel.
        if ((pix_x >= 10'd110) && (pix_x < 10'd530) &&
            (pix_y >= 10'd370) && (pix_y < 10'd415)) begin
            red   = 2'b11;
            green = 2'b00;
            blue  = 2'b00;
        end

        if ((pix_x >= 10'd114) && (pix_x < 10'd526) &&
            (pix_y >= 10'd374) && (pix_y < 10'd411)) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end

        text_here =
            label_pixel(pix_x, pix_y, 10'd130, 10'd386, 8'h4D) |
            label_pixel(pix_x, pix_y, 10'd140, 10'd386, 8'h41) |
            label_pixel(pix_x, pix_y, 10'd150, 10'd386, 8'h58) |
            label_pixel(pix_x, pix_y, 10'd170, 10'd386, 8'h56) |
            label_pixel(pix_x, pix_y, 10'd180, 10'd386, 8'h45) |
            label_pixel(pix_x, pix_y, 10'd190, 10'd386, 8'h52) |
            label_pixel(pix_x, pix_y, 10'd200, 10'd386, 8'h53) |
            label_pixel(pix_x, pix_y, 10'd210, 10'd386, 8'h54) |
            label_pixel(pix_x, pix_y, 10'd220, 10'd386, 8'h41) |
            label_pixel(pix_x, pix_y, 10'd230, 10'd386, 8'h50) |
            label_pixel(pix_x, pix_y, 10'd240, 10'd386, 8'h50) |
            label_pixel(pix_x, pix_y, 10'd250, 10'd386, 8'h45) |
            label_pixel(pix_x, pix_y, 10'd260, 10'd386, 8'h4E);

        if (text_here) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // Fixed target: 00.227.
        text_here =
            digit_pixel(pix_x, pix_y, 10'd380, 10'd380, MAX_SEC_TENS) |
            digit_pixel(pix_x, pix_y, 10'd398, 10'd380, MAX_SEC_ONES) |
            digit_pixel(pix_x, pix_y, 10'd428, 10'd380, MAX_MS_HUNDS) |
            digit_pixel(pix_x, pix_y, 10'd446, 10'd380, MAX_MS_TENS) |
            digit_pixel(pix_x, pix_y, 10'd464, 10'd380, MAX_MS_ONES);

        dot_here = (pix_x >= 10'd419) && (pix_x < 10'd424) &&
                   (pix_y >= 10'd395) && (pix_y < 10'd400);

        if (text_here || dot_here) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // Error strips.
        if (state == ST_FALSE) begin
            if ((pix_x >= 10'd250) && (pix_x < 10'd390) &&
                (pix_y >= 10'd165) && (pix_y < 10'd171)) begin
                red   = 2'b11;
                green = 2'b00;
                blue  = 2'b00;
            end
        end

        if (state == ST_SLOW) begin
            if ((pix_x >= 10'd270) && (pix_x < 10'd370) &&
                (pix_y >= 10'd165) && (pix_y < 10'd171)) begin
                red   = 2'b11;
                green = 2'b11;
                blue  = 2'b11;
            end
        end

        // VGA blanking.
        if (!display_on) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end
    end

    // TinyVGA PMOD pin order.
    assign uo_out  = {hsync, blue[0], green[0], red[0],
                      vsync, blue[1], green[1], red[1]};
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    wire unused;
    assign unused = &{ena, uio_in, 1'b0};

endmodule


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

    // 640 active + 16 front porch + 96 sync + 48 back porch.
    assign hsync = !((hcount >= 10'd656) && (hcount < 10'd752));

    // 480 active + 10 front porch + 2 sync + 33 back porch.
    assign vsync = !((vcount >= 10'd490) && (vcount < 10'd492));

    assign display_on = (hcount < 10'd640) && (vcount < 10'd480);

endmodule
