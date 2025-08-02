
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 100 ns (10 MHz)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

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
    await tqv.write_word_reg(0x00, 0x60000003)
    await ClockCycles(dut.clk, 8)
    await tqv.write_word_reg(0x20, 0x0300FA12)
    await ClockCycles(dut.clk, 8)

    assert await tqv.read_word_reg(0x20) == 0x0300FA12
    assert await tqv.read_word_reg(0x0) == 0x60000003

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

#    await tqv.write_word_reg(0x14, 0x00009090)
#    await tqv.write_word_reg(0x10, 0x90909090)

#    await tqv.write_word_reg(0x14, 0x0000a0a0)
#    await tqv.write_word_reg(0x10, 0xa0a0a0a0)

#    await tqv.write_word_reg(0x14, 0x0000b0b0)
#    await tqv.write_word_reg(0x10, 0xb0b0b0b0)

#    await tqv.write_word_reg(0x14, 0x0000c0c0)
#    await tqv.write_word_reg(0x10, 0xc0c0c0c0)


    # Wait for two clock cycles to see the output values, because ui_in is synchronized over two clocks,
    # and a further clock is required for the output to propagate.
    await ClockCycles(dut.clk, 3)

    # The following assersion is just an example of how to check the output values.
    # Change it to match the actual expected output of your module:
#    assert dut.uo_out.value == 0x96

    # Input value should be read back from register 1
#    assert await tqv.read_byte_reg(4) == 30

    # 0x10101010 should be read back from register 8
    assert await tqv.read_word_reg(0x10) == 0x10101010

    # Zero should be read back from register 2
#    assert await tqv.read_word_reg(16) == 0

    # A second write should work
#    await tqv.write_word_reg(0, 40)
#    assert dut.uo_out.value == 70

    # Test the interrupt, generated when ui_in[6] goes high
#    dut.ui_in[6].value = 1
#    await ClockCycles(dut.clk, 1)
#    dut.ui_in[6].value = 0

    # Interrupt asserted
#    await ClockCycles(dut.clk, 3)
#    assert dut.uio_out[0].value == 1

    # Interrupt doesn't clear
#    await ClockCycles(dut.clk, 10)
#    assert dut.uio_out[0].value == 1
    
    # Write bottom bit of address 8 high to clear
#    await tqv.write_byte_reg(8, 1)
#    assert dut.uio_out[0].value == 0
