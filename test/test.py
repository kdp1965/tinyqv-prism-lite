
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, Edge

from tqv import TinyQV

'''
==============================================================
PRISM Downloadable Configuration

Input:    chroma_gpio24.sv
Config:   tinyqv.cfg
==============================================================
'''
chroma_gpio24 = [
   0x000003c0, 0x08000000, 
   0x000003c0, 0x08000000, 
   0x00000140, 0x08010010, 
   0x00000bc0, 0x0800b200, 
   0x00000140, 0x0801401d, 
   0x00000280, 0x0841601a, 
   0x000003c0, 0x08004000, 
   0x00000288, 0x00012010, 
]
chroma_gpio24_ctrlReg = 0x00000598

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
    spi_data = []
    chroma = 'gpio24'

    async def simulate_74165():
        nonlocal input_shift
        val_str = dut.uo_out.value.binstr.replace('x', '0').replace('z', '0')
        prev_val = int(val_str, 2)
        while True:
            # Wait for rising edge of uo_out[7] (shift clock)
            await RisingEdge(dut.clk)
            if chroma != 'gpio24':
               continue;

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
            if chroma != 'gpio24':
               continue;

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


    async def delay(clocks):
        for i in range(clocks):
            await RisingEdge(dut.clk)

    async def simulate_spimaster():
        nonlocal spi_data
        val_str = dut.uo_out.value.binstr.replace('x', '0').replace('z', '0')
        prev_val = int(val_str, 2)
        baud = 16
        idx  = 0
        rx_byte = 0

        while True:
            # Wait for either posedge uo_out[7] (shift clk) or posedge uo_out[2] (store)
            await RisingEdge(dut.clk)
            if chroma != 'spislave':
               continue;

            # Get first bit of first byte
            next_byte = spi_data[idx]
            idx += 1

            # Set input bit
            bit = (next_byte >> 7) & 1
            dut.ui_in[2].value = bit

            # Drop chip select
            dut.ui_in[0].value = 0
            await delay(baud)


    async def load_chroma(chroma, ctrl_reg):
        '''
           Loads the specified chroma to the PRISM State Information Table
        '''
        # First reset the PRISM
        await tqv.write_word_reg(0x00, 0x00000000)
        assert await tqv.read_word_reg(0x0) == 0x00000000

        # Now load the chroma
        for i in range(8):
          # Load MSB of the control word first
          await tqv.write_word_reg(0x14, chroma[i * 2])
        
          # Loading LSB initates the shift
          await tqv.write_word_reg(0x10, chroma[i * 2 +1])
        
        # Validate the shift operation succeeded
        assert await tqv.read_word_reg(0x14) == chroma[0]
        assert await tqv.read_word_reg(0x10) == chroma[1]
        
        # Now program the PRISM peripheral configuration registers
        await tqv.write_word_reg(0x0, 0x00000000 | ctrl_reg)
        assert await tqv.read_word_reg(0x0) == (0x00000000 | ctrl_reg)
       
        # Now release PRISM from reset
        await tqv.write_word_reg(0x0, 0x20000000 | ctrl_reg)

    async def test_chroma_gpio24():
        nonlocal input_value

        await load_chroma(chroma_gpio24, chroma_gpio24_ctrlReg)
        
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
    await tqv.write_word_reg(0x00, 0x20000000)
    await ClockCycles(dut.clk, 8)
    await tqv.write_word_reg(0x20, 0x0300FA12)
    await ClockCycles(dut.clk, 8)

    assert await tqv.read_word_reg(0x20) == 0x0300FA12
    assert await tqv.read_word_reg(0x0) == 0x20000000

    await tqv.write_word_reg(0x00, 0x00000000)

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
    await test_chroma_gpio24()

