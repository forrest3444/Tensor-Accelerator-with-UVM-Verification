module dma_descriptor_fifo #(
  parameter int DEPTH = 2
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,
  input  logic push_i,
  input  logic [115:0] push_desc_i,
  input  logic pop_i,
  output logic [115:0] pop_desc_o,
  output logic full_o,
  output logic empty_o
);
  localparam int COUNT_WIDTH = (DEPTH <= 2) ? 2 : $clog2(DEPTH) + 1;
  logic [COUNT_WIDTH-1:0] unused_count;

  fifo #(
    .WIDTH(116),
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
