`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a VCD file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  wire [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`else
`ifdef USE_POWER_PINS
  wire VGND = 1'b0;
  wire VPWR = 1'b1;
`endif
`endif

  tt_um_tqv_peripheral_harness test_harness (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`else
`ifdef USE_POWER_PINS
      .VPWR(VPWR),
      .VGND(VGND),
`endif
`endif

      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

  /*
  ================================================================================
   Implement the 74165 "Input shift registers"
  ================================================================================
  */
  reg [23:0]   input_value;
  reg [23:0]   input_shift;

  initial begin
      input_value = 'h0;
  end

  always @(posedge uo_out[7] or negedge uo_out[1])
  begin
      if (!uo_out[1])
      begin
         input_shift <= input_value;
      end
      else
      begin
         input_shift <= {input_shift[22:0], 1'b0};   
      end
  end

  assign ui_in[0] = input_shift[23];

  /*
  ================================================================================
   Implement the 74595 "Output shift registers"
  ================================================================================
  */
  reg [23:0]   output_value;
  reg [23:0]   output_shift;


  always @(posedge uo_out[7] or posedge uo_out[2])
  begin
      if (uo_out[2])
      begin
         output_value <= output_shift;
      end
      else
      begin
         output_shift <= {output_shift[22:0], uo_out[3]};   
      end
  end

endmodule
