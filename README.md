**Matrix Multiply Implementation**

This document explains the implementation in `matrix_multiply.sv` (top-level module `ChipInterface` and helper `matrix_mult_block`). It focuses on structure, dataflow, timing, and how the ROM/COE files and testbench relate to the design.

**Overview**:
- **Purpose**: Compute the matrix multiplication (and a separate accumulation of matrix C) using a blocked, pipelined approach. The design finishes the full computation in ~517 clock cycles on a 100 MHz clock as implemented.
- **Top modules**: `ChipInterface` (top-level controller + display) and `matrix_mult_block` (16 identical blocks performing partial multiplies/accumulates).

**High-level dataflow**:
- The design treats the 128x128 matrix problem in 16 row-blocks (each block handles 8 rows). `ChipInterface` instantiates 16 `matrix_mult_block` instances.
- Each cycle the design reads two elements from each of: a block-specific ROM for `A`, a shared ROM for `B` (two addresses per cycle), and a ROM for `C` (used for separate accumulation).
- Each `matrix_mult_block` multiplies two pairs of 8-bit A and 8-bit B values using `multiplier_8816` instances, registers the multiplier outputs, and accumulates them into a 32-bit `accum_out` for that block.

**Addressing and iteration**:
- A single 10-bit free-running `counter` in `ChipInterface` drives the computation. The counter maps to:
  - `col_pair = counter[8:3]` — which column-pair (0..63)
  - `row_offset = counter[2:0]` — offset inside an 8-row block (0..7)
- For block index `g` (0..15), addresses into A are computed as `((8*g + row_offset) << 7) + {col_pair,1'b0}` and the next address (`+1`) to fetch two elements per clock.
- B addresses use `{col_pair,1'b0}` and `{col_pair,1'b0} + 1` to provide the matching B pair for the two A values.

**`matrix_mult_block` behavior**:
- Instantiates a ROM `romA_128x128` to read two A bytes per cycle, registers them, multiplies each with the corresponding registered B byte (from top-level registers), and registers multiplier outputs.
- Accumulation: when `counter` is in the active window (from about cycle 3 up to 514), the block adds the registered products (zero-extended to 32 bits) into `accum_out` each clock. The block therefore produces a 32-bit partial sum for its assigned rows.

**Final reduction and C-accumulation**:
- After all blocks finish their accumulation, `ChipInterface` reduces the 16 `block_accum` values using a staged (pipelined) adder structure:
  - Stage 1: sum groups of 4 blocks into four 32-bit registers (`layer1_*_reg`)
  - Stage 2: sum the four stage-1 results into `layer2_reg`.
- The design also separately accumulates all values from ROM `C` into `matrixC_accum_out`. `matrixC` reads two 16-bit C elements per cycle and adds them (zero-extended to 32 bits) when `row_offset == 0` (so it accumulates once per 8-cycle group).
- The final output `final_sum` is computed as `layer2_reg + matrixC_accum_out` once the pipeline reduction finishes; `final_clock_count` captures the terminating `counter` value for display.

**Timing and control**:
- The design relies on simple synchronous registers and a single `CLOCK_100` clock. The `reset` synchronizes via `BTN[0]`.
- The top-level control uses fixed counter windows to enable reads, multiplication, accumulation, and the final reduction. The code uses small pipeline stages to allow combinational adders to settle across cycles.

**ROMs and data files**:
- The design references ROM modules generated from COE files in this folder. Example files include `matA.coe`, `matB.coe`, `matC.coe` and chunked versions like `matA_1.coe`..`matA_6.coe`. These COE files provide the ROM initialization data used by `romA_128x128`, `romB_128x1`, and `romC_128x1` during simulation/synthesis.

**Testbench and verification**:
- See `matmul_test.sv` for the provided testbench that exercises the design in simulation. The repository also includes `matmult_expected_val.py` which computes the expected results for comparison during verification.
- Simulation artifacts for XSIM are present under `xsim.dir/` (prebuilt runs/objects). To run full simulation manually, use Vivado/XSIM commands that compile the design and run `matmul_test` (or use the provided script/IDE flow documented in the project README).

**How to interpret outputs**:
- `final_sum` is the 32-bit sum of the reduced matrix-multiplication result (sum over all computed products) plus the accumulated sum of entries in matrix C.
- `final_clock_count` records the `counter` value when the design finished; toggling `SW[0]` switches the seven-segment display between `final_sum` and `final_clock_count`.

**Files of interest**:
- `matrix_multiply.sv` — implementation explained here.
- `matmul_test.sv` — simulation testbench.
- `matmult_expected_val.py` — expected-value generator.
- `matA*.coe`, `matB*.coe`, `matC*.coe` — ROM initialization data files.

If you want, I can also add example XSIM run commands or a short section showing where each ROM module is instantiated in the sources. Want me to add that?
