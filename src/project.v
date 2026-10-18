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

    // ui_in[0]: start or restart.
    // ui_in[1]: reaction button.
    reg [7:0] ui_meta;
    reg [7:0] ui_sync;
    reg [7:0] ui_prev;

    wire start_press;
    wire react_press;

    assign start_press = ui_sync[0] & ~ui_prev[0];
    assign react_press = ui_sync[1] & ~ui_prev[1];

    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_LIGHT = 3'd1;
    localparam [2:0] ST_GO    = 3'd2;
    localparam [2:0] ST_DONE  = 3'd3;
    localparam [2:0] ST_FALSE = 3'd4;
    localparam [2:0] ST_SLOW  = 3'd5;

    // Playground VGA clock: 25 MHz, so 25,000,000 cycles = one second.
    localparam [24:0] LIGHT_TICKS = 25'd25000000;

    // Requested displayed target: 00.227.
    localparam [3:0] MAX_SEC_TENS = 4'd0;
    localparam [3:0] MAX_SEC_ONES = 4'd0;
    localparam [3:0] MAX_MS_HUNDS = 4'd2;
    localparam [3:0] MAX_MS_TENS  = 4'd2;
    localparam [3:0] MAX_MS_ONES  = 4'd7;

    reg [2:0]  state;
    reg [2:0]  lamp_count;
    reg [24:0] light_div;

    // Current reaction time: SS.MMM.
    reg [14:0] ms_div;
    reg [3:0]  run_sec_tens;
    reg [3:0]  run_sec_ones;
    reg [3:0]  run_ms_hunds;
    reg [3:0]  run_ms_tens;
    reg [3:0]  run_ms_ones;

    // Best valid result, held until reset.
    reg [3:0] best_sec_tens;
    reg [3:0] best_sec_ones;
    reg [3:0] best_ms_hunds;
    reg [3:0] best_ms_tens;
    reg [3:0] best_ms_ones;
    reg       best_valid;

    wire run_is_better;

    assign run_is_better =
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
            ui_meta       <= 8'h00;
            ui_sync       <= 8'h00;
            ui_prev       <= 8'h00;

            state         <= ST_IDLE;
            lamp_count    <= 3'd0;
            light_div     <= 25'd0;

            ms_div        <= 15'd0;
            run_sec_tens  <= 4'd0;
            run_sec_ones  <= 4'd0;
            run_ms_hunds  <= 4'd0;
            run_ms_tens   <= 4'd0;
            run_ms_ones   <= 4'd0;

            best_sec_tens <= 4'd0;
            best_sec_ones <= 4'd0;
            best_ms_hunds <= 4'd0;
            best_ms_tens  <= 4'd0;
            best_ms_ones  <= 4'd0;
            best_valid    <= 1'b0;
        end else begin
            // Two-flop synchronizer for asynchronous external buttons.
            ui_meta <= ui_in;
            ui_sync <= ui_meta;
            ui_prev <= ui_sync;

            // 25,000 cycles are exactly one millisecond at 25 MHz.
            if (state == ST_GO) begin
                if (ms_div == 15'd24999) begin
                    ms_div <= 15'd0;

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
                    ms_div <= ms_div + 15'd1;
                end
            end else begin
                ms_div <= 15'd0;
            end

            case (state)
                ST_IDLE: begin
                    if (start_press) begin
                        // Lamp 1 turns on immediately.
                        state        <= ST_LIGHT;
                        lamp_count   <= 3'd1;
                        light_div    <= 25'd0;

                        run_sec_tens <= 4'd0;
                        run_sec_ones <= 4'd0;
                        run_ms_hunds <= 4'd0;
                        run_ms_tens  <= 4'd0;
                        run_ms_ones  <= 4'd0;
                    end
                end

                ST_LIGHT: begin
                    // Reaction before lamp 5 is a false start.
                    if (react_press) begin
                        state <= ST_FALSE;
                    end else if (light_div == (LIGHT_TICKS - 25'd1)) begin
                        light_div <= 25'd0;

                        // Lamp 5 turns on and timing begins on this edge.
                        if (lamp_count == 3'd4) begin
                            lamp_count <= 3'd5;
                            state      <= ST_GO;
                        end else begin
                            lamp_count <= lamp_count + 3'd1;
                        end
                    end else begin
                        light_div <= light_div + 25'd1;
                    end
                end

                ST_GO: begin
                    if (react_press) begin
                        state <= ST_DONE;

                        if (!best_valid || run_is_better) begin
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

    // 3x5 pixel font, encoded as one 15-bit bitmap per glyph.
    // Supports digits and uppercase letters used by the interface.
    function font_bit;
        input [7:0] character;
        input [2:0] row;
        input [1:0] col;
        reg [14:0] bitmap;
        reg [4:0] bit_index;
        begin
            bitmap = 15'b000000000000000;

            case (character)
                8'h30: bitmap = 15'b111101101101111; // 0
                8'h31: bitmap = 15'b010110010010111; // 1
                8'h32: bitmap = 15'b110001010100111; // 2
                8'h33: bitmap = 15'b110001010001110; // 3
                8'h34: bitmap = 15'b101101111001001; // 4
                8'h35: bitmap = 15'b111100110001110; // 5
                8'h36: bitmap = 15'b011100111101111; // 6
                8'h37: bitmap = 15'b111001010010010; // 7
                8'h38: bitmap = 15'b111101111101111; // 8
                8'h39: bitmap = 15'b111101111001110; // 9

                8'h41: bitmap = 15'b010101111101101; // A
                8'h42: bitmap = 15'b110101110101110; // B
                8'h43: bitmap = 15'b111100100100111; // C
                8'h45: bitmap = 15'b111100110100111; // E
                8'h46: bitmap = 15'b111100110100100; // F
                8'h49: bitmap = 15'b111010010010111; // I
                8'h4C: bitmap = 15'b100100100100111; // L
                8'h4D: bitmap = 15'b101111111101101; // M
                8'h4E: bitmap = 15'b101111111111101; // N
                8'h4F: bitmap = 15'b111101101101111; // O
                8'h50: bitmap = 15'b110101110100100; // P
                8'h52: bitmap = 15'b110101110101101; // R
                8'h53: bitmap = 15'b111100111001111; // S
                8'h54: bitmap = 15'b111010010010010; // T
                8'h55: bitmap = 15'b101101101101111; // U
                8'h56: bitmap = 15'b101101101010010; // V
                8'h58: bitmap = 15'b101101010101101; // X
                8'h59: bitmap = 15'b101101010010010; // Y

                default: bitmap = 15'b000000000000000;
            endcase

            bit_index = row + row + row + col;

            if ((row < 3'd5) && (col < 2'd3))
                font_bit = bitmap[14 - bit_index];
            else
                font_bit = 1'b0;
        end
    endfunction

    // 3x5 glyph enlarged to 9x15 pixels.
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

                label_pixel = font_bit(character, row, col);
            end
        end
    endfunction

    // 3x5 digit enlarged to 15x25 pixels.
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

                digit_pixel = font_bit(character, row, col);
            end
        end
    endfunction

    function lamp_panel;
        input [9:0] px;
        input [9:0] py;
        input [9:0] base_x;
        begin
            lamp_panel = (px >= base_x) &&
                         (px < (base_x + 10'd90)) &&
                         (py >= 10'd85) &&
                         (py < 10'd155);
        end
    endfunction

    function lamp_core;
        input [9:0] px;
        input [9:0] py;
        input [9:0] base_x;
        begin
            lamp_core = (px >= (base_x + 10'd15)) &&
                        (px < (base_x + 10'd75)) &&
                        (py >= 10'd97) &&
                        (py < 10'd143);
        end
    endfunction

    reg [1:0] red;
    reg [1:0] green;
    reg [1:0] blue;
    reg       lamp_active;
    reg       lamp_red;
    reg       text_pixel;
    reg       point_pixel;

    always @* begin
        // Black background: only black, red, and white are used.
        red          = 2'b00;
        green        = 2'b00;
        blue         = 2'b00;
        lamp_active  = 1'b0;
        lamp_red     = 1'b0;
        text_pixel   = 1'b0;
        point_pixel  = 1'b0;

        // Header line: red while measuring, otherwise white.
        if (pix_y < 10'd9) begin
            if (state == ST_GO) begin
                red   = 2'b11;
                green = 2'b00;
                blue  = 2'b00;
            end else begin
                red   = 2'b11;
                green = 2'b11;
                blue  = 2'b11;
            end
        end

        // Heading: F1 REFLEX TRAINER.
        text_pixel =
            label_pixel(pix_x, pix_y, 10'd235, 10'd28, 8'h46) | // F
            label_pixel(pix_x, pix_y, 10'd245, 10'd28, 8'h31) | // 1
            label_pixel(pix_x, pix_y, 10'd265, 10'd28, 8'h52) | // R
            label_pixel(pix_x, pix_y, 10'd275, 10'd28, 8'h45) | // E
            label_pixel(pix_x, pix_y, 10'd285, 10'd28, 8'h46) | // F
            label_pixel(pix_x, pix_y, 10'd295, 10'd28, 8'h4C) | // L
            label_pixel(pix_x, pix_y, 10'd305, 10'd28, 8'h45) | // E
            label_pixel(pix_x, pix_y, 10'd315, 10'd28, 8'h58) | // X
            label_pixel(pix_x, pix_y, 10'd335, 10'd28, 8'h54) | // T
            label_pixel(pix_x, pix_y, 10'd345, 10'd28, 8'h52) | // R
            label_pixel(pix_x, pix_y, 10'd355, 10'd28, 8'h41) | // A
            label_pixel(pix_x, pix_y, 10'd365, 10'd28, 8'h49) | // I
            label_pixel(pix_x, pix_y, 10'd375, 10'd28, 8'h4E) | // N
            label_pixel(pix_x, pix_y, 10'd385, 10'd28, 8'h45) | // E
            label_pixel(pix_x, pix_y, 10'd395, 10'd28, 8'h52);  // R

        if (text_pixel) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // Five black lamp housings.
        if (lamp_panel(pix_x, pix_y, 10'd85) ||
            lamp_panel(pix_x, pix_y, 10'd195) ||
            lamp_panel(pix_x, pix_y, 10'd305) ||
            lamp_panel(pix_x, pix_y, 10'd415) ||
            lamp_panel(pix_x, pix_y, 10'd525)) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end

        // White top and bottom borders for lamps.
        if (((pix_y >= 10'd85) && (pix_y < 10'd89)) ||
            ((pix_y >= 10'd151) && (pix_y < 10'd155))) begin
            if (((pix_x >= 10'd85) && (pix_x < 10'd175)) ||
                ((pix_x >= 10'd195) && (pix_x < 10'd285)) ||
                ((pix_x >= 10'd305) && (pix_x < 10'd395)) ||
                ((pix_x >= 10'd415) && (pix_x < 10'd505)) ||
                ((pix_x >= 10'd525) && (pix_x < 10'd615))) begin
                red   = 2'b11;
                green = 2'b11;
                blue  = 2'b11;
            end
        end

        // Lamp count rises from one to five. All five remain red while timing.
        if (lamp_core(pix_x, pix_y, 10'd85)) begin
            lamp_active = 1'b1;
            lamp_red = ((state == ST_LIGHT) || (state == ST_GO)) &&
                       (lamp_count > 3'd0);
        end

        if (lamp_core(pix_x, pix_y, 10'd195)) begin
            lamp_active = 1'b1;
            lamp_red = ((state == ST_LIGHT) || (state == ST_GO)) &&
                       (lamp_count > 3'd1);
        end

        if (lamp_core(pix_x, pix_y, 10'd305)) begin
            lamp_active = 1'b1;
            lamp_red = ((state == ST_LIGHT) || (state == ST_GO)) &&
                       (lamp_count > 3'd2);
        end

        if (lamp_core(pix_x, pix_y, 10'd415)) begin
            lamp_active = 1'b1;
            lamp_red = ((state == ST_LIGHT) || (state == ST_GO)) &&
                       (lamp_count > 3'd3);
        end

        if (lamp_core(pix_x, pix_y, 10'd525)) begin
            lamp_active = 1'b1;
            lamp_red = ((state == ST_LIGHT) || (state == ST_GO)) &&
                       (lamp_count > 3'd4);
        end

        if (lamp_active) begin
            if (lamp_red) begin
                red   = 2'b11;
                green = 2'b00;
                blue  = 2'b00;
            end else begin
                red   = 2'b01;
                green = 2'b01;
                blue  = 2'b01;
            end
        end

        // Main timer card.
        if ((pix_x >= 10'd175) && (pix_x < 10'd465) &&
            (pix_y >= 10'd185) && (pix_y < 10'd265)) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        if ((pix_x >= 10'd180) && (pix_x < 10'd460) &&
            (pix_y >= 10'd190) && (pix_y < 10'd260)) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end

        // Current time: SS.MMM.
        text_pixel =
            digit_pixel(pix_x, pix_y, 10'd240, 10'd210, run_sec_tens) |
            digit_pixel(pix_x, pix_y, 10'd260, 10'd210, run_sec_ones) |
            digit_pixel(pix_x, pix_y, 10'd295, 10'd210, run_ms_hunds) |
            digit_pixel(pix_x, pix_y, 10'd315, 10'd210, run_ms_tens) |
            digit_pixel(pix_x, pix_y, 10'd335, 10'd210, run_ms_ones);

        point_pixel = (pix_x >= 10'd282) && (pix_x < 10'd288) &&
                      (pix_y >= 10'd229) && (pix_y < 10'd235);

        if (text_pixel || point_pixel) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // Best-score card.
        if ((pix_x >= 10'd90) && (pix_x < 10'd550) &&
            (pix_y >= 10'd305) && (pix_y < 10'd355)) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        if ((pix_x >= 10'd94) && (pix_x < 10'd546) &&
            (pix_y >= 10'd309) && (pix_y < 10'd351)) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end

        // Label: YOUR BEST.
        text_pixel =
            label_pixel(pix_x, pix_y, 10'd112, 10'd322, 8'h59) | // Y
            label_pixel(pix_x, pix_y, 10'd122, 10'd322, 8'h4F) | // O
            label_pixel(pix_x, pix_y, 10'd132, 10'd322, 8'h55) | // U
            label_pixel(pix_x, pix_y, 10'd152, 10'd322, 8'h42) | // B
            label_pixel(pix_x, pix_y, 10'd162, 10'd322, 8'h45) | // E
            label_pixel(pix_x, pix_y, 10'd172, 10'd322, 8'h53) | // S
            label_pixel(pix_x, pix_y, 10'd182, 10'd322, 8'h54);  // T

        if (text_pixel) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        if (best_valid) begin
            text_pixel =
                digit_pixel(pix_x, pix_y, 10'd390, 10'd314, best_sec_tens) |
                digit_pixel(pix_x, pix_y, 10'd408, 10'd314, best_sec_ones) |
                digit_pixel(pix_x, pix_y, 10'd438, 10'd314, best_ms_hunds) |
                digit_pixel(pix_x, pix_y, 10'd456, 10'd314, best_ms_tens) |
                digit_pixel(pix_x, pix_y, 10'd474, 10'd314, best_ms_ones);
        end else begin
            text_pixel = 1'b0;
        end

        point_pixel = (pix_x >= 10'd429) && (pix_x < 10'd434) &&
                      (pix_y >= 10'd329) && (pix_y < 10'd334);

        if (text_pixel || (point_pixel && best_valid)) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // Max target card.
        if ((pix_x >= 10'd90) && (pix_x < 10'd550) &&
            (pix_y >= 10'd375) && (pix_y < 10'd425)) begin
            red   = 2'b11;
            green = 2'b00;
            blue  = 2'b00;
        end

        if ((pix_x >= 10'd94) && (pix_x < 10'd546) &&
            (pix_y >= 10'd379) && (pix_y < 10'd421)) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end

        // Label: MAX VERSTAPPEN.
        text_pixel =
            label_pixel(pix_x, pix_y, 10'd112, 10'd392, 8'h4D) | // M
            label_pixel(pix_x, pix_y, 10'd122, 10'd392, 8'h41) | // A
            label_pixel(pix_x, pix_y, 10'd132, 10'd392, 8'h58) | // X
            label_pixel(pix_x, pix_y, 10'd152, 10'd392, 8'h56) | // V
            label_pixel(pix_x, pix_y, 10'd162, 10'd392, 8'h45) | // E
            label_pixel(pix_x, pix_y, 10'd172, 10'd392, 8'h52) | // R
            label_pixel(pix_x, pix_y, 10'd182, 10'd392, 8'h53) | // S
            label_pixel(pix_x, pix_y, 10'd192, 10'd392, 8'h54) | // T
            label_pixel(pix_x, pix_y, 10'd202, 10'd392, 8'h41) | // A
            label_pixel(pix_x, pix_y, 10'd212, 10'd392, 8'h50) | // P
            label_pixel(pix_x, pix_y, 10'd222, 10'd392, 8'h50) | // P
            label_pixel(pix_x, pix_y, 10'd232, 10'd392, 8'h45) | // E
            label_pixel(pix_x, pix_y, 10'd242, 10'd392, 8'h4E);  // N

        if (text_pixel) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // Fixed requested target: 00.227.
        text_pixel =
            digit_pixel(pix_x, pix_y, 10'd390, 10'd384, MAX_SEC_TENS) |
            digit_pixel(pix_x, pix_y, 10'd408, 10'd384, MAX_SEC_ONES) |
            digit_pixel(pix_x, pix_y, 10'd438, 10'd384, MAX_MS_HUNDS) |
            digit_pixel(pix_x, pix_y, 10'd456, 10'd384, MAX_MS_TENS) |
            digit_pixel(pix_x, pix_y, 10'd474, 10'd384, MAX_MS_ONES);

        point_pixel = (pix_x >= 10'd429) && (pix_x < 10'd434) &&
                      (pix_y >= 10'd399) && (pix_y < 10'd404);

        if (text_pixel || point_pixel) begin
            red   = 2'b11;
            green = 2'b11;
            blue  = 2'b11;
        end

        // State markers: false start in red, timeout in white.
        if (state == ST_FALSE) begin
            if ((pix_x >= 10'd245) && (pix_x < 10'd395) &&
                (pix_y >= 10'd170) && (pix_y < 10'd176)) begin
                red   = 2'b11;
                green = 2'b00;
                blue  = 2'b00;
            end
        end

        if (state == ST_SLOW) begin
            if ((pix_x >= 10'd270) && (pix_x < 10'd370) &&
                (pix_y >= 10'd170) && (pix_y < 10'd176)) begin
                red   = 2'b11;
                green = 2'b11;
                blue  = 2'b11;
            end
        end

        // RGB is black outside the active VGA image.
        if (!display_on) begin
            red   = 2'b00;
            green = 2'b00;
            blue  = 2'b00;
        end
    end

    // TinyVGA PMOD output order.
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

    // 640 active + 16 front porch + 96 active-low sync + 48 back porch.
    assign hsync = !((hcount >= 10'd656) && (hcount < 10'd752));

    // 480 active + 10 front porch + 2 active-low sync + 33 back porch.
    assign vsync = !((vcount >= 10'd490) && (vcount < 10'd492));

    assign display_on = (hcount < 10'd640) && (vcount < 10'd480);

endmodule
