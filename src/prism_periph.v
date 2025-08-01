/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
module tqvp_prism (
    input             clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input             rst_n,        // Reset_n - low to reset.
               
    input      [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                    // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.
               
    output     [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                    // Note that uo_out[0] is normally used for UART TX.

    input     [5:0]   address,      // Address within this peripheral's address space
    input     [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input     [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input     [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    
    output reg [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output            data_ready,

    output        user_interrupt    // Dedicated interrupt request for this peripheral
);

    localparam  OUTPUTS = 12;

    localparam  OUT_COUNT2_DEC      = 5;
    localparam  OUT_SHIFT           = 6;
    localparam  OUT_COUNT1_DEC      = 7;
    localparam  OUT_COUNT1_LOAD     = 8;
    localparam  OUT_COUNT2_INC      = 9;
    localparam  OUT_COUNT2_CLEAR    = 10;
    localparam  OUT_LATCH           = 11;

    wire                prism_reset;
    wire                prism_enable;
    reg                 prism_halt_r;
    reg                 prism_interrupt;
    reg   [1:0]         host_in;
    wire                prism_wr;
    wire [15:0]         prism_in_data;
    wire [OUTPUTS-1:0]  prism_out_data;
    wire [31:0]         prism_read_data;
    reg  [23:0]         count1;
    reg   [7:0]         count2;
    wire [23:0]         count1_preload;
    wire  [7:0]         count2_compare;
    wire                raw_out;
    reg   [6:0]         latched_out;
    reg   [1:0]         latched_in;
    reg   [7:0]         comm_data;
    wire  [1:0]         comm_in_sel;
    wire  [1:0]         cond_out_sel;
    wire  [1:0]         shift_out_sel;
    wire  [3:0]         shift_out;
    wire                shift_count_mode;
    wire  [4:0]         shift_compare;
    wire  [3:0]         comb_out;
    wire                shift_dir;
    wire                shift_24;
    wire                fifo_24;
    wire                count2_dec;
    wire                latch_in_out;
    reg   [2:0]         shift_count;
    reg   [31:0]        latch_data;
    reg                 latch_wr;
    reg                 latch_wr_p0;
    wire  [3:0]         cond_out_en;
    wire  [0:0]         cond_out;
    wire                comm_in;
    wire  [3:0]         comm_data_bits;
    wire                prism_halt;
    wire                shift_data;
    wire                prism_exec;
    wire                count_reg_en;
    wire                ctrl_reg_en;
    reg   [1:0]         fifo_wr_ptr;
    reg   [1:0]         fifo_rd_ptr;
    reg   [1:0]         fifo_count;
    wire                fifo_write;
    wire                fifo_read;
    reg   [7:0]         fifo_rd_data;
    wire                fifo_full;
    wire                fifo_empty;
    wire  [6:0]         uo_out_c;
    wire                clk_div2;
    reg                 clk_gate;

    // =============================================================
    // Crate a divide by 2 clock using clock gate
    // =============================================================
    always @(posedge clk or negedge rst_n)
    begin
        if (~rst_n)
            clk_gate <= 1'b0;
        else if (prism_enable)
            clk_gate <= ~clk_gate;
    end

`ifdef SIM
    assign clk_div2 = clk_gate & clk;
`else
    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__dlclkp_4 CG( .CLK(clk), .GCLK(clk_div2), .GATE(clk_gate) );
    /* verilator lint_on PINMISSING */
`endif
    
    // =============================================================
    // Instantiate the PRISM controller
    // =============================================================
    prism
    #(
        .OUTPUTS ( OUTPUTS )
     )
    i_prism
    (
        .clk                ( clk               ),
        .clk_div2           ( clk_div2          ),
        .rst_n              ( rst_n             ),

        .debug_reset        ( prism_reset       ),
        .fsm_enable         ( prism_enable      ),
        .in_data            ( prism_in_data     ),
        .out_data           ( prism_out_data    ),
        .cond_out           ( cond_out          ),
                            
        // Latch register control
        .latch_data         ( latch_data        ),
        .latch_wr           ( latch_wr          ),

        .debug_addr         ( address           ),
        .debug_wr           ( prism_wr          ),
        .debug_wdata        ( data_in           ),
        .debug_rdata        ( prism_read_data   ),
        .debug_halt_either  ( prism_halt        )
    );

    assign prism_wr = data_write_n != 2'b11;
    assign prism_exec = prism_enable && !prism_reset && !prism_halt;

    genvar i;
    generate
    
    // Create Conditional out enable bits
    for (i = 1; i < 4; i = i + 1)
    begin : GEN_COND_OUT_EN
        assign cond_out_en[i] = cond_out_sel == i;    
    end
    assign cond_out_en[0] = 1'b0;

    // Create shift out enable bits
    for (i = 0; i < 4; i = i + 1)
    begin : GEN_SHIFTS_OUT_EN
        assign shift_out[i] = i == 0 ? 1'b0 : shift_out_sel == i;    
        assign comb_out[i]  = ~shift_out[i] & raw_out;    
    end

    endgenerate

    // We don't use uo_out0 so it can be used for comms with RISC-V
    // Assign outputs based on conditional enable or latched enable
    assign uo_out_c[0] = prism_out_data[0];
    assign uo_out_c[3:1] = prism_out_data[3:1];
    assign uo_out_c[6:4] = (cond_out_en[3:1] & {3{cond_out[0]}}) | (~cond_out_en[3:1] & prism_out_data[6:4]);

    assign uo_out[1]   = (~raw_out & latched_out[0]) | (raw_out & prism_out_data[0]);
    assign uo_out[4:2] = ({3{~raw_out}} & latched_out[3:1]) | (comb_out & uo_out_c[3:1]) | (shift_out[3:1] & {3{shift_data}});
    assign uo_out[7:5] = ({2{~raw_out}} & latched_out[6:4]) | ({2{raw_out}} & uo_out_c[6:4]);
    assign uo_out[0]   = prism_out_data[OUT_LATCH];
    
    // Assign the PRISM intput data
    assign prism_in_data[6:0]   = ui_in[6:0];
    assign prism_in_data[7]     = shift_data;
    assign prism_in_data[9:8]   = host_in;
    assign prism_in_data[13:12] = latch_in_out ? {latched_out[6], latched_out[1]} : (latched_in ^ ui_in[1:0]);
    assign prism_in_data[14]    = shift_24 ? ({fifo_count, shift_count} == shift_compare) : (shift_count == shift_compare[2:0]);
    assign prism_in_data[15]    = count2 == comm_data;
    assign shift_compare        = shift_count_mode ? 5'h1F : 5'h0;

    //assign shift_data = shift_24 ? (shift_dir ? count1[0] : count1[23]) : (shift_dir ? comm_data[0] : comm_data[7]);
    assign shift_data = shift_24 ? (shift_dir ? count1[0] : count1[23]) : (shift_dir ? comm_data[0] : comm_data[7]);
    assign fifo_write = prism_out_data[OUT_COUNT1_LOAD] & fifo_24 & clk_gate;
    assign fifo_read  = fifo_24 && data_read_n == 2'b00 && address == 6'h19;
    assign fifo_full  = fifo_24 && fifo_count == 2'h2;
    assign fifo_empty = fifo_24 && fifo_count == 2'h0;

    always @*
    begin
        case (fifo_rd_ptr)
        2'h0:    fifo_rd_data = count1[7:0];
        2'h1:    fifo_rd_data = count1[15:8];
        2'h2:    fifo_rd_data = count1[23:16];
        default: fifo_rd_data = 8'h0;
        endcase
    end

    // Address 0 reads the example data register.  
    // Address 4 reads ui_in
    // All other addresses read 0.
    always @*
    begin
        case (address)
            6'h0:    data_out = {prism_interrupt, prism_reset, prism_enable, ui_in[7], count2_dec, fifo_24, shift_24, shift_dir,
                                latch_in_out, 1'b0, cond_out_sel, shift_out_sel, comm_in_sel,
                                1'h0, latched_out,
                                6'h0, shift_count_mode, raw_out};
            6'h18:   data_out = {6'h0, host_in, 6'h0, fifo_full, fifo_empty, fifo_rd_data, comm_data};
            6'h19:   data_out = {24'h0, fifo_rd_data};
            6'h1A:   data_out = {30'h0, fifo_full, fifo_empty};
            6'h1B:   data_out = {30'h0, host_in};
            6'h20:   data_out = {count2_compare, count1_preload};
            6'h24:   data_out = {count2, count1};
            default: data_out = prism_read_data;
        endcase
    end

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
            prism_interrupt <= 1'b0;
            prism_halt_r    <= 1'b0;
            host_in         <= 2'b0;
            comm_data       <= 8'h0;
            latch_wr        <= 1'b0;
            latch_wr_p0     <= 1'b0;
            latch_data      <= 32'h0;
            fifo_rd_ptr     <= 2'h0;
            fifo_count      <= 2'h0;
        end
        else
        begin
            // Create a delayed data_write signal for latches
            latch_wr_p0 <= prism_wr;
            latch_wr    <= latch_wr_p0;

            // Save data_in for latch and config writes
            if (prism_wr)
                latch_data <= data_in;

            // Detect rising edge of HALT
            prism_halt_r <= prism_halt;
            
            if ((prism_halt && !prism_halt_r) | (prism_out_data[OUT_COUNT2_CLEAR] & prism_out_data[OUT_COUNT2_INC])) begin
                prism_interrupt <= 1;
            end else if (address == 6'h0 && prism_wr)
            begin
                // Test for interrupt clear
                if (data_in[31])
                    prism_interrupt <= 0;
            end

            // Test for write to PRISM control bits
            if (address == 6'h18 && data_write_n == 2'b10)
                host_in  <= data_in[25:24];
            else if (address == 6'h1b && data_write_n == 2'b00)
                host_in  <= data_in[1:0];

            // Latch comm_data
            if (address == 6'h18 && data_write_n != 2'b11)
                comm_data <= data_in[7:0];
            else if (prism_exec && !shift_24 && prism_out_data[OUT_SHIFT] && clk_gate)
                comm_data <= shift_dir ? {comm_in, comm_data[7:1]}: {comm_data[6:0], comm_in};

            if (prism_exec)
            begin
                // Manage fifo read pointer
                if (fifo_24 && fifo_read && (fifo_count != 2'h0 || fifo_write))
                begin
                    // Increment FIFO read pointer
                    if (fifo_rd_ptr == 2'h2)
                        fifo_rd_ptr <= 2'h0;
                    else
                        fifo_rd_ptr <= fifo_rd_ptr + 1;
                end

                // Manage fifo count
                if (fifo_24)
                begin
                    // Test for write with no read and not full
                    if (fifo_write && !fifo_read && fifo_count != 2'h2)
                        fifo_count <= fifo_count + 1;
                    // Test for read with no write and not empty
                    else if (fifo_read && !fifo_write && fifo_count != 2'h0)
                        fifo_count <= fifo_count - 1;
                end
                else if (shift_24 && clk_gate && prism_out_data[OUT_SHIFT] && shift_count == 3'h7)
                    fifo_count <= fifo_count + 1;
            end
        end
    end

    always @(posedge clk_div2 or negedge rst_n)
    begin
        if (!rst_n)
        begin
            count1          <= 24'b0;
            count2          <= 8'b0;
            fifo_wr_ptr     <= 2'h0;
            latched_out     <= 7'h0;
            latched_in      <= 2'h0;
            shift_count     <= 3'h0;
        end
        else
        begin
            // Countdown to zero counter
            if (prism_exec)
            begin
                // Logic for load / decrement of 24-bit countdown counter
                if (prism_out_data[OUT_COUNT1_LOAD] & !fifo_24)
                    count1 <= count1_preload; 

                // Logic to decrement 24-bit counter
                else if (count1 != 0 && prism_out_data[OUT_COUNT1_DEC])
                    count1 <= count1 - 1;

                // Use 24-bit counter as shift-register
                else if (shift_24 && prism_out_data[OUT_SHIFT])
                    count1 <= shift_dir ? {comm_in, count2[23:1]} :  {count1[22:0], comm_in};

                // Use 24-bit counter as 3-byte FIFO
                else if (fifo_write && (fifo_count != 2'h2 || (fifo_count == 2'h2 && fifo_read)))
                begin
                    // Push data to the fifo
                    case (fifo_wr_ptr)
                    2'h0: count1[7:0]   <= comm_data;
                    2'h1: count1[15:8]  <= comm_data;
                    2'h2: count1[23:16] <= comm_data;
                    default: 
                        begin
                        end
                    endcase

                    // Increment the write pointer
                    if (fifo_wr_ptr == 2'h2)
                        fifo_wr_ptr <= 0;
                    else
                        fifo_wr_ptr <= fifo_wr_ptr + 1;
                end

                latched_out <= uo_out_c;

                // Count the number of shifts
                if (prism_out_data[OUT_SHIFT])
                begin
                    shift_count <= shift_count + 1;
                end
                
                // 8-bit counter
                if (prism_out_data[OUT_COUNT2_CLEAR] && !prism_out_data[OUT_COUNT2_INC])
                    count2 <= 8'h0; 
                else if (prism_out_data[OUT_COUNT2_INC] && !prism_out_data[OUT_COUNT2_CLEAR])
                    count2 <= count2 + 1;
                else if (count2_dec && prism_out_data[OUT_COUNT2_DEC])
                    count2 <= count2 - 1;
                
                // Latch the lower 2 outputs
                if (prism_out_data[OUT_LATCH])
                begin
                    latched_in  <= ui_in[1:0];
                end
            end
        end
    end

    /*
    ==================================================================================
    Instantiate latch based registers
    ==================================================================================
    */
    assign ctrl_reg_en  = address == 6'h00;
    assign count_reg_en = address == 6'h20;

    wire [14:0]   ctrl_bits_in;
    wire [14:0]   ctrl_bits_out;

    assign ctrl_bits_in[0]     = latch_data[0];       // raw_out
    assign ctrl_bits_in[1]     = latch_data[1];       // shift_count_mode
    assign ctrl_bits_in[3:2]   = latch_data[17:16];   // comm_in_sel
    assign ctrl_bits_in[5:4]   = latch_data[19:18];   // shift_out_sel
    assign ctrl_bits_in[7:6]   = latch_data[21:20];   // cond_out_sel
    assign ctrl_bits_in[8]     = latch_data[22];      // latch_in_out
    assign ctrl_bits_in[9]     = latch_data[24];      // shift_dir
    assign ctrl_bits_in[10]    = latch_data[25];      // shift_24
    assign ctrl_bits_in[11]    = latch_data[26];      // fifo_24
    assign ctrl_bits_in[12]    = latch_data[27];      // count2_dec
    assign ctrl_bits_in[13]    = latch_data[29];      // PRISM enable
    assign ctrl_bits_in[14]    = latch_data[30];      // PRISM reset

    assign raw_out             = ctrl_bits_out[0];
    assign shift_count_mode    = ctrl_bits_out[1];
    assign comm_in_sel         = ctrl_bits_out[3:2];
    assign shift_out_sel       = ctrl_bits_out[5:4];
    assign cond_out_sel        = ctrl_bits_out[7:6];
    assign latch_in_out        = ctrl_bits_out[8];
    assign shift_dir           = ctrl_bits_out[9];
    assign shift_24            = ctrl_bits_out[10];
    assign fifo_24             = ctrl_bits_out[11];
    assign count2_dec          = ctrl_bits_out[12];
    assign prism_enable        = ctrl_bits_out[13];
    assign prism_reset         = ctrl_bits_out[14];

    prism_latch_reg
    #(
        .WIDTH ( 15 )
     )
    ctrl_regs
    (
        .rst_n      ( rst_n         ),
        .enable     ( ctrl_reg_en   ),
        .wr         ( latch_wr      ),
        .data_in    ( ctrl_bits_in  ),
        .data_out   ( ctrl_bits_out )
    );

    prism_latch_reg
    #(
        .WIDTH ( 32 )
     )
    count_preloads
    (
        .rst_n      ( rst_n                            ),
        .enable     ( count_reg_en                     ),
        .wr         ( latch_wr                         ),
        .data_in    ( latch_data                       ),
        .data_out   ( {count2_compare, count1_preload} )
    );

    assign prism_in_data[10] = count1 == 0;
    assign prism_in_data[11] = count2 == count2_compare;

    assign user_interrupt = prism_interrupt;

    // List all unused inputs to prevent warnings
    // data_read_n is unused as none of our behaviour depends on whether
    // registers are being read.
    wire _unused = &{data_read_n, 1'b0};

endmodule

// vim: et sw=4 ts=4

