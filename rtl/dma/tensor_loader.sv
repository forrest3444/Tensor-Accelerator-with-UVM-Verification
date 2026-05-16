module tensor_loader (
  input  logic clk,
  input  logic rst_n,
  input  logic start_i,
  input  logic [31:0] ext_addr_i,
  input  logic [31:0] byte_len_i,
  input  logic [15:0] spad_offset_i,
  input  logic        row_mode_i,
  input  logic [2:0]  row_count_i,
  input  logic [31:0] row_bytes_i,
  input  logic [31:0] ext_row_stride_i,
  input  logic [15:0] spad_row_stride_i,
  output logic busy_o,
  output logic done_o,
  output logic error_o,
  output logic cross_4kb_o,

  output logic [31:0] m_axi_araddr,
  output logic        m_axi_arid,
  output logic [7:0]  m_axi_arlen,
  output logic [2:0]  m_axi_arsize,
  output logic [1:0]  m_axi_arburst,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,
  input  logic [63:0] m_axi_rdata,
  input  logic        m_axi_rid,
  input  logic [1:0]  m_axi_rresp,
  input  logic        m_axi_rlast,
  input  logic        m_axi_rvalid,
  output logic        m_axi_rready,

  output logic        spad_req_o,
  output logic        spad_we_o,
  output logic [15:0] spad_addr_o,
  output logic [31:0] spad_wdata_o,
  output logic [3:0]  spad_wstrb_o,
  input  logic        spad_ready_i
);
  logic dma_start;
  logic [31:0] dma_addr;
  logic [31:0] dma_byte_len;
  logic [15:0] dma_spad_offset;
  logic dma_busy;
  logic dma_done;
  logic dma_error;
  logic dma_cross_4kb;

  logic active_q;
  logic done_q;
  logic error_q;
  logic cross_4kb_q;
  logic row_start_pending_q;
  logic [2:0] row_q;
  logic [31:0] base_ext_addr_q;
  logic [31:0] base_byte_len_q;
  logic [15:0] base_spad_offset_q;
  logic row_mode_q;
  logic [2:0] row_count_q;
  logic [31:0] row_bytes_q;
  logic [31:0] ext_row_stride_q;
  logic [15:0] spad_row_stride_q;
  logic [31:0] row_ext_addr;
  logic [31:0] row_align_bytes;
  logic [31:0] row_offset;
  logic [15:0] row_spad_offset;
  logic last_row;
  logic launch_first;
  logic row_mode_eff;
  logic [2:0] row_eff;
  logic [31:0] base_ext_addr_eff;
  logic [31:0] base_byte_len_eff;
  logic [15:0] base_spad_offset_eff;
  logic [31:0] row_bytes_eff;
  logic [31:0] ext_row_stride_eff;
  logic [15:0] spad_row_stride_eff;

  assign launch_first = start_i && !active_q && !dma_busy && !done_q;
  assign row_eff = row_q;
  assign row_mode_eff = launch_first ? row_mode_i : row_mode_q;
  assign base_ext_addr_eff = launch_first ? ext_addr_i : base_ext_addr_q;
  assign base_byte_len_eff = launch_first ? byte_len_i : base_byte_len_q;
  assign base_spad_offset_eff = launch_first ? spad_offset_i : base_spad_offset_q;
  assign row_bytes_eff = launch_first ? row_bytes_i : row_bytes_q;
  assign ext_row_stride_eff = launch_first ? ext_row_stride_i : ext_row_stride_q;
  assign spad_row_stride_eff = launch_first ? spad_row_stride_i : spad_row_stride_q;
  assign row_offset = {29'd0, row_eff} * ext_row_stride_eff;
  assign row_ext_addr = base_ext_addr_eff + (row_mode_eff ? row_offset : 32'd0);
  assign row_align_bytes = row_mode_eff ? (row_ext_addr % 32'd8) : 32'd0;
  assign row_spad_offset = base_spad_offset_eff +
                           (row_mode_eff ? ({13'd0, row_eff} * spad_row_stride_eff) : 16'd0);
  assign dma_addr = row_ext_addr - row_align_bytes;
  assign dma_byte_len = row_mode_eff ? (row_bytes_eff + row_align_bytes) : base_byte_len_eff;
  assign dma_spad_offset = row_spad_offset;
  assign last_row = !row_mode_q || (row_q == (row_count_q - 1'b1));
  assign busy_o = active_q || dma_busy;
  assign done_o = done_q;
  assign error_o = error_q || dma_error;
  assign cross_4kb_o = cross_4kb_q || dma_cross_4kb;

  axi_read_dma u_axi_read_dma (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(dma_start),
    .addr_i(dma_addr),
    .byte_len_i(dma_byte_len),
    .spad_offset_i(dma_spad_offset),
    .busy_o(dma_busy),
    .done_o(dma_done),
    .error_o(dma_error),
    .cross_4kb_o(dma_cross_4kb),
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

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_q <= 1'b0;
      done_q <= 1'b0;
      error_q <= 1'b0;
      cross_4kb_q <= 1'b0;
      dma_start <= 1'b0;
      row_start_pending_q <= 1'b0;
      row_q <= 3'd0;
      base_ext_addr_q <= 32'd0;
      base_byte_len_q <= 32'd0;
      base_spad_offset_q <= 16'd0;
      row_mode_q <= 1'b0;
      row_count_q <= 3'd1;
      row_bytes_q <= 32'd0;
      ext_row_stride_q <= 32'd0;
      spad_row_stride_q <= 16'd0;
    end else begin
      done_q <= 1'b0;
      dma_start <= 1'b0;

      if (row_start_pending_q && !dma_busy) begin
        dma_start <= 1'b1;
        row_start_pending_q <= 1'b0;
      end else if (start_i && !active_q && !dma_busy && !done_q) begin
        active_q <= 1'b1;
        error_q <= 1'b0;
        cross_4kb_q <= 1'b0;
        row_q <= 3'd0;
        base_ext_addr_q <= ext_addr_i;
        base_byte_len_q <= byte_len_i;
        base_spad_offset_q <= spad_offset_i;
        row_mode_q <= row_mode_i;
        row_count_q <= (row_count_i == 3'd0) ? 3'd1 : row_count_i;
        row_bytes_q <= row_bytes_i;
        ext_row_stride_q <= ext_row_stride_i;
        spad_row_stride_q <= spad_row_stride_i;
        dma_start <= 1'b1;
      end else if (active_q && dma_done) begin
        error_q <= error_q || dma_error;
        cross_4kb_q <= cross_4kb_q || dma_cross_4kb;
        if (last_row) begin
          active_q <= 1'b0;
          done_q <= 1'b1;
        end else begin
          row_q <= row_q + 1'b1;
          row_start_pending_q <= 1'b1;
        end
      end else if (active_q) begin
        error_q <= error_q || dma_error;
        cross_4kb_q <= cross_4kb_q || dma_cross_4kb;
      end
    end
  end
endmodule
