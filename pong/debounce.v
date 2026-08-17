`default_nettype none
`timescale 1ns / 1ps

module debounce (
    input  wire clk,   // clock
    input  wire in,    // signal input
    output reg out,   // signal output (debounced)
    output reg ondn,  // on down (one tick)
    output reg onup   // on up (one tick)
    );

    // sync with clock and combat metastability
    reg sync_0, sync_1;
    always @(posedge clk) begin
        sync_0 <= in;
        sync_1 <= sync_0;
    end

    reg [17:0] cnt;
    reg idle, max;
    always @(*) begin
        idle = (out == sync_1);
        max  = &cnt;
        ondn = ~idle & max & ~out;
        onup = ~idle & max & out;
    end

    always @(posedge clk) begin
        if (idle) begin
            cnt <= 0;
        end else begin
            cnt <= cnt + 1;
            if (max) out <= ~out;
        end
    end

endmodule