module top (output LED1, input CLK);
    reg [23:0] counter;
    
    always @(posedge CLK) begin
        counter <= counter + 1;
    end
    
    assign LED1 = counter[23];
endmodule