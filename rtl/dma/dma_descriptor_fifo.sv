`timescale 1ns/1ps

import tensor_pkg::*;

module dma_descriptor_fifo #(
  parameter int DEPTH = 2
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,
  input  logic push_i,
  input  dma_desc_t push_desc_i,
  input  logic pop_i,
  output dma_desc_t pop_desc_o,
  output logic full_o,
  output logic empty_o
);
  localparam int COUNT_WIDTH = (DEPTH <= 2) ? 2 : $clog2(DEPTH) + 1;
  logic [COUNT_WIDTH-1:0] unused_count;

  fifo #(
    .WIDTH($bits(dma_desc_t)),
    .DEPTH(DEPTH)
  ) u_fifo (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(clear_i),
    .push_i(push_i),
    .push_data_i(push_desc_i),
    .pop_i(pop_i),
    .pop_data_o(pop_desc_o),
    .full_o(full_o),
    .empty_o(empty_o),
    .count_o(unused_count)
  );
endmodule
