# Project 4 - Pipelined Processor (ECSE 425)

This project implements a 5-stage pipelined RISC-V processor in VHDL and includes a ModelSim testbench flow.

## Overview

The processor has the classic 5 stages:

1. IF (Instruction Fetch)
2. ID (Instruction Decode / Register Read)
3. EX (Execute / Branch Resolve)
4. MEM (Data Memory)
5. WB (Write Back)

Key modules:

- `processor.vhd`: top-level pipeline
- `pipeline_types.vhd`: shared types, opcodes, helper functions
- `control.vhd`: instruction decode and control generation
- `imm_gen.vhd`: immediate extraction
- `alu.vhd`: ALU operations (including `mul`)
- `register_file.vhd`: 32x32 register file
- `memory.vhd`: RAM used for both instruction and data memories
- `hazard_detection.vhd`: stall-only RAW hazard detection (no forwarding)
- `testbench.vhd`: program load, execution, assertions, memory/register dump
- `testbench.tcl`: ModelSim automation script

## Current Memory Behavior

`memory.vhd` currently uses:

- synchronous write (on rising edge)
- combinatorial read (`readdata <= ram_block(address)`)

This allows same-cycle read/write behavior for the same address in simulation semantics.

## Program Files

Assembly and machine-code tests are in:

- `no_hazard_examples/`

Current `testbench.tcl` default program source is:

- `no_hazard_examples/hazard_simple.txt`

If you want to test another program, change `program_source` in `testbench.tcl`.

## How To Run (ModelSim)

From `Project_4_Pipelined_Processor/`:

```tcl
vsim -c -do testbench.tcl
```

or GUI mode:

```tcl
vsim -do testbench.tcl
```

The script will:

1. compile all design files
2. copy selected program to `program.txt`
3. run simulation for a fixed duration
4. check output files exist

## Outputs

After a successful run:

- `memory.txt` (8192 words dumped by testbench)
- `register_file.txt` (x0..x31)

## Assertions in Testbench

`testbench.vhd` currently checks expected architectural state for the selected default program (`hazard_simple`).

If you switch test programs, update assertions in `testbench.vhd` accordingly.

## Notes

- This project currently uses stall-based hazard handling (no forwarding).
- Branch/jump handling is resolved in EX with pipeline flush on redirect.
- The assembler utility is under `riscv_assembler/` (separate README available there).
