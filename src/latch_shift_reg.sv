module latch_shift_reg
#(
    parameter WIDTH = 48,
    parameter DEPTH = 8
)(
    input  wire                     rst_n,
    input  wire [WIDTH-1:0]         data_in,
    input  wire [DEPTH-1:0]         latch_en,
    output wire [WIDTH*DEPTH-1:0]   data_out
);

    // Internal storage
    reg [WIDTH-1:0] latch_regs [0:DEPTH-1];

    integer i;
    always_latch begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            if (latch_en[i] || !rst_n) begin
                latch_regs[i] = (i == 0) ? data_in : latch_regs[i-1];
            end
        end
    end

    // Flatten output
    genvar j;
    generate
        for (j = 0; j < DEPTH; j = j + 1) begin : output_pack
            assign data_out[(j+1)*WIDTH-1:j*WIDTH] = latch_regs[j];
        end
    endgenerate

endmodule

