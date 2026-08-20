// Based on Project F: FPGA Pong - Simple 480p Display Timings
// (C)2021 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io/posts/fpga-pong/
//
// Modified 2026 by Lewis Dill: SystemVerilog -> Verilog-2001 for Yosys,
// iCEBreaker 12-bit DVI Pmod pinout.

`default_nettype none
`timescale 1ns / 1ps

module simple_480p (
    input  wire pix_clk,   // pixel clock
    input  wire pix_rst,   // reset in pixel clock domain
    output reg [9:0] sx,  // horizontal position
    output reg [9:0] sy,  // vertical position
    output reg hsync,     // horizontal sync
    output reg vsync,     // vertical sync
    output reg de         // data enable (low in blanking interval)
    );

    // horizontal timings
    parameter HA_END = 639;           // horizontal end
    parameter HS_STA = HA_END + 16;   // sync start after front porch
    parameter HS_END = HS_STA + 96;   // sync end
    parameter LINE   = 799;           // last pixel on line

    // vertical timings
    parameter VA_END = 479;           // vertical end
    parameter VS_STA = VA_END + 10;   // sync start after front porch
    parameter VS_END = VS_STA + 2;    // sync end
    parameter SCREEN = 524;           // last line on screen

    always @(*) begin
        hsync = ~(sx >= HS_STA && sx < HS_END);  // invert
        vsync = ~(sy >= VS_STA && sy < VS_END);  // invert
        de = (sx <= HA_END && sy <= VA_END);
    end

    always @(posedge pix_clk) begin
        if (sx == LINE) begin
            sx <= 0;
            sy <= (sy == SCREEN) ? 0 : sy + 1;
        end else begin
            sx <= sx + 1;
        end
        if (pix_rst) begin
            sx <= 0;
            sy <= 0;
        end
    end
endmodule