module latch_shift_reg
#(
    parameter WIDTH = 48,
    parameter DEPTH = 8
)(
    input  wire                     rst_n,
    input  wire [WIDTH-1:0]         data_in,
    input  wire [DEPTH-1:0]         latch_en,
`ifdef USE_POWER_PINS
    input  wire VGND,
    input  wire VPWR,
`endif
    output wire [WIDTH*DEPTH-1:0]   data_out
);


    // Internal storage
    wire [WIDTH-1:0] latch_regs [0:DEPTH-1];

    genvar i;
    genvar b;
    generate
    for (i = 0; i < DEPTH; i = i + 1)
    begin : gen_prism_reg
        for (b = 0; b < WIDTH; b = b + 1)
        begin : gen_prism_bit
            sky130_fd_sc_hd__dlxtp_1 prism_cfg_bit
            (
                .D((i == 0) ? data_in[b] : latch_regs[i-1][b]),
                .GATE(latch_en[i] | !rst_n),
`ifdef USE_POWER_PINS
                .VGND(VGND),
                .VNB(VGND),
                .VPB(VPWR),
                .VPWR(VPWR),
`endif
                .Q(latch_regs[i][b])
            );
        end
    end
    endgenerate

    // Flatten output
    genvar j;
    generate
        for (j = 0; j < DEPTH; j = j + 1) begin : output_pack
            assign data_out[(j+1)*WIDTH-1:j*WIDTH] = latch_regs[j];
        end
    endgenerate

endmodule

