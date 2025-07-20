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
   parameter  DEPTH1      = 2,
   parameter  DEPTH2      = 2,
   parameter  A_BITS1     = DEPTH1 > 32 ? 6 :
                            DEPTH1 > 16 ? 5 : 
                            DEPTH1 > 8  ? 4 :
                            DEPTH1 > 4  ? 3 :
                            DEPTH1 > 2  ? 2 : 1,
   parameter  A_BITS2     = DEPTH2 > 32 ? 6 :
                            DEPTH2 > 16 ? 5 : 
                            DEPTH2 > 8  ? 4 :
                            DEPTH2 > 4  ? 3 :
                            DEPTH2 > 2  ? 2 : 1
)
(
`ifdef USE_POWER_PINS
   input                         VPWR,
   input                         VGND,
`endif

   input  wire                   clk,

   // ============================
   // Debug bus for programming
   // ============================
   input  wire [5:0]             debug_addr,    // Debug address
   input  wire                   debug_wr,      // Active HIGH write strobe
   input  wire [31:0]            debug_wdata,   // Debug write data
   output reg  [31:0]            debug_rdata,   // Debug read data

   // Read addresses and data
   input   wire [A_BITS1-1:0]    raddr1,        // Read address 1
   input   wire [A_BITS2-1:0]    raddr2,        // Read address 2
   output  reg  [WIDTH-1:0]      rdata1,        // Output for SI signal
   output  reg  [WIDTH-1:0]      rdata2         // Output for SI signal
);

   /* 
   =================================================================================
   Instantiate the Latch RAMs
   =================================================================================
   */
   wire                    config1_write;
   wire [WIDTH-1:0]        config1_data;
   wire [DEPTH1-1:0]       config1_latch_en;
   wire                    config1_busy;
   wire [WIDTH*DEPTH1-1:0] config1_bus;
   wire [WIDTH-1:0]        config1_array [0:DEPTH1-1];
   wire                    config2_write;
   wire [WIDTH-1:0]        config2_data;
   wire [DEPTH2-1:0]       config2_latch_en;
   wire                    config2_busy;
   wire [WIDTH*DEPTH2-1:0] config2_bus;
   wire [WIDTH-1:0]        config2_array [0:DEPTH2-1];
   
   /* 
   =================================================================================
   Latch RAM for SI[1]
   =================================================================================
   */
   assign config1_write = (debug_addr == 6'h10 || debug_addr == 6'h14) && debug_wr;
   latch_loader
   #(
      .DEPTH    ( DEPTH1 ),
      .WIDTH    ( WIDTH  )
    )
   prism_config1_loader
   (
       .clk          ( clk              ),
       .rst_n        ( rst_n            ),
       .write_req    ( config1_write    ),
       .address      ( debug_addr[2:0]  ),
       .data_in      ( debug_wdata      ),
       .config_data  ( config1_data     ),
       .busy         ( config1_busy     ),
       .latch_en     ( config1_latch_en )
   );

   latch_shift_reg
   #(
       .DEPTH ( DEPTH1 ),
       .WIDTH ( WIDTH  )
   )
   prism_latch_sit_u1
   (
`ifdef USE_POWER_PINS
       .VGND(VGND),
       .VPWR(VPWR),
`endif
        .rst_n        ( rst_n            ),
        .data_in      ( config1_data     ),
        .latch_en     ( config1_latch_en ),
        .data_out     ( config1_bus      )
   );

   genvar i;
   generate
       for (i = 0; i < DEPTH1; i = i + 1) begin : unpack_config1
           assign config1_array[i] = config1_bus[(i+1)*WIDTH-1 -: WIDTH];
       end
   endgenerate
 
   /* 
   =================================================================================
   Latch RAM for SI[1]
   =================================================================================
   */
   assign config2_write = (debug_addr == 6'h18 || debug_addr == 6'h1c) && debug_wr;
   latch_loader
   #(
      .DEPTH    ( DEPTH2 ),
      .WIDTH    ( WIDTH  )
    )
   prism_config2_loader
   (
       .clk          ( clk              ),
       .rst_n        ( rst_n            ),
       .write_req    ( config2_write    ),
       .address      ( debug_addr[2:0]  ),
       .data_in      ( debug_wdata      ),
       .config_data  ( config2_data     ),
       .busy         ( config2_busy     ),
       .latch_en     ( config2_latch_en )
   );

   latch_shift_reg
   #(
       .DEPTH ( DEPTH2 ),
       .WIDTH ( WIDTH  )
   )
   prism_latch_sit_u2
   (
`ifdef USE_POWER_PINS
       .VGND(VGND),
       .VPWR(VPWR),
`endif
        .rst_n        ( rst_n            ),
        .data_in      ( config2_data     ),
        .latch_en     ( config2_latch_en ),
        .data_out     ( config2_bus      )
   );

   generate
       for (i = 0; i < DEPTH2; i = i + 1) begin : unpack_config2
           assign config2_array[i] = config2_bus[(i+1)*WIDTH-1 -: WIDTH];
       end
   endgenerate
 

   /* 
   =================================================================================
   Assign the RAM outputs to the rdata1 / rdata2 outputs
   =================================================================================
   */
   assign rdata1 = config1_array[raddr1];
   assign rdata2 = config2_array[raddr2];

   /* 
   =================================================================================
   Generate the debug_rdata read-back from the RAM
   =================================================================================
   */
   always @*
   begin
      case (debug_addr)
      6'h10:   debug_rdata = config1_array[DEPTH1-1][31:0];
      6'h14:   debug_rdata = {{(64-WIDTH){1'b0}}, config1_array[DEPTH1-1][WIDTH-1:32]};
      6'h18:   debug_rdata = config2_array[DEPTH2-1][31:0];
      6'h1C:   debug_rdata = {{(64-WIDTH){1'b0}}, config2_array[DEPTH2-1][WIDTH-1:32]};
      default: debug_rdata = 32'h0;
      endcase
   end

endmodule // prism_latch_sit

