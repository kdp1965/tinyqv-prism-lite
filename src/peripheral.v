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

    localparam WIDTH = 80;
    localparam DEPTH = 8;

    wire                   config_write;
    wire [WIDTH-1:0]       config_data;
    wire [DEPTH-1:0]       config_latch_en;
    wire                   config_busy;
    wire [WIDTH*DEPTH-1:0] config_bus;
    wire [WIDTH-1:0]       config_array [0:DEPTH-1];  // not Verilog-2001 legal, but we’ll work around that

    // Implement a 32-bit read/write register at address 0
    reg [31:0] example_data;
    always @(posedge clk) begin
        if (!rst_n) begin
            example_data <= 0;
        end else begin
            if (address == 6'h0) begin
                if (data_write_n != 2'b11)              example_data[7:0]   <= data_in[7:0];
                if (data_write_n[1] != data_write_n[0]) example_data[15:8]  <= data_in[15:8];
                if (data_write_n == 2'b10)              example_data[31:16] <= data_in[31:16];
            end
        end
    end

    // The bottom 8 bits of the stored data are added to ui_in and output to uo_out.
    assign uo_out = example_data[7:0] + ui_in;

    // Address 0 reads the example data register.  
    // Address 4 reads ui_in
    // All other addresses read 0.
    assign data_out = (address == 6'h0) ? example_data :
                      (address == 6'h4) ? {24'h0, ui_in} :
                      (address == 6'h8) ? config_array[DEPTH-1][31:0] : 
                      (address == 6'hc) ? {config_array[DEPTH-1][63:32]} :
                      (address == 6'h10) ? {16'h0, config_array[DEPTH-1][79:64]} :
                      32'h0;

    // All reads complete in 1 clock
    assign data_ready = 1;
    
    // User interrupt is generated on rising edge of ui_in[6], and cleared by writing a 1 to the low bit of address 8.
    reg example_interrupt;
    reg last_ui_in_6;

    always @(posedge clk) begin
        if (!rst_n) begin
            example_interrupt <= 0;
        end

        if (ui_in[6] && !last_ui_in_6) begin
            example_interrupt <= 1;
        end else if (address == 6'h8 && data_write_n != 2'b11 && data_in[0]) begin
            example_interrupt <= 0;
        end

        last_ui_in_6 <= ui_in[6];
    end

    assign user_interrupt = example_interrupt;

    // List all unused inputs to prevent warnings
    // data_read_n is unused as none of our behaviour depends on whether
    // registers are being read.
    wire _unused = &{data_read_n, 1'b0};

    /*
    ================================================================================ 
    The PRISM latch based CONFIG data
    ================================================================================ 
    */
    assign config_write = (address == 6'h8 || address == 6'hC || address == 6'h10) && (data_write_n == 2'b10);
    latch_loader prism_config_loader
    (
        .clk          ( clk             ),
        .rst_n        ( rst_n           ),
        .write_req    ( config_write    ),
        .address      ( address         ),
        .data_in      ( data_in         ),
        .config_data  ( config_data     ),
        .busy         ( config_busy     ),
        .latch_en     ( config_latch_en )
    );

    latch_shift_reg
    #(
        .DEPTH ( DEPTH ),
        .WIDTH ( WIDTH )
    )
    i_latch_shift_reg
    (
`ifdef USE_POWER_PINS
        .VGND(VGND),
        .VPWR(VPWR),
`endif
        .rst_n        ( rst_n           ),
        .data_in      ( config_data     ),
        .latch_en     ( config_latch_en ),
        .data_out     ( config_bus      )
    );

    genvar i;
    generate
        for (i = 0; i < DEPTH; i = i + 1) begin : unpack_config
            assign config_array[i] = config_bus[(i+1)*WIDTH-1 -: WIDTH];
        end
    endgenerate
 

endmodule

// vim: et sw=4 ts=4

