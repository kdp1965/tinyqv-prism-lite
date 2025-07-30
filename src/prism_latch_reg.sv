module prism_latch_reg
#(
    parameter WIDTH = 32
)(
    input  wire               rst_n,
    input  wire               enable,
    input  wire               wr,
    input  wire [WIDTH-1:0]   data_in,
    output wire [WIDTH-1:0]   data_out
);

`ifdef SIM
    // Internal storage
    reg  [WIDTH-1:0] latch_data;

    always @(rst_n or enable or wr or data_in)
    begin
        if (~rst_n)
            latch_data <= {WIDTH{1'b0}};
        else if (enable & wr)
            latch_data <= data_in;
    end

`else
    // Internal storage
    wire [WIDTH-1:0] latch_data;
    wire             gate;
    wire             pre_reset;

    /* verilator lint_off PINMISSING */
    genvar i;
    genvar b;
    generate
        (* keep = 1 *) sky130_fd_sc_hd__and2_1 gate_and (.A(enable), .B(wr), .X(pre_reset));
        if (WIDTH < 6)
            (* keep = 1 *) sky130_fd_sc_hd__or2_1 gate_or (.A(pre_reset), .B(~rst_n), .X(gate));
        else if (WIDTH < 12)
            (* keep = 1 *) sky130_fd_sc_hd__or2_2 gate_or (.A(pre_reset), .B(~rst_n), .X(gate));
        else
            (* keep = 1 *) sky130_fd_sc_hd__or2_4 gate_or (.A(pre_reset), .B(~rst_n), .X(gate));
        
        for (b = 0; b < WIDTH; b = b + 1)
        begin : gen_prism_bit
            (* keep = 1 *) sky130_fd_sc_hd__dlxtp_1 prism_cfg_bit
            (
                .D    (data_in[b]),
                .GATE (gate),
                .Q    (latch_data[b])
            );
        end
    endgenerate
    /* verilator lint_on PINMISSING */

`endif

    assign data_out = latch_data;

endmodule

