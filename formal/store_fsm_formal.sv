module store_fsm_formal;
  localparam int TILE_M = 4;
  localparam int ROW_INDEX_WIDTH = 2;
  localparam int ROW_COUNT_WIDTH = 3;

  (* gclk *) logic clk;
  logic rst_n = 1'b0;
  logic past_valid = 1'b0;
  (* anyseq *) logic clear_i;
  (* anyseq *) logic start_i;
  (* anyseq *) logic row_ready_i;
  (* anyseq *) logic [ROW_INDEX_WIDTH-1:0] row_ready_index_i;
  (* anyseq *) logic pp_tile_done_i;
  (* anyseq *) logic desc_ready_i;
  (* anyseq *) logic writer_done_i;
  (* anyseq *) logic store_buffer_i;
  (* anyseq *) logic [31:0] c_ext_offset_i;
  (* anyseq *) logic [31:0] tile_rows_i;
  (* anyseq *) logic [31:0] c_row_bytes_i;
  logic desc_push_o;
  logic active_o;
  logic busy_o;
  logic done_o;
  logic [31:0] active_c_ext_offset_o;
  logic [31:0] active_c_row_bytes_o;
  logic [ROW_COUNT_WIDTH-1:0] active_row_count_o;
  logic [TILE_M-1:0] active_row_ready_o;
  logic active_buffer_o;

  store_fsm #(
    .TILE_M(TILE_M),
    .ROW_INDEX_WIDTH(ROW_INDEX_WIDTH),
    .ROW_COUNT_WIDTH(ROW_COUNT_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(clear_i),
    .start_i(start_i),
    .row_ready_i(row_ready_i),
    .row_ready_index_i(row_ready_index_i),
    .pp_tile_done_i(pp_tile_done_i),
    .desc_ready_i(desc_ready_i),
    .writer_done_i(writer_done_i),
    .store_buffer_i(store_buffer_i),
    .c_ext_offset_i(c_ext_offset_i),
    .tile_rows_i(tile_rows_i),
    .c_row_bytes_i(c_row_bytes_i),
    .desc_push_o(desc_push_o),
    .active_o(active_o),
    .busy_o(busy_o),
    .done_o(done_o),
    .active_c_ext_offset_o(active_c_ext_offset_o),
    .active_c_row_bytes_o(active_c_row_bytes_o),
    .active_row_count_o(active_row_count_o),
    .active_row_ready_o(active_row_ready_o),
    .active_buffer_o(active_buffer_o)
  );

  always_ff @(posedge clk) begin
    past_valid <= 1'b1;
    rst_n <= 1'b1;

    if (!past_valid) begin
      assume(!rst_n);
    end else begin
      assume(rst_n);
      assume(tile_rows_i <= TILE_M);
      assume(!(start_i && active_o));

      assert(busy_o == active_o);
      assert(!done_o || active_o);
      assert(!desc_push_o || active_o);
      assert(!desc_push_o || desc_ready_i);
      assert(!desc_push_o || active_row_ready_o[0]);

      if (start_i && !active_o) begin
        assert(active_c_ext_offset_o == c_ext_offset_i);
        assert(active_c_row_bytes_o == c_row_bytes_i);
        assert(active_buffer_o == store_buffer_i);
      end
    end
  end
endmodule
