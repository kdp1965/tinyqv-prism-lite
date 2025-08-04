
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, Edge

from tqv import TinyQV

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 100 ns (10 MHz)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    # Setup simulated external devices
    input_value = 0xA5A5A5  # whatever test value you want
    output_shift = 0
    output_value = 0
    input_shift = input_value

    async def simulate_74165():
        nonlocal input_shift
        val_str = dut.uo_out.value.binstr.replace('x', '0').replace('z', '0')
        prev_val = int(val_str, 2)
        while True:
            # Wait for rising edge of uo_out[7] (shift clock)
            await RisingEdge(dut.clk)

            # Get uo_out as an integer safely ('x' -> 0)
            val_str = dut.uo_out.value.binstr.replace('x', '0').replace('z', '0')
            curr_val = int(val_str, 2)

            # Check for clear or clock
            if curr_val & 2 == 0:
                # Load new value
                input_shift = input_value
            elif ((prev_val ^ curr_val) & (1 << 7)) and (curr_val & (1 << 7)):
                # Shift left
                input_shift = (input_shift << 1) & 0xFFFFFF
            prev_val = curr_val

            # Set ui_in[0] to MSB
            dut.ui_in[0].value = (input_shift >> 23) & 1

    async def simulate_74595():
        nonlocal output_shift, output_value
        val_str = dut.uo_out.value.binstr.replace('x', '0').replace('z', '0')
        prev_val = int(val_str, 2)

        while True:
            # Wait for either posedge uo_out[7] (shift clk) or posedge uo_out[2] (store)
            await RisingEdge(dut.clk)

            val_str = dut.uo_out.value.binstr.replace('x', '0').replace('z', '0')
            curr_val = int(val_str, 2)
            if curr_val & 4 != 0:
                # On store, latch output
                output_value = output_shift
            elif ((prev_val ^ curr_val) & (1 << 7)) and (curr_val & (1 << 7)):
                # On shift, shift in from uo_out[3]
                bit = int(dut.uo_out[3].value)
                output_shift = ((output_shift << 1) | bit) & 0xFFFFFF
            prev_val = curr_val

    # Start the simulations
    cocotb.start_soon(simulate_74165())
    cocotb.start_soon(simulate_74595())

    # Interact with your design's registers through this TinyQV class.
    # This will allow the same test to be run when your design is integrated
    # with TinyQV - the implementation of this class will be replaces with a
    # different version that uses Risc-V instructions instead of the SPI 
    # interface to read and write the registers.
    tqv = TinyQV(dut)

    # Reset
    await tqv.reset()

    dut._log.info("Test project behavior")

    # Write values to the count2_compare / count1_preload
    await tqv.write_word_reg(0x00, 0x60000000)
    await ClockCycles(dut.clk, 8)
    await tqv.write_word_reg(0x20, 0x0300FA12)
    await ClockCycles(dut.clk, 8)

    assert await tqv.read_word_reg(0x20) == 0x0300FA12
    assert await tqv.read_word_reg(0x0) == 0x60000000

    # Test register write and read back
    # Write a value to the config array 
    await tqv.write_word_reg(0x14, 0x00001010)
    await tqv.write_word_reg(0x10, 0x10101010)

    await tqv.write_word_reg(0x14, 0x00002020)
    await tqv.write_word_reg(0x10, 0x20202020)

    await tqv.write_word_reg(0x14, 0x00003030)
    await tqv.write_word_reg(0x10, 0x30303030)

    await tqv.write_word_reg(0x14, 0x00004040)
    await tqv.write_word_reg(0x10, 0x40404040)

    await tqv.write_word_reg(0x14, 0x00005050)
    await tqv.write_word_reg(0x10, 0x50505050)

    await tqv.write_word_reg(0x14, 0x00006060)
    await tqv.write_word_reg(0x10, 0x60606060)

    await tqv.write_word_reg(0x14, 0x00007070)
    await tqv.write_word_reg(0x10, 0x70707070)

    await tqv.write_word_reg(0x14, 0x00008080)
    await tqv.write_word_reg(0x10, 0x80808080)

    # Wait for two clock cycles to see the output values, because ui_in is synchronized over two clocks,
    # and a further clock is required for the output to propagate.
    await ClockCycles(dut.clk, 3)

    # 0x10101010 should be read back from register 8
    assert await tqv.read_word_reg(0x10) == 0x10101010


    # ===========================================================
    # Okay, now load up a real design and see if it does anything
    # This is the 24-Bit GPIO Chroma
    # ===========================================================

    await tqv.write_word_reg(0x14, 0x03c0 )
    await tqv.write_word_reg(0x10, 0x08000000)

    await tqv.write_word_reg(0x14, 0x0140 )
    await tqv.write_word_reg(0x10, 0x08010010)

    await tqv.write_word_reg(0x14, 0x0bc0 )
    await tqv.write_word_reg(0x10, 0x0800d200)

    await tqv.write_word_reg(0x14, 0x03c0 )
    await tqv.write_word_reg(0x10, 0x0800a000)

    await tqv.write_word_reg(0x14, 0x0140 )
    await tqv.write_word_reg(0x10, 0x0801401d)

    await tqv.write_word_reg(0x14, 0x0280)
    await tqv.write_word_reg(0x10, 0x0841601a)

    await tqv.write_word_reg(0x14, 0x03c0)
    await tqv.write_word_reg(0x10, 0x08004000)

    await tqv.write_word_reg(0x14, 0x0288)
    await tqv.write_word_reg(0x10, 0x00012010)

    assert await tqv.read_word_reg(0x14) == 0x03c0
    assert await tqv.read_word_reg(0x10) == 0x08000000

    # Now program the PRISM peripheral configuration registers
    await tqv.write_word_reg(0x0, 0x65980000)
    assert await tqv.read_word_reg(0x0) == 0x65980000

    # Now release PRISM from reset
    await tqv.write_word_reg(0x0, 0x25980000)

    # Put 24-bit OUTPUT data in the 24-bit Shift register
    await tqv.write_word_reg(0x20, 0x00F05077)

    # Set an input value in the testbench
    input_value = 0x00BEEF

    # Start a transfer
    await tqv.write_word_reg(0x18, 0x03000000)
    await tqv.write_word_reg(0x18, 0x00000000)

    # See if we got the input value
    assert await tqv.read_word_reg(0x24) == 0x0000BEEF
    assert output_value == 0x00F05077

#  1. com_in_sel    = 0 (Shift input data on ui_in[0])
#  2. shift_24_le   = 1 (Enable 24-bit shift)
#  3. shift_en      = 1 (Enable shift operation)
#  4. shift_dir     = 1 (LSB first)
#  5. shift_out_sel = 2 (Route shift_data to uo_out[3])
#  6. fifo_24       = 0 (Not using 24-bit reg as FIFO)
#  7. latch_in_out  = 1 (Readback latched out data [6:1])
#  8. cond_sel      = 1 (Route cond_out to uo_out[2])
    
    








