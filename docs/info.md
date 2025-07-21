<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## What it does

This is a Programmable Reconfigurable Indexed State Machine (PRISM) that executes a Verilog coded
state machine that is loaded via a configuration bitstream at runtime.

## Register map

Document the registers that are used to interact with your peripheral

| Address | Name  | Access | Description                                                         |
|---------|-------|--------|---------------------------------------------------------------------|
| 0x00    | DATA  | R/W    | A word of data                                                      |

## How to test

1.  First define a Finite State Machine with inputs and outputs.
2.  Write Verilog to describe your FSM in Mealy format.
3.  Generate a bitstream using the custom branch of Yosys that supports PRISM (use the provided config file).
4.  Replace the programming bitstream in the provided C code with your FSM bitstream.

## External hardware

No external HW required other than anything custom you might want to control from the programmable FSM.
