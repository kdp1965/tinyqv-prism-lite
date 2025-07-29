module prism_latch_reg
#(
    parameter WIDTH = 32,
    parameter DRIVE = 1
)(
    input  wire               enable,
    input  wire               wr,
    input  wire [WIDTH-1:0]   data_in,
    output wire [WIDTH-1:0]   data_out
);

`ifdef SIM
    // Internal storage
    reg  [WIDTH-1:0] latch_data;

    always @(enable or wr or data_in)
    begin
        if (enable & wr)
            latch_data <= data_in;
    end

`else
    // Internal storage
    wire [WIDTH-1:0] latch_data;
    wire             gate;

    /* verilator lint_off PINMISSING */
    genvar i;
    genvar b;
    generate
        if (WIDTH < 6)
            sky130_fd_sc_hd__and2_1 gate_and (.A(enable), .B(wr), .X(gate));
        else if (WIDTH < 12)
            sky130_fd_sc_hd__and2_2 gate_and (.A(enable), .B(wr), .X(gate));
        else
            sky130_fd_sc_hd__and2_4 gate_and (.A(enable), .B(wr), .X(gate));
        
        for (b = 0; b < WIDTH; b = b + 1)
        begin : gen_prism_bit
          if (DRIVE == 1)
            sky130_fd_sc_hd__dlxtp_1 prism_cfg_bit
            (
                .D    (data_in[b]),
                .GATE (gate),
                .Q    (latch_data[b])
            );
         else if (DRIVE == 2)
            sky130_fd_sc_hd__dlxtp_2 prism_cfg_bit
            (
                .D    (data_in[b]),
                .GATE (gate),
                .Q    (latch_data[b])
            );
         else
            sky130_fd_sc_hd__dlxtp_4 prism_cfg_bit
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

