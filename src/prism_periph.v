/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
module tqvp_prism (
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.

    input  [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                // Note that uo_out[0] is normally used for UART TX.

    input [5:0]   address,      // Address within this peripheral's address space
    input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    
    output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output        data_ready,

    output        user_interrupt  // Dedicated interrupt request for this peripheral
);

    localparam  OUTPUTS = 13;

    reg                 prism_reset;
    reg                 prism_enable;
    reg                 prism_halt_r;
    reg                 prism_interrupt;
    reg   [1:0]         extra_in;
    wire                prism_wr;
    wire [15:0]         prism_in_data;
    wire [OUTPUTS-1:0]  prism_out_data;
    wire [31:0]         prism_read_data;
    reg  [23:0]         count1_preload;
    reg  [23:0]         count1;
    reg   [3:0]         count2;
    reg   [3:0]         count2_compare;
    reg   [3:0]         latched_ctrl;
    reg   [3:0]         latched_out;
    reg   [1:0]         latched_in;
    reg   [7:0]         comm_data;
    reg   [1:0]         comm_in_sel;
    reg   [2:0]         cond_out_sel;
    reg                 shift_dir;
    wire  [6:0]         cond_out_en;
    wire  [0:0]         cond_out;
    wire                comm_in;
    wire  [3:0]         comm_data_bits;
    wire                prism_halt;

    // Instantiate the prism controller
    prism
    #(
        .OUTPUTS ( OUTPUTS )
     )
    i_prism
    (
        .clk                ( clk               ),
        .rst_n              ( rst_n             ),

        .debug_reset        ( prism_reset       ),
        .fsm_enable         ( prism_enable      ),
        .in_data            ( prism_in_data     ),
        .out_data           ( prism_out_data    ),
        .cond_out           ( cond_out          ),
                            
        .debug_addr         ( address           ),
        .debug_wr           ( prism_wr          ),
        .debug_wdata        ( data_in           ),
        .debug_rdata        ( prism_read_data   ),
        .debug_halt_either  ( prism_halt        )
    );

    assign prism_wr = data_write_n == 2'b10;

    genvar i;
    generate
    for (i = 0; i < 7; i = i + 1)
    begin : GEN_COND_OUT_EN
        assign cond_out_en[i] = cond_out_sel == i;    
    end
    endgenerate

    // We don't use uo_out0 so it can be used for comms with RISC-V
    // Assign outputs based on conditional enable or latched enable
    assign uo_out[4:1] = (cond_out_en[3:0] & {4{cond_out[0]}}) | (~cond_out_en[3:0] & ((latched_ctrl & latched_out) | (~latched_ctrl & prism_out_data[3:0])));
    assign uo_out[7:5] = (cond_out_en[6:4] & {3{cond_out[0]}}) | (~cond_out_en[6:4] & prism_out_data[6:4]);
    assign uo_out[0] = 1'b0;
    
    // Assign the PRISM intput data
    assign prism_in_data[6:0]   = ui_in[6:0];
    assign prism_in_data[7]     = shift_dir ? comm_data[0] : comm_data[7];
    assign prism_in_data[9:8]   = extra_in;
    assign prism_in_data[13:12] = latched_in ^ ui_in[1:0];
    assign prism_in_data[15:0]  = 2'h0;

    // Address 0 reads the example data register.  
    // Address 4 reads ui_in
    // All other addresses read 0.
    assign data_out = address == 6'h0  ? {prism_interrupt, prism_reset, prism_enable,
                                          12'h0, shift_dir, 1'b0, cond_out_sel, 2'b0, comm_in_sel, latched_out, latched_ctrl} :
                      address == 6'h18 ? {22'h0, extra_in, comm_data} :
                      address == 6'h28 ? {count2, 4'b0, count1} :
                      prism_read_data;

    // All reads complete in 1 clock
    assign data_ready = 1;

    // Assign COMM data in
    assign comm_data_bits = ui_in[3:0];
    assign comm_in = comm_data_bits[comm_in_sel];
    
    // User interrupt is generated on rising edge of ui_in[6], and cleared by writing a 1 to the low bit of address 8.

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            prism_reset     <= 1'b0;
            prism_enable    <= 1'b0;
            prism_interrupt <= 1'b0;
            prism_halt_r    <= 1'b0;
            extra_in        <= 2'b0;
            count1_preload  <= 24'b0;
            count2_compare  <= 4'b0;
            count1          <= 27'b0;
            count2          <= 4'b0;
            latched_ctrl    <= 4'b0;
            latched_out     <= 4'h0;
            comm_data       <= 8'h0;
            comm_in_sel     <= 2'h0;
            cond_out_sel    <= 3'h0;
            shift_dir       <= 1'b0;
        end
        else
        begin
            // Detect rising edge of HALT
            prism_halt_r <= prism_halt;
            
            if ((prism_halt && !prism_halt_r) | (prism_out_data[10] & prism_out_data[9])) begin
                prism_interrupt <= 1;
            end else if (address == 6'h0 && data_write_n == 2'b10)
            begin
                // Test for interrupt clear
                if (data_in[31])
                    prism_interrupt <= 0;

                // FSM Enable and reset bits
                prism_reset  <= data_in[30];
                prism_enable <= data_in[29];
                latched_ctrl <= data_in[3:0];
                comm_in_sel  <= data_in[9:8];
                cond_out_sel <= data_in[14:12];
                shift_dir    <= data_in[16];
            end
            else if (address == 6'h18 && data_write_n == 2'b10)
            begin
                extra_in  <= data_in[9:8];
            end
            else if (address == 6'h28 && data_write_n == 2'b10)
            begin
                count1_preload <= data_in[23:0];
                count2_compare <= data_in[31:28];
            end

            // Latch comm_data
            if (address == 6'h18 && data_write_n == 2'b10)
                comm_data <= data_in[7:0];
            else if (prism_out_data[12])
                comm_data <= shift_dir ? {comm_in, comm_data[7:1]}: {comm_data[6:0], comm_in};

            // Countdown to zero counter
            if (!prism_halt && (count1 != 0) && prism_out_data[7] && !prism_out_data[8])
            begin
                count1 <= count1 - 1;
            end
            else
            begin
                if (prism_enable && !prism_halt && prism_out_data[8] && !prism_out_data[7])
                    count1 <= count1_preload; 
            end

            // 4-bit counter
            if (!prism_halt && prism_out_data[9] && !prism_out_data[10])
            begin
                count2 <= count2 + 1;
            end
            else
            begin
                if (prism_enable && !prism_halt && prism_out_data[10] && !prism_out_data[9])
                    count2 <= 4'h0; 
            end

            // Latch the lower 5 outputs
            if (!prism_halt && prism_out_data[11])
            begin
                latched_out <= prism_out_data[3:0];
                latched_in  <= ui_in[1:0];
            end
        end
    end

    assign prism_in_data[10] = count1 == 0;
    assign prism_in_data[11] = count2 == count2_compare;

    assign user_interrupt = prism_interrupt;

    // List all unused inputs to prevent warnings
    // data_read_n is unused as none of our behaviour depends on whether
    // registers are being read.
    wire _unused = &{data_read_n, 1'b0};

endmodule

// vim: et sw=4 ts=4

