// (c) Copyright Ken Pettit
//         All Rights Reserved
// ------------------------------------------------------------------------------
//
//  File        : prism_latch_sit.v
//  Revision    : 1.2
//  Author      : Ken Pettit
//  Created     : 07/20/2025
//
// ------------------------------------------------------------------------------
//
// Description:  
//    This is a Programmable Reconfigurable Indexed State Machine (PRISM)
//    latch based State Information Table (SIT).
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
//    KP      07/20/25  1.0  Initial version
//
// ------------------------------------------------------------------------------

module prism_latch_sit
#(
   parameter  WIDTH       = 80,
   parameter  DEPTH       = 2,
   parameter  A_BITS      = DEPTH > 32 ? 6 :
                            DEPTH > 16 ? 5 : 
                            DEPTH > 8  ? 4 :
                            DEPTH > 4  ? 3 :
                            DEPTH > 2  ? 2 : 1
)
(
`ifdef USE_POWER_PINS
   input                         VPWR,
   input                         VGND,
`endif

   input  wire                   clk,
   input  wire                   rst_n,

   // ============================
   // Debug bus for programming
   // ============================
   input  wire [5:0]             debug_addr,    // Debug address
   input  wire                   debug_wr,      // Active HIGH write strobe
   input  wire [31:0]            debug_wdata,   // Debug write data
   output reg  [31:0]            debug_rdata,   // Debug read data

   // Read addresses and data
   input   wire [A_BITS-1:0]     raddr1,        // Read address 1
   output  wire [WIDTH-1:0]      rdata1         // Output for SI signal
);

   /* 
   =================================================================================
   Instantiate the Latch RAMs
   =================================================================================
   */
   wire                    config_write;
   wire [WIDTH-1:0]        config_data;
   wire [DEPTH-1:0]        config_latch_en;
   wire [WIDTH*DEPTH-1:0]  config_bus;
   wire [WIDTH-1:0]        config1_array [0:DEPTH-1];

   /* 
   =================================================================================
   Latch RAM for SI[1]
   =================================================================================
   */
   assign config_write = (debug_addr == 6'h10 || debug_addr == 6'h14) && debug_wr;
   latch_loader
   #(
      .DEPTH    ( DEPTH ),
      .WIDTH    ( WIDTH )
    )
   prism_config_loader
   (
       .clk          ( clk             ),
       .rst_n        ( rst_n           ),
       .write_req    ( config_write    ),
       .address      ( debug_addr[2:0] ),
       .data_in      ( debug_wdata     ),
       .config_data  ( config_data     ),
       .latch_en     ( config_latch_en )
   );

   latch_shift_reg
   #(
       .DEPTH ( DEPTH ),
       .WIDTH ( WIDTH )
   )
   i_prism_latch_sit
   (
`ifdef USE_POWER_PINS
       .VGND(VGND),
       .VPWR(VPWR),
`endif
        .rst_n        ( rst_n            ),
        .data_in      ( config_data     ),
        .latch_en     ( config_latch_en ),
        .data_out     ( config_bus      )
   );

   genvar i;
   generate
       for (i = 0; i < DEPTH; i = i + 1) begin : unpack_config1
           assign config1_array[i] = config_bus[(i+1)*WIDTH-1 -: WIDTH];
       end
   endgenerate
 

   /* 
   =================================================================================
   Assign the RAM outputs to the rdata1 / rdata2 outputs
   =================================================================================
   */
   assign rdata1 = config1_array[raddr1];

   /* 
   =================================================================================
   Generate the debug_rdata read-back from the RAM
   =================================================================================
   */
   always @*
   begin
      case (debug_addr)
      6'h10:   debug_rdata = config1_array[DEPTH-1][31:0];
      6'h14:   debug_rdata = {{(64-WIDTH){1'b0}}, config1_array[DEPTH-1][WIDTH-1:32]};
      default: debug_rdata = 32'h0;
      endcase
   end

endmodule // prism_latch_sit

