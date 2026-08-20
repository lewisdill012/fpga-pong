`default_nettype none
`timescale 1ns / 1ps

module top_pong (
    input  wire clk_12m,    // 12 MHz clock
    input  wire btn_rst,      // reset button
    input  wire btn_fire,     // fire button
    input  wire btn_up,       // up button
    input  wire btn_dn,       // down button
    output reg dvi_clk,      // DVI pixel clock
    output reg dvi_hsync,    // DVI horizontal sync
    output reg dvi_vsync,    // DVI vertical sync
    output reg dvi_de,       // DVI data enable
    output reg [3:0] dvi_r,  // 4-bit DVI red
    output reg [3:0] dvi_g,  // 4-bit DVI green
    output reg [3:0] dvi_b   // 4-bit DVI blue
    );

    // gameplay params
    localparam TOWIN      =  4;
    localparam SPEEDUP    =  5;  // speed up ball after this many shots (max 16)
    localparam BALL_SIZE  =  8;  // ball size in pixels
    localparam BALL_ISPX  =  5;  // initial horizontal ball speed
    localparam BALL_ISPY  =  3;  // initial vertical ball speed
    localparam PAD_HEIGHT = 48;  // paddle height in pixels
    localparam PAD_WIDTH  = 10;  // paddle width in pixels
    localparam PAD_OFFS   = 32;  // paddle distance from edge of screen in pixels
    localparam PAD_SPD    =  3;  // vertical paddle speed

    reg pix_clk;
    reg pix_clk_locked;
    clock_480p pixel_clock_inst (
       .clk_12MHz(clk_12m),
       .rst_n(btn_rst),
       .pix_clk,
       .pix_clk_locked
    );

    // display sync signals and coordinates 
    localparam CORDW = 10;  // screen coordinate width in bits
    reg [CORDW-1:0] sx, sy;
    reg hsync, vsync, de;
    simple_480p display_inst (
        .pix_clk,
        .pix_rst(!pix_clk_locked),  // wait for clock lock
        .sx,
        .sy,
        .hsync,
        .vsync,
        .de
    );

    localparam H_RES = 640;
    localparam V_RES = 480;

    reg frame;
    always @(*) frame = (sy == V_RES && sx == 0);

    reg [3:0] score_l, score_r;
    
    reg ball, padl, padr;

    reg [CORDW-1:0] ball_x, ball_y;  // position (origin at top left)
    reg [CORDW-1:0] ball_spx;        // horizontal speed (pixels/frame)
    reg [CORDW-1:0] ball_spy;        // vertical speed (pixels/frame)
    reg [3:0] shot_cnt;              // shot counter
    reg ball_dx, ball_dy;            // direction: 0 is right/down
    reg ball_dx_prev;                // direction in previous tick (for shot counting)
    reg coll_r, coll_l;              // screen collision flags

    reg [CORDW-1:0] padl_y, padr_y;  // vertical position of left and right paddles
    reg [CORDW-1:0] ai_y, play_y;    // vertical position of AI and player paddle

    always @(*) begin
        padl_y = play_y;
        padr_y = ai_y;
    end

    reg sig_fire, sig_up, sig_dn;
    debounce deb_fire (.clk(pix_clk), .in(btn_fire), .out(), .ondn(), .onup(sig_fire));
    debounce deb_up (.clk(pix_clk), .in(btn_up), .out(sig_up), .ondn(), .onup());
    debounce deb_dn (.clk(pix_clk), .in(btn_dn), .out(sig_dn), .ondn(), .onup());

    localparam NEW_GAME=0, POSITION=1, READY=2, POINT=3, END_GAME=4, PLAY=5;
    reg [2:0] state, state_next;
    always @(*) begin
        case (state)
            NEW_GAME: state_next = POSITION;
            POSITION: state_next = READY;
            READY: state_next = (sig_fire) ? PLAY : READY;
            POINT: state_next = (sig_fire) ? POSITION : POINT;
            END_GAME: state_next = (sig_fire) ? NEW_GAME : END_GAME;
            PLAY: begin
                if (coll_l || coll_r) begin
                    if ((score_l == TOWIN) || (score_r == TOWIN)) state_next = END_GAME;
                    else state_next = POINT;
                end else state_next = PLAY;
            end
            default: state_next = NEW_GAME;
        endcase
        if (!pix_clk_locked) state_next = NEW_GAME;
    end

    always @(posedge pix_clk) state <= state_next;

    // AI paddle
    always @(posedge pix_clk) begin
        if (state == POSITION) ai_y <= (V_RES - PAD_HEIGHT)/2;
        else if (frame && state == PLAY) begin
            if (ai_y + PAD_HEIGHT/2 < ball_y) begin  // ball below
                if (ai_y + PAD_HEIGHT + PAD_SPD >= V_RES-1) begin  // bottom of screen?
                    ai_y <= V_RES - PAD_HEIGHT - 1;  // move down as far as we can
                end else ai_y <= ai_y + PAD_SPD;  // move down
            end else if (ai_y + PAD_HEIGHT/2 > ball_y + BALL_SIZE) begin // ball above
                if (ai_y < PAD_SPD) begin  // top of screen
                    ai_y <= 0;  // move up as far as we can
                end else ai_y <= ai_y - PAD_SPD;  // move up
            end
        end
    end

    // Player control
    always @(posedge pix_clk) begin
        if (state == POSITION) play_y <= (V_RES - PAD_HEIGHT)/2;
        else if (frame && state == PLAY) begin
            if (sig_dn) begin
                if (play_y + PAD_HEIGHT + PAD_SPD >= V_RES-1) begin  // bottom of screen?
                    play_y <= V_RES - PAD_HEIGHT - 1;  // move down as far as we can
                end else play_y <= play_y + PAD_SPD;  // move down
            end else if (sig_up) begin
                if (play_y < PAD_SPD) begin  // top of screen
                    play_y <= 0;  // move up as far as we can
                end else play_y <= play_y - PAD_SPD;  // move up
            end
        end
    end

    // ball movement
    always @(posedge pix_clk) begin
        case (state)
            NEW_GAME: begin
                score_l <= 0;  // reset score
                score_r <= 0;
            end

            POSITION: begin
                coll_l <= 0;  // reset screen collision flags
                coll_r <= 0;
                ball_spx <= BALL_ISPX;  // reset speed
                ball_spy <= BALL_ISPY;
                shot_cnt <= 0;  // reset shot count

                // centre ball vertically and position on paddle (right or left)
                ball_y <= (V_RES - BALL_SIZE)/2;
                if (coll_r) begin
                    ball_x <= H_RES - (PAD_OFFS + PAD_WIDTH + BALL_SIZE);
                    ball_dx <= 1;  // move left
                end else begin
                    ball_x <= PAD_OFFS + PAD_WIDTH;
                    ball_dx <= 0;  // move right
                end
            end

            PLAY: begin
                if (frame) begin
                    // horizontal ball position
                    if (ball_dx == 0) begin  // moving right
                        if (ball_x + BALL_SIZE + ball_spx >= H_RES-1) begin
                            ball_x <= H_RES-BALL_SIZE;  // move to edge of screen
                            score_l <= score_l + 1;
                            coll_r <= 1;
                        end else ball_x <= ball_x + ball_spx;
                    end else begin  // moving left
                        if (ball_x < ball_spx) begin
                            ball_x <= 0;  // move to edge of screen
                            score_r <= score_r + 1;
                            coll_l <= 1;
                        end else ball_x <= ball_x - ball_spx;
                    end

                    // vertical ball position
                    if (ball_dy == 0) begin  // moving down
                        if (ball_y + BALL_SIZE + ball_spy >= V_RES-1)
                            ball_dy <= 1;  // move up next frame
                        else ball_y <= ball_y + ball_spy;
                    end else begin  // moving up
                        if (ball_y < ball_spy)
                            ball_dy <= 0;  // move down next frame
                        else ball_y <= ball_y - ball_spy;
                    end

                    // ball speed increases after SPEEDUP shots
                    if (ball_dx_prev != ball_dx) shot_cnt <= shot_cnt + 1;
                    if (shot_cnt == SPEEDUP) begin  // increase ball speed
                        ball_spx <= (ball_spx < PAD_WIDTH) ? ball_spx + 1 : ball_spx;
                        ball_spy <= ball_spy + 1;
                        shot_cnt <= 0;
                    end
                end
            end
        endcase

        // change direction if ball collides with paddle
        if (ball && padl && ball_dx==1) ball_dx <= 0;  // left paddle
        if (ball && padr && ball_dx==0) ball_dx <= 1;  // right paddle

        // record ball direction in previous frame
        if (frame) ball_dx_prev <= ball_dx;
    end

    // check for ball and paddles at current screen position (sx,sy)
    always @(*) begin
        ball = (sx >= ball_x) && (sx < ball_x + BALL_SIZE)
               && (sy >= ball_y) && (sy < ball_y + BALL_SIZE);
        padl = (sx >= PAD_OFFS) && (sx < PAD_OFFS + PAD_WIDTH)
               && (sy >= padl_y) && (sy < padl_y + PAD_HEIGHT);
        padr = (sx >= H_RES - PAD_OFFS - PAD_WIDTH - 1) && (sx < H_RES - PAD_OFFS - 1)
               && (sy >= padr_y) && (sy < padr_y + PAD_HEIGHT);
    end

    // draw the score
    reg pix_score;  // pixel of score char
    simple_score #(.CORDW(CORDW), .H_RES(H_RES)) simple_score_inst (
        .pix_clk,
        .sx,
        .sy,
        .score_l,
        .score_r,
        .pix(pix_score)
    );

    // Colors
    reg [3:0] paint_r, paint_g, paint_b;
    always @(*) begin
        if (pix_score) {paint_r, paint_g, paint_b} = 12'hF30;  // score
        else if (ball) {paint_r, paint_g, paint_b} = 12'hFC0;  // ball
        else if (padl || padr) {paint_r, paint_g, paint_b} = 12'hFFF;  // paddles
        else {paint_r, paint_g, paint_b} = 12'h137;  // background
    end

    // Display colour
    reg [3:0] display_r, display_g, display_b;
    always @(*) begin
        display_r = (de) ? paint_r : 4'h0;
        display_g = (de) ? paint_g : 4'h0;
        display_b = (de) ? paint_b : 4'h0;
    end

    // DVI Pmod output
    SB_IO #(
        .PIN_TYPE(6'b010100)  // PIN_OUTPUT_REGISTERED
    ) dvi_signal_io [14:0] (
        .PACKAGE_PIN({dvi_hsync, dvi_vsync, dvi_de, dvi_r, dvi_g, dvi_b}),
        .OUTPUT_CLK(pix_clk),
        .D_OUT_0({hsync, vsync, de, display_r, display_g, display_b}),
        /* verilator lint_off PINCONNECTEMPTY */
        .D_OUT_1()
        /* verilator lint_on PINCONNECTEMPTY */
    );

    // DVI Pmod clock output: 180° out of phase with other DVI signals
    SB_IO #(
        .PIN_TYPE(6'b010000)  // PIN_OUTPUT_DDR
    ) dvi_clk_io (
        .PACKAGE_PIN(dvi_clk),
        .OUTPUT_CLK(pix_clk),
        .D_OUT_0(1'b0),
        .D_OUT_1(1'b1)
    );
endmodule