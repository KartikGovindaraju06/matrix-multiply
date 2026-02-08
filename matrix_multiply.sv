// Required in every 18-240 file, but commented out to prevent synthesis issues
// `default_nettype none

// Starter code for Project 2.  See README.md for details
// Author: Srikar Govindaraju   AndrewID: srikarg

/*
This is my main module. It instantiates 16 helper modules that
each iterate through 1/16th of matrix A and perform a partial
matrix multiplication and accumulation. Then, it takes the acumulated
partial sum from each of the 16 helper modules and adds them
together. It also computes the accumulated sum of all of the elements
in matrix C independently, and adds together everything at the 
very end of the computation cycle. It takes 517 clock cycles.
*/
module ChipInterface
  (input  logic         CLOCK_100, // 100 MHZ Clock
   input  logic [15:0]  SW,
   input  logic [3:0]   BTN,
   output logic [7:0]   D0_SEG, D1_SEG,
   output logic [3:0]   D0_AN, D1_AN);

  // Synchronize the reset button and switch[0]
  logic reset_tmp, reset, switch0_tmp, switch0;
  always_ff @(posedge CLOCK_100) begin
   reset_tmp <= BTN[0];
   reset <= reset_tmp;

   switch0_tmp <= SW[0];
   switch0 <= switch0_tmp;
  end

  // Counter to keep track of where in the matrices we are
  logic [9:0] counter;
  always_ff @(posedge CLOCK_100) begin
    if (reset) counter <= '0;
    else counter <= counter + 10'b1;
  end
  
  // Keeps track of the current column we are working with (64 pairs)
  logic [5:0] col_pair;
  assign col_pair = counter[8:3];
  
  /* Keeps track of the current row we are working with 
  (8 per block -> 128 rows total)
  */
  logic [2:0] row_offset;
  assign row_offset = counter[2:0];

  // Stores the addresses for matrix A for each of the 16 ROMS
  logic [13:0] matrixA_addra [16], matrixA_addrb [16];
  logic [31:0] block_accum [16]; // Stores the 16 accumulator outputs

  // Addresses for matrix B
  logic [6:0] matrixB_addra, matrixB_addrb;
  assign matrixB_addra = {col_pair, 1'b0};
  assign matrixB_addrb = {col_pair, 1'b0} + 7'd1;
  
  // ROM instantiation for Matrix B
  logic [7:0] matrixB_douta, matrixB_doutb;
  romB_128x1 matrixB(
    .clka(CLOCK_100),
    .addra(matrixB_addra),
    .douta(matrixB_douta),
    .clkb(CLOCK_100),
    .addrb(matrixB_addrb),
    .doutb(matrixB_doutb));

  // Registers storing values read from B before multiplication
  logic [7:0] matrixB_douta_reg, matrixB_doutb_reg;
  always_ff @(posedge CLOCK_100) begin
    if (reset) begin
      matrixB_douta_reg <= '0;
      matrixB_doutb_reg <= '0;
    end
    else begin
      matrixB_douta_reg <= matrixB_douta;
      matrixB_doutb_reg <= matrixB_doutb;
    end
  end

  // generate block for the 16 ROMS + compute paths
  generate
    for (genvar g = 0; g < 16; g++) begin : matrix_mult_block_gen
      assign matrixA_addra[g] = ((8*g + row_offset) << 7) + {col_pair, 1'b0};
      assign matrixA_addrb[g] = ((8*g + row_offset) << 7) 
                                + {col_pair, 1'b0} + 14'b1;
      matrix_mult_block block(
        .clk(CLOCK_100),
        .reset(reset),
        .en(1'b1),
        .counter(counter),
        .matrixA_addra(matrixA_addra[g]),
        .matrixA_addrb(matrixA_addrb[g]),
        .matrixB_douta_reg(matrixB_douta_reg),
        .matrixB_doutb_reg(matrixB_doutb_reg),
        .accum_out(block_accum[g]));
    end : matrix_mult_block_gen
  endgenerate

  // Addresses for matrix C (2 elements at a time: 64 pairs over 64 col_pairs)
  logic [6:0] matrixC_addra, matrixC_addrb;
  assign matrixC_addra = {col_pair, 1'b0};
  assign matrixC_addrb = {col_pair, 1'b0} + 7'd1;

  logic [15:0] matrixC_douta, matrixC_doutb;
  romC_128x1 matrixC(
    .clka(CLOCK_100),
    .addra(matrixC_addra),
    .douta(matrixC_douta),
    .clkb(CLOCK_100),
    .addrb(matrixC_addrb),
    .doutb(matrixC_doutb));

  // Registers storing values read from C before accumulation
  logic [15:0] matrixC_douta_reg, matrixC_doutb_reg;
  always_ff @(posedge CLOCK_100) begin
    if (reset) begin
      matrixC_douta_reg <= '0;
      matrixC_doutb_reg <= '0;
    end
    else begin
      matrixC_douta_reg <= matrixC_douta;
      matrixC_doutb_reg <= matrixC_doutb;
    end
  end

  // Accumulate C only when we advance to a new pair (row_offset==0)
  logic en_c, en_c_reg;
  always_ff @(posedge CLOCK_100) begin
    if (reset) begin
      en_c <= 0;
      en_c_reg <= 0;
    end
    else begin
      en_c <= (row_offset == 3'b000);
      en_c_reg <= en_c;
    end
  end
  
  // Accumulated sum of all values in matrix C
  logic [31:0] matrixC_accum_out;
  always_ff @(posedge CLOCK_100) begin
    if (reset) matrixC_accum_out <= '0;
    else if (counter < 10'd512 && en_c_reg)
      matrixC_accum_out <= matrixC_accum_out 
                          + {16'b0, matrixC_douta_reg} 
                          + {16'b0, matrixC_doutb_reg};
  end
  
  // Pipelined adder reduction for the 16 block accumulators
  logic [31:0] layer1_a_reg, layer1_b_reg, layer1_c_reg, layer1_d_reg;
  logic [31:0] layer2_reg;
  logic layer1_done, layer2_done;
  always_ff @(posedge CLOCK_100) begin
    if (reset) begin
      layer1_a_reg <= '0;
      layer1_b_reg <= '0;
      layer1_c_reg <= '0;
      layer1_d_reg <= '0;
      layer2_reg <= '0;
      layer1_done <= 1'b0;
      layer2_done <= 1'b0;
    end else if (counter == 10'd515) begin
      layer1_a_reg <= block_accum[0] + block_accum[1] 
                    + block_accum[2] + block_accum[3];
      layer1_b_reg <= block_accum[4] + block_accum[5] 
                    + block_accum[6] + block_accum[7];
      layer1_c_reg <= block_accum[8] + block_accum[9] 
                    + block_accum[10] + block_accum[11];
      layer1_d_reg <= block_accum[12] + block_accum[13] 
                    + block_accum[14] + block_accum[15];
      layer1_done <= 1'b1;
    end
    else if (layer1_done) begin
      layer2_reg <= layer1_a_reg + layer1_b_reg + layer1_c_reg + layer1_d_reg;
      layer2_done <= 1;
    end
  end

  // Produce the final sum and store clock count
  logic [31:0] final_sum;
  logic [10:0] final_clock_count;
  logic display_ready;
  always_ff @(posedge CLOCK_100) begin
    if (reset) begin
      final_sum <= '0;
      final_clock_count <= '0;
      display_ready <= 1'b0;
    end
    else if (layer2_done) begin
      if (final_sum == '0) final_sum <= layer2_reg + matrixC_accum_out;
      if (final_clock_count == '0) begin
        final_clock_count <= counter;
        display_ready <= 1'b1;
      end
    end
  end

  // Wiring everything to the boolean board here
  logic [3:0] hex7, hex6, hex5, hex4, hex3, hex2, hex1, hex0;
  always_ff @(posedge CLOCK_100) begin
    if (reset) begin
      hex0 <= '0;
      hex1 <= '0;
      hex2 <= '0;
      hex3 <= '0;
      hex4 <= '0;
      hex5 <= '0;
      hex6 <= '0;
      hex7 <= '0;
    end
    else if (display_ready) begin
      hex0 <= switch0 ? final_clock_count[3:0] : final_sum[3:0];
      hex1 <= switch0 ? final_clock_count[7:4] : final_sum[7:4];
      hex2 <= switch0 ? final_clock_count[10:8] : final_sum[11:8];
      hex3 <= switch0 ? '0 : final_sum[15:12];
      hex4 <= switch0 ? '0 : final_sum[19:16];
      hex5 <= switch0 ? '0 : final_sum[23:20];
      hex6 <= switch0 ? '0 : final_sum[27:24];
      hex7 <= switch0 ? '0 : final_sum[31:28]; 
    end
  end 
  EightSevenSegmentDisplays display(
    .HEX7(hex7), 
    .HEX6(hex6),
    .HEX5(hex5), 
    .HEX4(hex4), 
    .HEX3(hex3),  
    .HEX2(hex2),
    .HEX1(hex1), 
    .HEX0(hex0),
    .CLOCK_100(CLOCK_100), 
    .reset(reset),
    .dec_points(8'b0000_0000),
    .blank(8'b0000_0000),
    .D2_AN(D1_AN), .D1_AN(D0_AN), .D2_SEG(D1_SEG), .D1_SEG(D0_SEG));

endmodule : ChipInterface

/*
This module iterates through 1/16th of the matrix A and performs 
matrix multiplication with matrix B. The values produced by this
operation are accumulated independently, and are added together
at a later stage in the pipeline, along with the value accumulated
from matrix C.
*/
module matrix_mult_block
  (input logic clk, reset, en,
   input logic [9:0] counter,
   input logic [13:0] matrixA_addra, matrixA_addrb,
   input logic [7:0] matrixB_douta_reg, matrixB_doutb_reg,
   output logic [31:0] accum_out);

  // ROM instantiation for Matrix A
  logic [7:0] matrixA_douta, matrixA_doutb;
  romA_128x128 matrixA(
    .clka(clk),
    .addra(matrixA_addra),
    .douta(matrixA_douta),
    .clkb(clk),
    .addrb(matrixA_addrb),
    .doutb(matrixA_doutb));

  // Registers storing values read from A before multiplication
  logic [7:0] matrixA_douta_reg, matrixA_doutb_reg;
  always_ff @(posedge clk) begin
    if (reset || counter > 10'd513) begin
      matrixA_douta_reg <= '0;
      matrixA_doutb_reg <= '0;
    end
    else begin
      matrixA_douta_reg <= matrixA_douta;
      matrixA_doutb_reg <= matrixA_doutb;
    end
  end

  // multiplier modules that multiply the two values read from A and B
  logic [15:0] mult1_out, mult2_out;
  multiplier_8816 mult1(
    .A(matrixA_douta_reg), 
    .B(matrixB_douta_reg), 
    .P(mult1_out));
  
  multiplier_8816 mult2(
    .A(matrixA_doutb_reg), 
    .B(matrixB_doutb_reg), 
    .P(mult2_out));

  // Registers storing multiplier outputs
  logic [15:0] mult1_out_reg, mult2_out_reg;
  always_ff @(posedge clk) begin
    if (reset || counter > 10'd514) begin
      mult1_out_reg <= '0;
      mult2_out_reg <= '0;
    end
    else begin
      mult1_out_reg <= mult1_out;
      mult2_out_reg <= mult2_out;
    end
  end

  // Accumulates running sum of each block
  always_ff @(posedge clk) begin
    if (reset)
      accum_out <= '0;
    else if (counter >= 10'd3 && counter <= 10'd514)
      accum_out <= accum_out + {16'b0, mult1_out_reg} + {16'b0, mult2_out_reg};
  end

endmodule: matrix_mult_block