module axi_read_dma_formal;
  localparam int AXI_ADDR_WIDTH = 32;
  localparam int AXI_DATA_WIDTH = 64;
  localparam int SPAD_ADDR_WIDTH = 16;
  localparam int SPAD_DATA_WIDTH = 32;
  localparam int AXI_BYTES = AXI_DATA_WIDTH / 8;

  (* gclk *) logic clk;
  logic rst_n = 1'b0;
  logic past_valid = 1'b0;

  (* anyseq *) logic start_i;
  (* anyseq *) logic [AXI_ADDR_WIDTH-1:0] addr_i;
  (* anyseq *) logic [31:0] byte_len_i;
  (* anyseq *) logic [7:0] burst_len_i;
  (* anyseq *) logic [SPAD_ADDR_WIDTH-1:0] spad_offset_i;
  logic busy_o;
  logic done_o;
  logic error_o;
  logic cross_4kb_o;
  logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr;
  logic m_axi_arid;
  logic [7:0] m_axi_arlen;
  logic [2:0] m_axi_arsize;
  logic [1:0] m_axi_arburst;
  logic m_axi_arvalid;
  (* anyseq *) logic m_axi_arready;
  (* anyseq *) logic [AXI_DATA_WIDTH-1:0] m_axi_rdata;
  (* anyseq *) logic m_axi_rid;
  (* anyseq *) logic [1:0] m_axi_rresp;
  (* anyseq *) logic m_axi_rlast;
  (* anyseq *) logic m_axi_rvalid;
  logic m_axi_rready;
  logic spad_req_o;
  logic spad_we_o;
  logic [SPAD_ADDR_WIDTH-1:0] spad_addr_o;
  logic [SPAD_DATA_WIDTH-1:0] spad_wdata_o;
  logic [SPAD_DATA_WIDTH/8-1:0] spad_wstrb_o;
  (* anyseq *) logic spad_ready_i;

  axi_read_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .SPAD_ADDR_WIDTH(SPAD_ADDR_WIDTH),
    .SPAD_DATA_WIDTH(SPAD_DATA_WIDTH),
    .MAX_BURST_BEATS(4),
    .AUTO_SPLIT_4KB(1'b1)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(start_i),
    .addr_i(addr_i),
    .byte_len_i(byte_len_i),
    .burst_len_i(burst_len_i),
    .spad_offset_i(spad_offset_i),
    .busy_o(busy_o),
    .done_o(done_o),
    .error_o(error_o),
    .cross_4kb_o(cross_4kb_o),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arid(m_axi_arid),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rid(m_axi_rid),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .spad_req_o(spad_req_o),
    .spad_we_o(spad_we_o),
    .spad_addr_o(spad_addr_o),
    .spad_wdata_o(spad_wdata_o),
    .spad_wstrb_o(spad_wstrb_o),
    .spad_ready_i(spad_ready_i)
  );

  always_ff @(posedge clk) begin
    past_valid <= 1'b1;
    rst_n <= 1'b1;

    if (!past_valid) begin
      assume(!rst_n);
    end else begin
      assume(rst_n);
      assume((addr_i % AXI_BYTES) == 0);
      assume(byte_len_i <= 32'd64);
      assume((burst_len_i >= 8'd1) && (burst_len_i <= 8'd4));
      assume(!(start_i && busy_o));
      assume(!(m_axi_rvalid && !m_axi_rready));

      assert(m_axi_arburst == 2'b01);
      assert(m_axi_arsize == 3'd3);
      assert(!cross_4kb_o);
      assert(!spad_req_o || spad_we_o);
      assert(!spad_req_o || (spad_wstrb_o == '1));

      if (m_axi_arvalid) begin
        assert((m_axi_araddr % AXI_BYTES) == 0);
        assert(({20'd0, m_axi_araddr[11:0]} +
                (({24'd0, m_axi_arlen} + 32'd1) * AXI_BYTES)) <= 32'd4096);
      end

      if ($past(m_axi_rvalid && m_axi_rready && m_axi_rresp[1])) begin
        assert(error_o);
      end
    end
  end
endmodule
