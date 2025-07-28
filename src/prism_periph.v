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

    localparam  OUT_COUNT1_DEC      = 7;
    localparam  OUT_COUNT1_LOAD     = 8;
    localparam  OUT_COUNT2_INC      = 9;
    localparam  OUT_COUNT2_CLEAR    = 10;
    localparam  OUT_LATCH           = 11;
    localparam  OUT_SHIFT           = 12;

    reg                 prism_reset;
    reg                 prism_enable;
    reg                 prism_halt_r;
    reg                 prism_interrupt;
    reg   [1:0]         extra_in;
    wire                prism_wr;
    wire [15:0]         prism_in_data;
    wire [OUTPUTS-1:0]  prism_out_data;
//    wire [OUTPUTS-1:0]  debug_dout_share;
    wire [31:0]         prism_read_data;
    reg  [23:0]         count1_preload;
    reg  [23:0]         count1;
    reg   [3:0]         count2;
    reg   [3:0]         count2_compare;
    reg   [1:0]         latched_ctrl;
    reg   [1:0]         latched_out;
    reg   [1:0]         latched_in;
    reg   [7:0]         comm_data;
    reg   [1:0]         comm_in_sel;
    reg   [2:0]         cond_out_sel;
    reg                 shift_dir;
    reg                 shift_24;
    reg                 shift_out_mode;
//    reg                 shift_out_sel;
//    reg   [1:0]         shift_out_en;
    reg   [4:0]         shift_count;
    wire  [6:0]         cond_out_en;
    wire  [0:0]         cond_out;
    wire                comm_in;
    wire  [3:0]         comm_data_bits;
    wire                prism_halt;
    wire                shift_data;
    wire                prism_exec;

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
//        .debug_dout_share   ( debug_dout_share  ),
                            
        .debug_addr         ( address           ),
        .debug_wr           ( prism_wr          ),
        .debug_wdata        ( data_in           ),
        .debug_rdata        ( prism_read_data   ),
        .debug_halt_either  ( prism_halt        )
    );

    assign prism_wr = data_write_n == 2'b10;
    assign prism_exec = prism_enable && !prism_halt;

    genvar i;
    generate
    for (i = 0; i < 7; i = i + 1)
    begin : GEN_COND_OUT_EN
        assign cond_out_en[i] = cond_out_sel == i;    
    end
//    for (i = 0; i < 2; i = i + 1)
//    begin : GEN_SHIFT_OUT_EN
//        assign shift_out_en[i] = shift_out_sel == i;    
//    end
    endgenerate

    // We don't use uo_out0 so it can be used for comms with RISC-V
    // Assign outputs based on conditional enable or latched enable
    assign uo_out[2:1] = (cond_out_en[1:0] & {2{cond_out[0]}}) | (~cond_out_en[1:0] & ((latched_ctrl & latched_out) | (~latched_ctrl & prism_out_data[1:0])));
//    assign uo_out[4:3] = (cond_out_en[3:2] & {2{cond_out[0]}}) | (~cond_out_en[3:2] & ((shift_out_en & {2{shift_data}}) | (~shift_out_en & ~prism_out_data[3:2])));
//    assign uo_out[7:5] = (cond_out_en[6:4] & {3{cond_out[0]}}) | (~cond_out_en[6:4] & prism_out_data[6:4]);
    assign uo_out[7:3] = (cond_out_en[6:2] & {5{cond_out[0]}}) | (~cond_out_en[6:2] & prism_out_data[6:4]);
    assign uo_out[0] = 1'b0;
    
    // Assign the PRISM intput data
    assign prism_in_data[6:0]   = ui_in[6:0];
    assign prism_in_data[7]     = shift_data;
    assign prism_in_data[9:8]   = extra_in;
    assign prism_in_data[13:12] = latched_in ^ ui_in[1:0];
    assign prism_in_data[14]    = shift_count == 5'h0;
    assign prism_in_data[15]    = 1'b0;

    assign shift_data = shift_24 ? (shift_dir ? count1[0] : count1[23]) : (shift_dir ? comm_data[0] : comm_data[7]);

    // Address 0 reads the example data register.  
    // Address 4 reads ui_in
    // All other addresses read 0.
    assign data_out = address == 6'h0  ? {prism_interrupt, prism_reset, prism_enable, 5'b0,
                                          //2'h0, shift_out_mode, shift_out_sel, 2'h0, shift_24, shift_dir,
                                          4'h0, 2'h0, shift_24, shift_dir,
                                          1'b0, cond_out_sel, 2'b0, comm_in_sel,
                                          2'h0, latched_out, 2'h0, latched_ctrl} :
                      address == 6'h18 ? {22'h0, extra_in, comm_data} :
                      address == 6'h28 ? {3'h0, count2, count1} :
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
            count1          <= 24'b0;
            count2          <= 4'b0;
            latched_ctrl    <= 2'b0;
            latched_out     <= 2'h0;
            latched_in      <= 2'h0;
            comm_data       <= 8'h0;
            comm_in_sel     <= 2'h0;
            cond_out_sel    <= 3'h0;
            shift_dir       <= 1'b0;
            shift_24        <= 1'b0;
            shift_count     <= 5'h0;
            //shift_out_mode  <= 1'b0;
            //shift_out_sel   <= 1'h0;
        end
        else
        begin
            // Detect rising edge of HALT
            prism_halt_r <= prism_halt;
            
            if ((prism_halt && !prism_halt_r) | (prism_out_data[OUT_COUNT2_CLEAR] & prism_out_data[OUT_COUNT2_INC])) begin
                prism_interrupt <= 1;
            end else if (address == 6'h0 && data_write_n == 2'b10)
            begin
                // Test for interrupt clear
                if (data_in[31])
                    prism_interrupt <= 0;

                // FSM Enable and reset bits
                prism_reset    <= data_in[30];
                prism_enable   <= data_in[29];
                latched_ctrl   <= data_in[1:0];
                comm_in_sel    <= data_in[9:8];
                cond_out_sel   <= data_in[14:12];
                shift_dir      <= data_in[16];
                shift_24       <= data_in[17];
                //shift_out_sel  <= data_in[20];
                //shift_out_mode <= data_in[21];
            end
            else if (address == 6'h18 && data_write_n == 2'b10)
            begin
                extra_in  <= data_in[9:8];
            end
            else if (address == 6'h28 && data_write_n == 2'b10)
            begin
                count1_preload <= data_in[23:0];
                count2_compare <= data_in[27:24];
            end

            // Latch comm_data
            if (address == 6'h18 && data_write_n == 2'b10)
                comm_data <= data_in[7:0];
            else if (prism_exec && !shift_24 && prism_out_data[OUT_SHIFT])
                comm_data <= shift_dir ? {comm_in, comm_data[7:1]}: {comm_data[6:0], comm_in};

            // Countdown to zero counter
            if (prism_exec)
            begin
                // Logic for load / decrement of 24-bit countdown counter
                if (prism_out_data[OUT_COUNT1_LOAD])
                    count1 <= count1_preload; 
                else if (count1 != 0 && prism_out_data[OUT_COUNT1_DEC])
                    count1 <= count1 - 1;

                // Use 24-bit counter as shift-register
                else if (shift_24 && prism_out_data[OUT_SHIFT])
                    count1 <= shift_dir ? {comm_in, count1[23:1]} : {count1[22:0], comm_in};

                // Count the number of shifts
                if (prism_out_data[OUT_SHIFT])
                begin
                    if (shift_24 || (!shift_24 && shift_count != 5'h7))
                        shift_count <= shift_count + 1;
                    else 
                        shift_count <= 5'h0;
                end

                // 4-bit counter
                if (prism_out_data[OUT_COUNT2_CLEAR] && !prism_out_data[OUT_COUNT2_INC])
                    count2 <= 4'h0; 
                else if (prism_out_data[OUT_COUNT2_INC] && !prism_out_data[OUT_COUNT2_CLEAR])
                    count2 <= count2 + 1;
                
                // Latch the lower 2 outputs
                if (prism_out_data[OUT_LATCH])
                begin
                    latched_out <= prism_out_data[1:0];
                    latched_in  <= ui_in[1:0];
                end
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

