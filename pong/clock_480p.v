`default_nettype none
`timescale 1ns / 1ps

module clock_480p (
    input  wire clk_12MHz,
    input  wire rst_n,
    output wire pix_clk,
    output reg pix_clk_locked
    );

    localparam FEEDBACK_PATH="SIMPLE";
    localparam DIVR=4'b0000;
    localparam DIVF=7'b1000010;
    localparam DIVQ=3'b101;
    localparam FILTER_RANGE=3'b001;

    wire locked;
    SB_PLL40_PAD #(
        .FEEDBACK_PATH(FEEDBACK_PATH),
        .DIVR(DIVR),
        .DIVF(DIVF),
        .DIVQ(DIVQ),
        .FILTER_RANGE(FILTER_RANGE)
    ) pll_inst (
        .PACKAGEPIN(clk_12MHz),
        .PLLOUTGLOBAL(pix_clk),
        .RESETB(rst_n),
        .BYPASS(1'b0),
        .LOCK(locked)
    );

    reg locked_sync_0;
    always @(posedge pix_clk) begin
        locked_sync_0 <= locked;
        pix_clk_locked <= locked_sync_0;
    end
endmodule