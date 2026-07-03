module store_row_buffer_formal;
  localparam int TILE_M = 2;
  localparam int TILE_N = 2;
  localparam int DATA_WIDTH = 32;
  localparam int ADDR_WIDTH = 8;
  localparam int ROW_INDEX_WIDTH = 1;

  (* gclk *) logic clk;
  logic rst_n = 1'b0;
  logic past_valid = 1'b0;
  (* anyseq *) logic clear_i;
  (* anyseq *) logic row_write_i;
  (* anyseq *) logic write_bank_i;
  (* anyseq *) logic [ROW_INDEX_WIDTH-1:0] row_write_index_i;
  (* anyseq *) logic [TILE_M-1:0][TILE_N-1:0][DATA_WIDTH-1:0] tile_data_i;
  (* anyseq *) logic read_bank_i;
  (* anyseq *) logic [ROW_INDEX_WIDTH-1:0] read_row_i;
  (* anyseq *) logic read_req_i;
  (* anyseq *) logic [ADDR_WIDTH-1:0] read_addr_i;
  logic [DATA_WIDTH-1:0] read_data_o;
  logic read_ready_o;

  store_row_buffer #(
    .TILE_M(TILE_M),
    .TILE_N(TILE_N),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .ROW_INDEX_WIDTH(ROW_INDEX_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(clear_i),
    .row_write_i(row_write_i),
    .write_bank_i(write_bank_i),
    .row_write_index_i(row_write_index_i),
    .tile_data_i(tile_data_i),
    .read_bank_i(read_bank_i),
    .read_row_i(read_row_i),
    .read_req_i(read_req_i),
    .read_addr_i(read_addr_i),
    .read_data_o(read_data_o),
    .read_ready_o(read_ready_o)
  );

  always_ff @(posedge clk) begin
    past_valid <= 1'b1;
    rst_n <= 1'b1;

    if (!past_valid) begin
      assume(!rst_n);
    end else begin
      assume(rst_n);
      assume(read_addr_i < 8'd16);
      assert(read_ready_o == read_req_i);
      if ($past(clear_i)) begin
        assert(read_data_o == 32'd0);
      end
      if ($past(read_req_i && rst_n && !clear_i)) begin
        if (($past(read_row_i) + (($past(read_addr_i) / 8))) >= TILE_M) begin
          assert(read_data_o == 32'd0);
        end
      end
    end
  end
endmodule
