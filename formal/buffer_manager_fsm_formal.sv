module buffer_manager_fsm_formal;
  (* gclk *) logic clk;
  logic rst_n = 1'b0;
  logic past_valid = 1'b0;
  (* anyseq *) logic clear_i;
  (* anyseq *) logic [5:0] tile_m_i;
  (* anyseq *) logic [5:0] tile_n_i;
  (* anyseq *) logic [31:0] tile_m_count_i;
  (* anyseq *) logic last_tile_i;
  (* anyseq *) logic store_buffer_i;
  (* anyseq *) logic store_start_i;
  (* anyseq *) logic store_done_i;
  logic current_buffer_o;
  logic next_buffer_free_o;
  logic next_load_prefetch_safe_o;
  logic [15:0] a_spad_base_o;
  logic [15:0] b_spad_base_o;
  logic [15:0] bias_spad_base_o;
  logic b_load_needed_o;

  buffer_manager_fsm dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(clear_i),
    .tile_m_i(tile_m_i),
    .tile_n_i(tile_n_i),
    .tile_m_count_i(tile_m_count_i),
    .last_tile_i(last_tile_i),
    .store_buffer_i(store_buffer_i),
    .store_start_i(store_start_i),
    .store_done_i(store_done_i),
    .current_buffer_o(current_buffer_o),
    .next_buffer_free_o(next_buffer_free_o),
    .next_load_prefetch_safe_o(next_load_prefetch_safe_o),
    .a_spad_base_o(a_spad_base_o),
    .b_spad_base_o(b_spad_base_o),
    .bias_spad_base_o(bias_spad_base_o),
    .b_load_needed_o(b_load_needed_o)
  );

  always_ff @(posedge clk) begin
    past_valid <= 1'b1;
    rst_n <= 1'b1;

    if (!past_valid) begin
      assume(!rst_n);
    end else begin
      assume(rst_n);
      assume((tile_m_count_i >= 32'd1) && (tile_m_count_i <= 32'd16));
      assume(tile_m_i < tile_m_count_i[5:0]);

      assert((a_spad_base_o == 16'h0000) || (a_spad_base_o == 16'h0400));
      assert(b_spad_base_o == 16'h0800);
      assert(bias_spad_base_o == 16'h0c00);
      assert(b_load_needed_o == (tile_m_i == 6'd0));
      assert(!next_load_prefetch_safe_o || next_buffer_free_o);

      if (!last_tile_i && next_load_prefetch_safe_o) begin
        assert(tile_m_i != (tile_m_count_i[5:0] - 1'b1));
      end
    end
  end
endmodule
