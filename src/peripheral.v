/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
module tqvp_prism (
`ifdef USE_POWER_PINS
    input  wire VGND,
    input  wire VPWR,
`endif
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

    reg         prism_reset;
    reg         prism_enable;
    reg         prism_halt_r;
    reg         prism_interrupt;
    reg   [8:0] extra_in;
    wire        prism_wr;
    wire [15:0] prism_in_data;
    wire [12:0] prism_out_data;
    wire [31:0] prism_read_data;
//    wire        prism_cond_out;
    wire        prism_halt;

    // Instantiate the prism controller
    prism i_prism
    (
        .clk                ( clk               ),
        .rst_n              ( rst_n             ),

`ifdef USE_POWER_PINS
        .VGND               ( VGND              ),
        .VPWR               ( VPWR              ),
`endif
                                                
        .debug_reset        ( prism_reset       ),
        .fsm_enable         ( prism_enable      ),
        .in_data            ( prism_in_data     ),
        .out_data           ( prism_out_data    ),
//        .cond_out           ( prism_cond_out    ),
                            
        .debug_addr         ( address           ),
        .debug_wr           ( prism_wr          ),
        .debug_wdata        ( data_in           ),
        .debug_rdata        ( prism_read_data   ),
        .debug_halt_either  ( prism_halt        )
    );

    assign prism_wr = data_write_n == 2'b10;

    // The We don't use uo_out0 so it can be used for comms with RISC-V
    assign uo_out = {prism_out_data[6:0], 1'b0};
    
    // Assign the PRISM intput data
    assign prism_in_data[6:0] = ui_in[6:0];
    assign prism_in_data[15:7] = extra_in;

    // Address 0 reads the example data register.  
    // Address 4 reads ui_in
    // All other addresses read 0.
    assign data_out = (address == 6'h0) ?
                      {prism_interrupt, prism_reset, prism_enable, prism_read_data[28:0]} :
                       prism_read_data;

    // All reads complete in 1 clock
    assign data_ready = 1;
    
    // User interrupt is generated on rising edge of ui_in[6], and cleared by writing a 1 to the low bit of address 8.

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            prism_interrupt <= 0;
            prism_halt_r    <= 0;
            extra_in        <= '0;
        end
        else
        begin
            // Detect rising edge of HALT
            prism_halt_r <= prism_halt;
            
            if (prism_halt && !prism_halt_r) begin
                prism_interrupt <= 1;
            end else if (address == 6'h0 && data_write_n == 2'b10)
            begin
                // Test for interrupt clear
                if (data_in[31])
                    prism_interrupt <= 0;

                // FSM Enable and reset bits
                prism_reset  <= data_in[30];
                prism_enable <= data_in[29];
            end
            else if (address == 6'h18 && data_write_n == 2'b10)
                extra_in <= data_in[8:0];
        end
    end

    assign user_interrupt = prism_interrupt;

    // List all unused inputs to prevent warnings
    // data_read_n is unused as none of our behaviour depends on whether
    // registers are being read.
    wire _unused = &{data_read_n, 1'b0};

endmodule

// vim: et sw=4 ts=4

