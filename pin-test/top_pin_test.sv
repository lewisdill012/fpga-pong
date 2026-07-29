module top_pin_test (
    input  wire clk_12m,
    output wire dvi_clk,
    output wire dvi_hsync,
    output wire dvi_vsync,
    output wire dvi_de,
    output wire [3:0] dvi_r,
    output wire [3:0] dvi_g,
    output wire [3:0] dvi_b
);

    reg [22:0] counter;
    always @(posedge clk_12m) counter <= counter + 1'b1;

    wire slow = counter[22];  // ~0.7 Hz toggle

    assign dvi_clk   = slow;
    assign dvi_hsync = slow;
    assign dvi_vsync = slow;
    assign dvi_de    = slow;
    assign dvi_r     = {4{slow}};
    assign dvi_g     = 4'b0000;
    assign dvi_b     = 4'b0000;

endmodule