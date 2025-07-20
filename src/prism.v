// (c) Copyright Ken Pettit
//         All Rights Reserved
// ------------------------------------------------------------------------------
//
//  File        : prism.sv
//  Revision    : 1.2
//  Author      : Ken Pettit
//  Created     : 05/09/2015
//
// ------------------------------------------------------------------------------
//
// Description:  
//    This is a Programmable Reconfigurable Indexed State Machine (PRISM)
//
//                        /\           
//                       /  \           
//                   ..-/----\-..       
//               --''  /      \  ''--   
//                    /________\        
//
// Modifications:
//
//    Author  Date      Rev  Description
//    ======  ========  ===  ================================================
//    KP      05/09/15  1.0  Initial version
//    KP      12/07/17  1.1  Modified the input stage to use muxed inputs
//                           with config space select bits, added AND/OR/XOR
//                           and invert capability, added dual compare logic,
//                           added state transition outputs and conditional
//                           outputs, added SI loop mode when si_inc active.
//    KP      12/13/17  1.2  Added Reconfigurability / Fracturability.
//
// ------------------------------------------------------------------------------


/*
=====================================================================================

    Theory of operation:
                                                                        
    +-------------+     +--------------------------------------------------+
    |   Current   |  5  | State Information Table (SIT)                    |
    | State Index +--/->|                                                  |
    |    (SI)     |     | Output: STate Execution Word (STEW)              |
    +-------------+     ++--------+---------+--------------+-+-------------+
         ^ Next SI       |        |LUT      |NewSI         | |
         |               |        |Data     |              | | Transition
         |               |        |(16)     | 5  |\        | |   Outputs     |\  
         |     Input     |        |         +-/->|1|       | +-------------->|1| Output Values
         |     Select    |        |              | +----+  |  State Outputs  | +--------------> 
         |     Muxes (4) |        v    CurrSI -->|0|    |  +---------------->|0|
         |           -->|\      +-------+        |/     |                    |/ 
         |            o | |  3  |       |         |     |                     |
         |    Inputs  o | +--/->|  LUT  +---------*-----|---------------------+
         |            o | |     |       | New State?    |                   
         |           -->|/      +-------+               |
         |                                              |
         +----------------------------------------------+
                                                
    1.  The current State Index (SI) is used as the address to a RAM (State Information Table - SIT)                                            
    2.  The RAM output word is the STate Execution Word (STEW).
    3.  While in the current state (SI), output values are driven from STEW bits.
    4.  Four (4) inputs are MUXed from the 32 available via STEW bits and sent to the LUT.
    5.  The 4-input LUT is programmed from 16 STEW bits to give a "Goto New State?" decision.
    6.  If the LUT output is HIGH, the FSM goes to the NewSI (from the STEW) state.
    7.  During a transition to a NewSI state, the output values are driven with "Transition" values.
    8.  Also (not shown) are a limited number of Conditional Outputs. In any given state, a 
        conditional output will be determined only by the input values base on a LUT.
    9.  The PRISM is Fracturable, meaning it can be fractured into two (somewhat) independent shards
        (state machines), each with it's own SI.  The SI[0] FSM will have 1/2 of the states and
        the SI[1] will have the remainder (on a power of 2 basis).  If there were 24 states, then:

           SI[0] - 16 states
           SI[1] - 8  states
                                                                                         
    10. In the fractured mode, there are output mask bit registers that assign
        outputs to specific shard. 
    11. The FSM (or each shard) can be debugged.  There are 2 breakpoints for each
        that stop the FSM at a specified state.  Also, the FSM can be halted via
        register interface and single stepped.
=====================================================================================
*/
module prism
 #(
   parameter  DEPTH          = 12,                 // Total number of available states
   parameter  INPUTS         = 16,                 // Total number of Input to the module
   parameter  OUTPUTS        = 11,                 // Nuber of FSM outputs
   parameter  COND_OUT       = 0,                  // Number of conditional outputs
   parameter  COND_LUT_SIZE  = 2,                  // Size (inputs) for COND decision tree LUT
   parameter  STATE_INPUTS   = 3,                  // Number of parallel state input muxes
   parameter  DUAL_COMPARE   = 0,
   parameter  FRACTURABLE    = 1,
   parameter  LUT_SIZE       = 3,
   parameter  INCLUDE_DEBUG  = 1,
   parameter  SI_BITS        = DEPTH > 32 ? 6 :
                               DEPTH > 16 ? 5 :
                               DEPTH > 8  ? 4 :
                               DEPTH > 4  ? 3 :
                               DEPTH > 2  ? 2 : 1,
   parameter  INPUT_BITS     = INPUTS > 32 ? 6 :
                               INPUTS > 16 ? 5 :
                               INPUTS > 8  ? 4 :
                               INPUTS > 4  ? 3 :
                               INPUTS > 2  ? 2 : 1,
   parameter  COND_LUT_BITS  = 2**COND_LUT_SIZE,
   parameter  RAM_WIDTH      = STATE_INPUTS   * INPUT_BITS       + // Input mux sel bits
                               (2**LUT_SIZE)  * (DUAL_COMPARE+1) + // AND/OR Invert per jump state
                               SI_BITS        * (DUAL_COMPARE+1) + // JumpTo state bits
                               OUTPUTS        * (DUAL_COMPARE+2) + // Output Bits 
                               COND_LUT_BITS  * COND_OUT         + // Conditional output bits
                               1,                                  // Increment bit
   parameter  RAM_DWIDTH     = RAM_WIDTH > 96 ? 128 : 
                               RAM_WIDTH > 64 ? 96  :
                               RAM_WIDTH > 32 ? 64  : 32,
   parameter  W_ADDR         = 8
  )
  (
`ifdef USE_POWER_PINS
    input             VPWR,
    input             VGND,
`endif
   // Timing inputs
   input   wire                  clk,              // System clock 
   input   wire                  rst_n,            // TRUE when receiving Bit 0
   input   wire                  debug_reset,
   input   wire                  fsm_enable,       // Enable signal

   // Symbol and other state detect inputs
   input   wire [INPUTS-1:0]     in_data,          // The input data

   // Output data
   output  wire [OUTPUTS-1:0]    out_data,         // Bit Slip pulse back to SerDes
   output  wire [COND_OUT-1:0]   cond_out,         // Conditional outputs

   // ============================
   // Debug bus for programming
   // ============================
   input  wire [W_ADDR-1:0]      debug_addr,         // Debug address
   input  wire                   debug_wr,           // Active HIGH write strobe
   input  wire [31:0]            debug_wdata,        // Debug write data
   output wire [31:0]            debug_rdata,        // Debug read data
   output wire                   debug_halt_either
  );


   localparam W_PAR_IN    = INPUT_BITS;
   localparam HALF_IN     = STATE_INPUTS / 2;
   localparam DEPTH_HALF  = DEPTH > 256 ? 256 : DEPTH > 128 ? 128 : DEPTH > 64 ? 64 : DEPTH > 32 ? 32 : 
                            DEPTH > 16 ? 16 : DEPTH > 8 ? 8 : DEPTH > 4 ? 4 : DEPTH > 2 ? 2 : 1;
   localparam DEPTH_REM   = DEPTH - DEPTH_HALF;
   localparam DH_BITS     = DEPTH_HALF == 256 ? 8 : DEPTH_HALF == 128 ? 7 : DEPTH_HALF == 64 ? 6 :
                            DEPTH_HALF == 32 ? 5 : DEPTH_HALF == 16 ? 4 : DEPTH_HALF == 8 ? 3 : 
                            DEPTH_HALF == 4 ? 2 : 1;
   localparam DR_BITS     = DEPTH_REM == 256 ? 8 : DEPTH_REM == 128 ? 7 : DEPTH_REM == 64 ? 6 :
                            DEPTH_REM == 32 ? 5 : DEPTH_REM == 16 ? 4 : DEPTH_REM == 8 ? 3 : 
                            DEPTH_REM == 4 ? 2 : 1;
   localparam CMP_SEL_SIZE= 2**LUT_SIZE;
   localparam W_DBG_CTRL  = SI_BITS*3 + 6;
   localparam RAM_DEPTH   = DEPTH;
   localparam RAM_DEPTH1  = RAM_DEPTH / 2;
   localparam RAM_DEPTH0  = RAM_DEPTH - RAM_DEPTH1;
   localparam DBG_MSB_BITS= ((RAM_DEPTH1 + RAM_DEPTH0) > 4 ? 3 :
                             (RAM_DEPTH1 + RAM_DEPTH0) > 2 ? 2 : 1);
   localparam DBG_A_BITS  = 3 + DBG_MSB_BITS;

   reg                        cfg_program;
   reg                        fsm_enable_comb;        // Enable signal
   reg                        fsm_enable_int;         // Enable signal
   reg                        fsm_enable_pin_disable; // Disable for fsm_enable input pin 
   reg                        cfg_fractured;

   // Signal declarations
   reg   [SI_BITS-1:0]        curr_si[1:0];         // Current State Index value
   reg   [SI_BITS-1:0]        next_si[1:0];         // Next State Index value
   reg   [SI_BITS-1:0]        loop_si[1:0];         // Loop State Index value
   reg                        loop_valid[1:0];      // Indiactes if loop_si value is valid
   reg   [SI_BITS-1:0]        debug_si[1:0];        // Current State Index value
   reg                        debug_new_si_p1[1:0];     // Current State Index value
   reg                        debug_new_si_p2[1:0];     // Current State Index value
   reg                        debug_new_si_p3[1:0];     // Current State Index value

   // Signals to create parallel input muxes
   wire  [W_PAR_IN-1:0]       input_mux_sel [ FRACTURABLE:0 ] [ STATE_INPUTS-1:0 ];
   reg                        input_mux_out_c [ FRACTURABLE:0 ] [ STATE_INPUTS-1:0 ];
   wire                       input_mux_out   [ FRACTURABLE:0 ] [ STATE_INPUTS-1:0 ];

   // RAM interface signals for output values
   wire  [OUTPUTS-1:0]        state_outputs [ FRACTURABLE:0 ];                // Output values from RAM
   wire  [OUTPUTS-1:0]        jump_outputs  [ FRACTURABLE:0 ] [ DUAL_COMPARE:0 ]; // Jumpto transition Output values

   // RAM interface signals for SI control
   wire  [SI_BITS-1:0]        jump_to [ FRACTURABLE:0 ] [ DUAL_COMPARE:0 ];      // SI Jump to address
   wire                       inc_si  [ FRACTURABLE:0 ];                       // SI Inc signal

   // Compare signals from RAM
   wire  [CMP_SEL_SIZE-1:0]   cmp_sel [ FRACTURABLE:0 ] [ DUAL_COMPARE:0 ];
		
   // Signals for doing input compare and muxing
   wire  [DUAL_COMPARE:0]     compare_match [ FRACTURABLE:0 ];

   // Conditional out control signals
   wire  [COND_LUT_BITS-1:0]  cond_cfg    [ FRACTURABLE:0 ] [ COND_OUT-1:0 ];
   wire  [1:0]                cond_in     [ FRACTURABLE:0 ] [ COND_OUT-1:0 ];
   wire                       cond_out_c  [ FRACTURABLE:0 ] [ COND_OUT-1:0 ];
   wire                       cond_out_m  [ FRACTURABLE:0 ] [ COND_OUT-1:0 ];

   // Output data masking
   wire  [OUTPUTS-1:0]        out_data_c  [ FRACTURABLE:0 ];
   wire  [OUTPUTS-1:0]        out_data_m  [ FRACTURABLE:0 ];
   wire  [OUTPUTS-1:0]        out_data_fsm;        // FSM outputs
   
   // Memory control signals
   wire  [RAM_WIDTH-1:0]      ram_dout_c  [ 1:0 ];
   wire  [RAM_WIDTH-1:0]      ram_dout    [ FRACTURABLE:0 ];
   wire  [DH_BITS-1:0]        ram_raddr1;
   wire  [DR_BITS-1:0]        ram_raddr2;
   wire  [RAM_WIDTH-1:0]      stew        [ FRACTURABLE:0 ];           // State Execution Word

   // Config data
   reg   [OUTPUTS-1:0]        cfg_data_out_mask [ FRACTURABLE:0 ];
   reg   [COND_OUT-1:0]       cfg_cond_out_mask [ FRACTURABLE:0 ];

   // PRISM readback data (SI, etc.)
   reg  [31:0]                debug_rdata_prism;  // Peripheral read data
   reg  [31:0]                debug_in_data;      // Peripheral data for in_data readback
   reg  [DBG_A_BITS-1:0]      debug_si_a;

   // Debug control register
   reg  [W_DBG_CTRL-1:0]      debug_ctrl0;
   reg  [W_DBG_CTRL-1:0]      debug_ctrl1;
   wire                       debug_halt_req[1:0];
   wire                       debug_step_si[1:0];
   wire                       debug_bp_en0[1:0];
   wire                       debug_bp_en1[1:0];
   wire  [SI_BITS-1:0]        debug_bp_si0[1:0];
   wire  [SI_BITS-1:0]        debug_bp_si1[1:0];
   wire                       debug_new_si[1:0];
   wire  [SI_BITS-1:0]        debug_new_siv[1:0];
   reg  [OUTPUTS-1:0]         debug_dout;          // Outputs during debug
   reg  [OUTPUTS-1:0]         debug_dout_new_val;  // New Outputs from debug write
   reg                        debug_dout_new;
   reg                        debug_dout_new_p1;
   reg                        debug_dout_new_p2;
   reg                        debug_dout_new_p3;

   // Debug control regs
   reg  [1:0]                 debug_halt;
   reg  [1:0]                 debug_step_pending;
   reg  [1:0]                 debug_resume_pending;
   reg  [1:0]                 debug_halt_req_p1;
   reg  [1:0]                 debug_step_si_last;
   reg  [1:0]                 debug_break_active[1:0];
   reg  [31:0]                decision_tree_data;  // Peripheral read data

   integer      cond_pos[14];

   assign cond_pos[0]   = 0;
   assign cond_pos[1]   = 1;

   assign cond_pos[2]   = STATE_INPUTS-2;
   assign cond_pos[3]   = STATE_INPUTS-1;

   assign cond_pos[4]   = 2;
   assign cond_pos[5]   = HALF_IN;

   assign cond_pos[6]   = HALF_IN;
   assign cond_pos[7]   = HALF_IN+1;

   assign cond_pos[8]   = HALF_IN+2;
   assign cond_pos[9]   = HALF_IN;

   assign cond_pos[10]  = HALF_IN+1;
   assign cond_pos[11]  = HALF_IN+1;

   assign cond_pos[12]  = 3;
   assign cond_pos[13]  = HALF_IN+2;

   /* 
   =================================================================================
	Generate Section for RAM State Information Table (SIT)
   =================================================================================
   */

   wire [31:0]             debug_rdata_ram;  // Peripheral read data
   wire                    debug_ram_en;

   // Instantiate the Latch based SIT
   prism_latch_sit
   #(
      .WIDTH   ( RAM_WIDTH     ),
      .DEPTH1  ( RAM_DEPTH0    ),
      .DEPTH2  ( RAM_DEPTH1    ),
      .A_BITS1 ( DH_BITS       ),
      .A_BITS2 ( DR_BITS       )
    )
   prism_latch_sit_i
   (
`ifdef USE_POWER_PINS
      .VPWR(VPWR),
      .VGND(VGND),
`endif
      .clk                   ( clk                     ),
                                                         
      // Periph bus interface                            
      .debug_addr            ( debug_addr              ),
      .debug_wdata           ( debug_wdata             ),
      .debug_rdata           ( debug_rdata_ram         ),
      .debug_wr              ( debug_wr                ),
                                                        
      // PRISM interface                                
      .raddr1                ( ram_raddr1              ),
      .raddr2                ( ram_raddr2              ),
      .rdata1                ( ram_dout_c[0]           ),
      .rdata2                ( ram_dout_c[1]           )
   );

   assign debug_ram_en = debug_addr[5:2] == 1;

   for (genvar f = 0; f <= FRACTURABLE; f++)
   begin: GEN_RAM_DOUT
      assign ram_dout[f] = FRACTURABLE && cfg_fractured ? ram_dout_c[f] : 
                  f > 0 ? 'h0 : curr_si[0][SI_BITS-1] ? ram_dout_c[1] : ram_dout_c[0];
   end

   assign debug_rdata  = debug_rdata_prism;
   assign debug_en_ram = debug_wr && (debug_addr[W_ADDR-1:0] == 8'b0);
   assign ram_raddr1   = curr_si[0][DH_BITS-1:0];
   assign ram_raddr2   = curr_si[1][DR_BITS-1:0];

   always @(posedge clk)
   begin
      if (~rst_n | debug_reset)
      begin
         debug_si_a <= 'h0;
      end
      else
      begin
         // Test for write to the debug_si_a
         if (debug_wr && debug_addr[W_ADDR-1:4] == 'h1)
         begin
            // Test for write to fsm_enable override bits
            if (debug_addr[3:0] == 'h1)
            begin
               debug_si_a <= debug_wdata[DBG_A_BITS-1:0];
            end
         end

         // Test for read / write of STEW word
         else if (debug_en_ram && debug_addr == 'h0)
            debug_si_a <= debug_si_a + 1;
      end
   end

   /* 
   =================================================================================
   Assign signals from generated / instantiated RAM
   =================================================================================
   */
   localparam INPUT_SEL_SIZE  = STATE_INPUTS * W_PAR_IN;
   
   localparam INPUT_SEL_START = 1;
   localparam JUMP_TO_START   = INPUT_SEL_SIZE + INPUT_SEL_START;
   localparam OUTPUTS_START   = JUMP_TO_START  + SI_BITS*(DUAL_COMPARE+1);
   localparam CMP_SEL_START   = OUTPUTS_START  + OUTPUTS*(DUAL_COMPARE+2); 
   localparam COND_START      = CMP_SEL_START  + CMP_SEL_SIZE*(DUAL_COMPARE+1);

`ifdef DEBUG_PRISM_STEW
   initial begin
      $display("RAM_WIDTH       = %d", RAM_WIDTH);
      $display("RAM_DEPTH0      = %d", RAM_DEPTH0);
      $display("RAM_DEPTH1      = %d", RAM_DEPTH1);
      $display("INPUT_SEL_START = %d", INPUT_SEL_START);
      $display("OUTPUTS_START   = %d", OUTPUTS_START);
      $display("JUMP_TO_START   = %d", JUMP_TO_START); 
      $display("CMP_SEL_START   = %d", CMP_SEL_START);
      $display("COND_START      = %d", COND_START);
      $display("W_ADDR          = %d", W_ADDR);
   end
`endif

   // Assign stew either as registered or non-registered ram_dout
   for (genvar f = 0; f <= FRACTURABLE; f++)
   begin: GEN_STEW
      assign stew[f] = ram_dout[f][RAM_WIDTH-1:0];
   end

   // Now map the stew to the individual fields
   for (genvar f = 0; f <= FRACTURABLE; f++)
   begin: GEN_CTRL
      for (genvar cmp = 0; cmp < DUAL_COMPARE+1; cmp++)
      begin : OPCODE_ASSIGN_GEN
         // Assign JumpTo bits
         assign jump_to[f][cmp]       = stew[f][SI_BITS           + JUMP_TO_START + SI_BITS*(DUAL_COMPARE-cmp) -1      -: SI_BITS];

         // Assign jump_outputs
         assign jump_outputs[f][cmp]  = stew[f][OUTPUTS           + OUTPUTS_START + OUTPUTS*((DUAL_COMPARE-cmp)+1) -1  -: OUTPUTS];

         // Assign cmp_sel bits
         assign cmp_sel[f][cmp]       = stew[f][CMP_SEL_SIZE*(cmp+1)-1+ CMP_SEL_START -: CMP_SEL_SIZE];
      end

      // Assign conditional output bits
      for (genvar cond = 0; cond < COND_OUT; cond++)
      begin : COND_ASSIGN_GEN
         assign cond_cfg[f][cond]     = stew[f][COND_LUT_BITS*cond + COND_START +: COND_LUT_BITS]; 
      end

      // Assign output bits
      assign state_outputs[f]         = stew[f][OUTPUTS     + OUTPUTS_START-1 -: OUTPUTS];

      // Assign Input mux selection bits
      for (genvar inp = 0; inp < STATE_INPUTS; inp++)
      begin: GEN_IN_MUX_SEL
         assign input_mux_sel[f][inp] = stew[f][INPUT_SEL_START + W_PAR_IN * (inp+1) - 1 -: W_PAR_IN];
      end

      // Assign increment bit
      assign inc_si[f]                = stew[f][0];
   end

   /* 
   =================================================================================
   Clocked State Block for state machine SI
   =================================================================================
   */
   always @(posedge clk)
   begin
      if (~rst_n | debug_reset)
      begin
         curr_si[0] <= 'h0;
         curr_si[1] <= 'h0;
      end
      else
      begin
         if (!cfg_program & fsm_enable_comb)
         begin
            curr_si[0] <= next_si[0];
            curr_si[1] <= next_si[1];
         end
      end
   end

   /* 
   =================================================================================
   Logic for next SI 
   =================================================================================
   */
   for (genvar s = 0; s <= 1; s++)
   begin: GEN_NEXT_SI
      assign next_si[s] = debug_halt[s] ? debug_si[s] : 
                          compare_match[FRACTURABLE?s:0][0] ? jump_to[FRACTURABLE?s:0][0] :
                          DUAL_COMPARE && compare_match[FRACTURABLE?s:0][DUAL_COMPARE] ? jump_to[FRACTURABLE?s:0][DUAL_COMPARE] :
                          inc_si[FRACTURABLE?s:0] ? curr_si[s] + 1 :
                          loop_valid[FRACTURABLE?s:0] ? loop_si[FRACTURABLE?s:0] :
                          curr_si[s];
   end
   assign debug_halt_either = debug_halt[0] | debug_halt[1];

   /* 
   =================================================================================
   Logic for loop_si
   =================================================================================
   */
   always @(posedge clk)
   begin
      integer f;

      if (~rst_n | debug_reset)
      begin
         fsm_enable_comb <= 1'b0;

         for (f = 0; f <= FRACTURABLE; f++)
         begin
            loop_valid[f] <= 1'b0;
            loop_si[f] <= 'h0;
         end
      end
      else
      begin
         // Enable FSM from either input pin or internal register
         fsm_enable_comb <= (fsm_enable & !fsm_enable_pin_disable) | fsm_enable_int;

         for (f = 0; f <= FRACTURABLE; f++)
         begin
            if (compare_match[f][0] || compare_match[f][DUAL_COMPARE])
               loop_valid[f] <= 1'b0;

            else if (inc_si[f] && ~loop_valid[f])
            begin
               loop_valid[f] <= 1'b1;
               loop_si[f] <= curr_si[f];
            end
         end
      end
   end
   
   /* 
   =================================================================================
   Create a mux for each STATE_INPUT
   =================================================================================
   */
   generate
      for (genvar f = 0; f <= FRACTURABLE; f++)
      begin: GEN_INPUT_MUX
         for (genvar inp = 0; inp < STATE_INPUTS; inp++)
         begin : STATE_IN_MUX_GEN
            assign input_mux_out_c[f][inp] = in_data[input_mux_sel[f][inp]];
            assign input_mux_out[f][inp] = input_mux_out_c[f][inp];
         end
      end
   endgenerate

   /* 
   =================================================================================
   For each state index, Generate a LUT
   =================================================================================
   */
   wire [LUT_SIZE-1:0] lut_inputs[FRACTURABLE:0][DUAL_COMPARE : 0];

   generate
   for (genvar f = 0; f <= FRACTURABLE; f++)
   begin: GEN_LUTS_F
      // Simple LUT4 lookup
      for (genvar cmp = 0; cmp < DUAL_COMPARE+1; cmp++)
      begin : CMP_INST
         // Map MUX outputs to lut inputs
         for (genvar inp = 0; inp < LUT_SIZE; inp++)
         begin: GEN_LUT_INPUTS
            assign lut_inputs[f][cmp][inp] = input_mux_out[f][cmp*(STATE_INPUTS-LUT_SIZE)+inp];
         end
         
         assign compare_match[f][cmp] = cmp_sel[f][cmp][lut_inputs[f][cmp]];
      end
   end
   endgenerate

   /* 
   =================================================================================
   Assign the output values.
   =================================================================================
   */
   for (genvar f = 0; f <= FRACTURABLE; f++)
   begin: GEN_OUT_DATA
      // Assign outputs based on state compare
      assign out_data_c[f] = compare_match[f][0] ? jump_outputs[f][0] : DUAL_COMPARE && 
            compare_match[f][DUAL_COMPARE] ? jump_outputs[f][DUAL_COMPARE] : state_outputs[f];

      // If fractured, mask output bits based on config settings
      assign out_data_m[f] = FRACTURABLE && cfg_fractured ? out_data_c[f] & cfg_data_out_mask[f]
                              : out_data_c[f];
   end

   assign out_data_fsm = fsm_enable_comb ? FRACTURABLE && cfg_fractured ? out_data_m[FRACTURABLE] | out_data_m[0] :
                        out_data_m[0] : {OUTPUTS{1'b0}};
   assign out_data = INCLUDE_DEBUG & (debug_halt[0] | debug_halt[FRACTURABLE]) ? debug_dout : out_data_fsm;

   /* 
   =================================================================================
   Assign the conditional outputs
   =================================================================================
   */
   for (genvar f = 0; f <= FRACTURABLE; f++)
   begin : COND_FRAC_GEN
      for (genvar cond = 0; cond < COND_OUT; cond++)
      begin : COND_OUT_GEN
         // Create OR and AND output for each conditional OUT
         assign cond_in[f][cond][0] = input_mux_out[f][cond_pos[cond*2]];
         assign cond_in[f][cond][1] = input_mux_out[f][cond_pos[cond*2+1]];

         // Drive the conditional output based on enable and ao_sel 
         assign cond_out_c[f][cond] = cond_cfg[f][cond][cond_in[f][cond][COND_LUT_SIZE-1:0]];

         // Assign masked registers based on fractured state
         assign cond_out_m[f][cond] = FRACTURABLE && cfg_fractured ? cond_out_c[f][cond] & cfg_cond_out_mask[f][cond] :
                                       cond_out_c[f][cond];
      end
   end

   for (genvar cond = 0; cond < COND_OUT; cond++)
   begin : COND_OUT_GEN
      // Assign final conditional outputs
      assign cond_out[cond] = fsm_enable_comb ? ((FRACTURABLE && cfg_fractured) ? (cond_out_m[FRACTURABLE][cond] | 
                              cond_out_m[0][cond]) : cond_out_m[0][cond]) : 1'b0;
      
   end  

   /* 
   =================================================================================
   Debug Bus Register Map:

   0x00: Config:  {29'h0, cfg_fractured, fsm_enable_pin_disable, fsm_enable, cfg_program}
   0x04: debug_ctrl0
   0x08: debug_ctrl1
   0x0c: Current State info
              { {(26-SI_BITS*4) {1'b0}}, 
                debug_break_active[FRACTURABLE], debug_halt[FRACTURABLE], next_si[FRACTURABLE], curr_si[FRACTURABLE],
                debug_break_active[0],           debug_halt[0],           next_si[0],           curr_si[0]
              };
   0x10: STEW0 LSB
   0x14: STEW0 MSB
   0x18: STEW1 LSB
   0x1C: STEW1 MSB
   0x20: cfg_data_out_mask[0]
   0x14: cfg_cond_out_mask[0]
   0x28: cfg_data_out_mask[1]
   0x2c: cfg_cond_out_mask[1]
   0x30: debug_output_bits;
   0x34: decision_tree_data
   0x38: outut_data
   0x3c: input_data
   ===================================================================================== 
   */
   always @(posedge clk)
   begin
      if (~rst_n | debug_reset)
      begin
         integer f;
         integer cond;

         cfg_fractured <= 1'b0;
         cfg_program <= 1'b0;
         fsm_enable_int <= 1'b0;
         fsm_enable_pin_disable <= 1'b0;
         debug_ctrl0 <= {W_DBG_CTRL{1'b0}};
         debug_ctrl1 <= {W_DBG_CTRL{1'b0}};
         debug_dout_new_val <= 'h0;
         debug_dout_new <= 1'b0;
         debug_dout_new_p1 <= 1'b0;
         debug_dout_new_p2 <= 1'b0;
         debug_dout_new_p3 <= 1'b0;

         for (f = 0; f <= FRACTURABLE; f++)
         begin
            cfg_data_out_mask[f] <= 'h0;

            for (cond = 0; cond < COND_OUT; cond++)
               cfg_cond_out_mask[f][cond] <= 'h0;
         end
      end
      else
      begin
         integer f;

         // Test for write to Fracture Control registers
         if (FRACTURABLE && debug_wr && debug_addr == 6'h0)
         begin
            // Test for write to top-level control reg
            cfg_fractured <= debug_wdata[3];
         end

         if (FRACTURABLE && debug_wr &&
               debug_addr[W_ADDR-1:4] == 'h2)
         begin
            // Test for write to output masks 
            for (f = 0; f <= FRACTURABLE; f++)
            begin
               // Test for general output mask write
               if (debug_addr[3:0] == 4'(f*8))
                  cfg_data_out_mask[f] <= debug_wdata[OUTPUTS-1:0];

               // Test for conditional output mask write
               if (debug_addr[3:0] == 4'(4 + f*8))
                  cfg_cond_out_mask[f] <= debug_wdata[COND_OUT-1:0];
            end
         end

         // Test for write to fsm_enable override bits
         if (debug_wr && debug_addr == 6'h0)
         begin
            cfg_program    <= debug_wdata[0];
            fsm_enable_int <= debug_wdata[1];
            fsm_enable_pin_disable <= debug_wdata[2];
         end

         // Test for write to debug output register
         if (INCLUDE_DEBUG && debug_wr && (debug_addr[W_ADDR-1:4] == 4'h0))
         begin
            // Test for write to debug_dout bits
            if (debug_addr[3:0] == 4'hC)
            begin
               // Save debug register
               debug_dout_new_val <= debug_wdata[OUTPUTS-1:0];
               debug_dout_new <= 1'b1;
               debug_dout_new_p1 <= 1'b1;
               debug_dout_new_p2 <= 1'b1;
               debug_dout_new_p3 <= 1'b1;
            end

            // Test for write to top-level control reg
            if (debug_addr[3:0] == 4'h4)
            begin
               // Save debug register
               debug_ctrl0 <= debug_wdata[W_DBG_CTRL-1:0];
            end

            // Test for write to top-level control reg
            if (debug_addr[3:0] == 4'h8)
            begin
               // Save debug register
               debug_ctrl1 <= debug_wdata[W_DBG_CTRL-1:0];
            end
         end
         else
         begin
            debug_dout_new    <= debug_dout_new_p1;
            debug_dout_new_p1 <= debug_dout_new_p2;
            debug_dout_new_p2 <= debug_dout_new_p3;
            debug_dout_new_p3 <= 1'b0;
         end
      end
   end

   /*
   ===================================================================================== 
   Register READ
   ===================================================================================== 
   */
   always @*
   begin
      debug_rdata_prism = 32'h0;

      // Detect debug read
      case (debug_addr[W_ADDR-1:4])
      4'h0: begin
               if (FRACTURABLE)
                  case (debug_addr[3:0])
                     4'h0:    debug_rdata_prism = {28'h0, cfg_fractured, fsm_enable_pin_disable, fsm_enable_comb, cfg_program};
                     4'h4:    debug_rdata_prism = debug_ctrl0;
                     4'h8:    debug_rdata_prism = debug_ctrl1;
                     4'hC:    debug_rdata_prism = { {(26-SI_BITS*4) {1'b0}}, 
                                 debug_break_active[FRACTURABLE], debug_halt[FRACTURABLE], next_si[FRACTURABLE], curr_si[FRACTURABLE],
                                 debug_break_active[0],           debug_halt[0],           next_si[0],           curr_si[0]};
                     default: debug_rdata_prism = 32'h0;
                  endcase
               else
                  case (debug_addr[3:0])
                     4'h0:    debug_rdata_prism = {29'h0, fsm_enable_pin_disable, fsm_enable_comb, 1'b0};
                     4'h4:    debug_rdata_prism = debug_ctrl0;
                     4'h8:    debug_rdata_prism = debug_ctrl1;
                     4'hC:    debug_rdata_prism = { {(26-SI_BITS*4) {1'b0}}, 
                                 2'h0,                            1'b0,                    {SI_BITS{1'b0}},      {SI_BITS{1'b0}},
                                 debug_break_active[0],           debug_halt[0],           next_si[0],           curr_si[0]};
                     default: debug_rdata_prism = 32'h0; 
                  endcase
           end
      4'h1:   debug_rdata_prism = debug_rdata_ram;

      4'h2:   begin
               if (FRACTURABLE)
                  case (debug_addr[3:0])
                  4'h0:  debug_rdata_prism = {{(32-OUTPUTS){1'b0}},cfg_data_out_mask[0]};
                  4'h4:  debug_rdata_prism = {{(32-COND_OUT){1'b0}},cfg_cond_out_mask[0]};
                  4'h8:  debug_rdata_prism = {{(32-OUTPUTS){1'b0}},cfg_data_out_mask[FRACTURABLE]};
                  4'hc:  debug_rdata_prism = {{(32-COND_OUT){1'b0}},cfg_cond_out_mask[FRACTURABLE]};
                  default: debug_rdata_prism = 32'h0; 
                  endcase
               else
                  case (debug_addr[3:0])
                  4'h0:  debug_rdata_prism = {{(32-OUTPUTS){1'b0}},cfg_data_out_mask[0]};
                  4'h4:  debug_rdata_prism = {{(32-COND_OUT){1'b0}},cfg_cond_out_mask[0]};
                  default: debug_rdata_prism = 32'h0; 
                  endcase
               end
      4'h3:   begin
                  case (debug_addr[3:0])
                  4'h0: debug_rdata_prism = {{(32-OUTPUTS){1'b0}}, debug_dout};
                  4'h4: debug_rdata_prism = decision_tree_data;
                  4'h8: debug_rdata_prism = {{(32-OUTPUTS){1'b0}}, out_data};
                  4'h8: debug_rdata_prism = {{(32-INPUTS){1'b0}}, in_data};
                  default: debug_rdata_prism = 32'h0; 
                  endcase
              end
      default: debug_rdata_prism = 32'h0;
      endcase
   end

   localparam LUT_INOUT_SIZE = 1 + LUT_SIZE;
   localparam FRACTURE_DECISION_SIZE = (DUAL_COMPARE + 1)*LUT_INOUT_SIZE ;

   always @*
   begin
      integer f, cmp;

      // Default to zero
      decision_tree_data = 32'h0;

      // Add decision tree data
      for (f = 0; f <= FRACTURABLE; f++)
         for (cmp = 0; cmp <= DUAL_COMPARE; cmp++)
            decision_tree_data[f*FRACTURE_DECISION_SIZE + (cmp+1)*LUT_INOUT_SIZE-1 -: LUT_INOUT_SIZE] = {compare_match[f][cmp], lut_inputs[f][cmp]};
   end

   // Generate Periph read-back for in_data
   generate
      always @*
      begin
         // Default to zero
         debug_in_data = 32'h0;

         // Override bits based on number of inputs defined by parameter
         debug_in_data[INPUTS-1:0] = in_data;
      end
   endgenerate

   /* 
   =================================================================================
   Debug print the state changes
   =================================================================================
   */

`ifdef DEBUG_PRISM_TRANSITIONS
   always @(curr_si[0] or out_data)
      $display("SI=%02x   OutData=%06X   Jump0 Out=%06X   JumpTo 0=%3d  LUT_in=%X  CMP=%d", 
            curr_si[0], out_data, jump_outputs[0][0], jump_to[0][0], lut_inputs[0][0], compare_match[0][0]);

   if (DUAL_COMPARE)
   begin
      always @(compare_match[0][1])
         $display("CompareMatch 1 = %d\n", compare_match[0][1]);
      always @(jump_outputs[0][1])
         $display("Jump1 Out=%x\n", jump_outputs[0][1]);
      always @(jump_to[0][1])
         $display("JumpTo 1 = %d\n", jump_to[0][1]);
   end
`endif

   /* 
   =================================================================================
   Assign debug control register bits
   =================================================================================
   */
   // Control for fracture unit 0
   assign debug_halt_req[0] = debug_ctrl0[0];
   assign debug_step_si[0]  = debug_ctrl0[1];
   assign debug_bp_en0[0]   = debug_ctrl0[2];
   assign debug_bp_en1[0]   = debug_ctrl0[3];
   assign debug_bp_si0[0]   = debug_ctrl0[SI_BITS  +4-1 -: SI_BITS];
   assign debug_bp_si1[0]   = debug_ctrl0[SI_BITS*2+4-1 -: SI_BITS];
   assign debug_new_si[0]   = debug_ctrl0[SI_BITS*2+4];
   assign debug_new_siv[0]  = debug_ctrl0[SI_BITS*3+5-1 -: SI_BITS];

   // Control for fracture unit 1
   assign debug_halt_req[1] = debug_ctrl1[0];
   assign debug_step_si[1]  = debug_ctrl1[1];
   assign debug_bp_en0[1]   = debug_ctrl1[2];
   assign debug_bp_en1[1]   = debug_ctrl1[3];
   assign debug_bp_si0[1]   = debug_ctrl1[SI_BITS  +4-1 -: SI_BITS];
   assign debug_bp_si1[1]   = debug_ctrl1[SI_BITS*2+4-1 -: SI_BITS];
   assign debug_new_si[1]   = debug_ctrl1[SI_BITS*2+4];
   assign debug_new_siv[1]  = debug_ctrl1[SI_BITS*3+5-1 -: SI_BITS];

   /* 
   =================================================================================
   Debugger code
   =================================================================================
   */
   always @(posedge clk)
   begin
      if (~rst_n | debug_reset)
      begin
         integer f;
         debug_halt <= 2'h0;
         debug_step_pending <= 2'h0;
         debug_resume_pending <= 2'h0;
         debug_halt_req_p1 <= 2'h0;
         debug_step_si_last <= 2'h0;

         for (f = 0; f <= 1; f++)
         begin
            debug_si[f] <={SI_BITS{1'b0}};
            debug_break_active[f] <= 2'h0;
         end
      end
      else
      begin
         integer f;
         for (f = 0; f <= 1; f++)
         begin
            // Create rising edge detector for debug_step_si
            debug_step_si_last[f] <= debug_step_si[f];

            // New SI load from debug interface
            debug_new_si_p1[f] <= debug_new_si[f];
            debug_new_si_p2[f] <= debug_new_si_p1[f];
            debug_new_si_p3[f] <= debug_new_si_p2[f];
            if (debug_new_si_p2[f] && !debug_new_si_p3[f])
            begin  
               debug_si[f] <= debug_new_siv[f];
            end

            // Test for single-step request
            else if (debug_halt[f] && debug_step_si[f] && !debug_step_si_last[f] && !debug_step_pending[f])
            begin
               // Disable halt and enable step_pending
               debug_halt[f] <= 1'b0;
               debug_step_pending[f] <= 1'b1;
               debug_break_active[f] <= 2'b0;
            end

            // Test if we need to halt the FSM
            else if (debug_step_pending[f] || 
                    (debug_bp_en0[f] && !debug_break_active[f][0] && !debug_resume_pending[f] && (debug_bp_si0[f] == next_si[f])) ||
                    (debug_bp_en1[f] && !debug_break_active[f][1] && !debug_resume_pending[f] && (debug_bp_si1[f] == next_si[f])) ||
                     (debug_halt_req[f] & !debug_halt_req_p1[f]))
            begin
               // Halt the FSM
               debug_halt[f] <= 1'b1;
               debug_si[f] <= next_si[f];
               debug_dout <= out_data_fsm;
               debug_step_pending[f] <= 1'b0;

               // If halt requested, clear debug_break_active
               if (debug_halt_req[f])
                  debug_break_active[f] <= 2'h0;
               else
               begin
                  // Test if we broke because of breakpoint 0
                  if (debug_bp_en0[f] && !debug_break_active[f][0] && (debug_bp_si0[f] == curr_si[f]))
                     debug_break_active[f][0] <= 1'b1;
                  else
                     debug_break_active[f][0] <= 1'b0;

                  // Test if we broke because of breakpoint 1
                  if (debug_bp_en1[f] && !debug_break_active[f][1] && (debug_bp_si1[f] == curr_si[f]))
                     debug_break_active[f][1] <= 1'b1;
                  else
                     debug_break_active[f][1] <= 1'b0;
               end
            end

            // Test if we need to resume the FSM
            else if (debug_halt[f] && !debug_halt_req[f] && !debug_break_active[f][0] && !debug_break_active[f][1])
            begin
               debug_halt[f] <= 1'b0;
               debug_step_pending[f] <= 1'b0;
               debug_break_active[f] <= 2'b0;
            end

            // Test for new debug_dout load
            if (debug_dout_new)
               debug_dout <= debug_dout_new_val;

            // Test for resume from halt request
            debug_halt_req_p1[f] <= debug_halt_req[f];
            debug_resume_pending[f] <= debug_halt_req_p1[f] & !debug_halt_req[f];
            if (debug_halt_req_p1[f] & !debug_halt_req[f])
            begin
               debug_halt[f] <= 1'b0;
               debug_break_active[f] <= 2'b0;
            end
         end
      end
   end

endmodule // prism


