module dma_burst_splitter_formal;
  localparam int AXI_DATA_WIDTH = 64;
  localparam int MAX_BURST_BEATS = 16;
  localparam int BEAT_BYTES = AXI_DATA_WIDTH / 8;

  (* anyseq *) logic [31:0] addr_i;
  (* anyseq *) logic [31:0] bytes_i;
  (* anyseq *) logic [7:0] burst_len_i;

  logic [7:0] auto_beats;
  logic [31:0] auto_bytes;
  logic auto_cross;
  logic auto_valid;
  logic [7:0] noauto_beats;
  logic [31:0] noauto_bytes;
  logic noauto_cross;
  logic noauto_valid;

  dma_burst_splitter #(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .MAX_BURST_BEATS(MAX_BURST_BEATS),
    .AUTO_SPLIT_4KB(1'b1)
  ) dut_auto (
    .addr_i(addr_i),
    .bytes_i(bytes_i),
    .burst_len_i(burst_len_i),
    .burst_beats_o(auto_beats),
    .burst_bytes_o(auto_bytes),
    .crosses_4kb_o(auto_cross),
    .valid_o(auto_valid)
  );

  dma_burst_splitter #(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .MAX_BURST_BEATS(MAX_BURST_BEATS),
    .AUTO_SPLIT_4KB(1'b0)
  ) dut_noauto (
    .addr_i(addr_i),
    .bytes_i(bytes_i),
    .burst_len_i(burst_len_i),
    .burst_beats_o(noauto_beats),
    .burst_bytes_o(noauto_bytes),
    .crosses_4kb_o(noauto_cross),
    .valid_o(noauto_valid)
  );

  always_comb begin
    assume(bytes_i <= 32'd8192);
    assume((addr_i % BEAT_BYTES) == 0);

    assert(auto_cross == noauto_cross);
    assert(auto_cross == (bytes_i > (32'd4096 - {20'd0, addr_i[11:0]})));

    if (auto_valid) begin
      assert(bytes_i != 32'd0);
      assert(burst_len_i != 8'd0);
      assert(auto_bytes != 32'd0);
      assert(auto_bytes <= bytes_i);
      assert(auto_bytes <= 32'(MAX_BURST_BEATS * BEAT_BYTES));
      assert(({20'd0, addr_i[11:0]} + auto_bytes) <= 32'd4096);
      assert(auto_beats != 8'd0);
    end

    if (noauto_valid) begin
      assert(!noauto_cross);
      assert(noauto_bytes <= bytes_i);
      assert(noauto_bytes <= 32'(MAX_BURST_BEATS * BEAT_BYTES));
    end else if ((bytes_i != 32'd0) && (burst_len_i != 8'd0)) begin
      assert(noauto_cross);
    end
  end
endmodule
