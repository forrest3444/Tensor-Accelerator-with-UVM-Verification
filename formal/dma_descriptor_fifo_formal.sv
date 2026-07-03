module dma_descriptor_fifo_formal;
  localparam int DEPTH = 2;
  localparam int DESC_W = 117;

  (* gclk *) logic clk;
  logic rst_n = 1'b0;
  logic clear_i;
  (* anyseq *) logic push_i;
  (* anyseq *) logic pop_i;
  (* anyseq *) logic [DESC_W-1:0] push_desc_i;
  logic [DESC_W-1:0] pop_desc_o;
  logic full_o;
  logic empty_o;
  logic past_valid = 1'b0;

  dma_descriptor_fifo #(
    .DEPTH(DEPTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(clear_i),
    .push_i(push_i),
    .push_desc_i(push_desc_i),
    .pop_i(pop_i),
    .pop_desc_o(pop_desc_o),
    .full_o(full_o),
    .empty_o(empty_o)
  );

  always_ff @(posedge clk) begin
    past_valid <= 1'b1;
    rst_n <= 1'b1;
    clear_i <= 1'b0;

    if (!past_valid) begin
      assume(!rst_n);
      clear_i <= 1'b1;
    end else begin
      assume(rst_n);
      assume(!(push_i && full_o && !pop_i));
      assume(!(pop_i && empty_o && !push_i));
      assert(!(full_o && empty_o));
    end
  end
endmodule
