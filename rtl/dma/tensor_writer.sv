module tensor_writer #(
  parameter int AXI_ADDR_WIDTH = 32,
  parameter int AXI_DATA_WIDTH = 64,
  parameter int SPAD_ADDR_WIDTH = 16,
  parameter int SPAD_DATA_WIDTH = 32,
  parameter int MAX_BURST_BEATS = 16,
  parameter int ROW_COUNT_WIDTH = 4,
  parameter int ROW_READY_WIDTH = 4
) (
  input  logic clk,
  input  logic rst_n,
  input  logic start_i,
  input  logic [31:0] ext_addr_i,
  input  logic [15:0] byte_len_i,
  input  logic [7:0]  burst_len_i,
  input  logic [15:0] spad_offset_i,
  input  logic        row_mode_i,
  input  logic [ROW_COUNT_WIDTH-1:0] row_count_i,
  input  logic [ROW_READY_WIDTH-1:0] row_ready_i,
  input  logic [15:0] row_bytes_i,
  input  logic [15:0] ext_row_stride_i,
  input  logic [15:0] spad_row_stride_i,
  output logic busy_o,
  output logic done_o,
  output logic error_o,
  output logic cross_4kb_o,

  output logic [31:0] m_axi_awaddr,
  output logic        m_axi_awid,
  output logic [7:0]  m_axi_awlen,
  output logic [2:0]  m_axi_awsize,
  output logic [1:0]  m_axi_awburst,
  output logic        m_axi_awvalid,
  input  logic        m_axi_awready,
  output logic [63:0] m_axi_wdata,
  output logic [7:0]  m_axi_wstrb,
  output logic        m_axi_wlast,
  output logic        m_axi_wvalid,
  input  logic        m_axi_wready,
  input  logic [1:0]  m_axi_bresp,
  input  logic        m_axi_bid,
  input  logic        m_axi_bvalid,
  output logic        m_axi_bready,

  output logic        spad_req_o,
  output logic        spad_we_o,
  output logic [15:0] spad_addr_o,
  input  logic [31:0] spad_rdata_i,
  input  logic        spad_ready_i
);
  logic dma_start;
  logic dma_busy;
  logic dma_done;
  logic dma_error;
  logic dma_cross_4kb;
  logic active_q;
  logic done_q;
  logic error_q;
  logic row_mode_q;
  logic row_pending_q;
  logic [ROW_COUNT_WIDTH-1:0] row_q;
  logic [ROW_COUNT_WIDTH-1:0] row_count_q;
  logic [31:0] ext_addr_q;
  logic [15:0] byte_len_q;
  logic [15:0] row_bytes_q;
  logic [15:0] ext_row_stride_q;
  logic [15:0] spad_offset_q;
  logic [15:0] spad_row_stride_q;
  logic [7:0] burst_len_q;
  logic [31:0] dma_addr;
  logic [31:0] dma_byte_len;
  logic [15:0] dma_spad_offset;
  logic row_last;

  assign busy_o = active_q || dma_busy || dma_start;
  assign done_o = done_q;
  assign error_o = error_q || dma_error;
  assign cross_4kb_o = dma_cross_4kb;
  assign row_last = row_q == (row_count_q - 1'b1);
  assign dma_addr = row_mode_q ? (ext_addr_q + (32'(row_q) * 32'(ext_row_stride_q))) :
                    ext_addr_q;
  assign dma_byte_len = row_mode_q ? 32'(row_bytes_q) : 32'(byte_len_q);
  assign dma_spad_offset = row_mode_q ?
                           (spad_offset_q + (16'(row_q) * spad_row_stride_q)) :
                           spad_offset_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dma_start <= 1'b0;
      active_q <= 1'b0;
      done_q <= 1'b0;
      error_q <= 1'b0;
      row_mode_q <= 1'b0;
      row_pending_q <= 1'b0;
      row_q <= '0;
      row_count_q <= ROW_COUNT_WIDTH'(1);
      ext_addr_q <= 32'd0;
      byte_len_q <= 16'd0;
      row_bytes_q <= 16'd0;
      ext_row_stride_q <= 16'd0;
      spad_offset_q <= 16'd0;
      spad_row_stride_q <= 16'd0;
      burst_len_q <= 8'd0;
    end else begin
      dma_start <= 1'b0;
      done_q <= 1'b0;

      if (start_i && !active_q && !dma_busy) begin
        active_q <= 1'b1;
        error_q <= 1'b0;
        row_mode_q <= row_mode_i;
        row_pending_q <= 1'b0;
        row_q <= '0;
        row_count_q <= (row_mode_i && (row_count_i != '0)) ? row_count_i : ROW_COUNT_WIDTH'(1);
        ext_addr_q <= ext_addr_i;
        byte_len_q <= byte_len_i;
        row_bytes_q <= row_mode_i ? row_bytes_i : byte_len_i;
        ext_row_stride_q <= ext_row_stride_i;
        spad_offset_q <= spad_offset_i;
        spad_row_stride_q <= spad_row_stride_i;
        burst_len_q <= burst_len_i;
        dma_start <= 1'b1;
      end else if (active_q && dma_done) begin
        error_q <= error_q || dma_error;
        if (row_last || dma_error) begin
          active_q <= 1'b0;
          row_pending_q <= 1'b0;
          done_q <= 1'b1;
        end else begin
          row_q <= row_q + 1'b1;
          if (!row_mode_q || row_ready_i[row_q + 1'b1]) begin
            dma_start <= 1'b1;
            row_pending_q <= 1'b0;
          end else begin
            row_pending_q <= 1'b1;
          end
        end
      end else if (active_q && row_pending_q && row_ready_i[row_q] && !dma_busy) begin
        dma_start <= 1'b1;
        row_pending_q <= 1'b0;
      end
    end
  end

  axi_write_dma #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .SPAD_ADDR_WIDTH(SPAD_ADDR_WIDTH),
    .SPAD_DATA_WIDTH(SPAD_DATA_WIDTH),
    .MAX_BURST_BEATS(MAX_BURST_BEATS)
  ) u_axi_write_dma (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(dma_start),
    .addr_i(dma_addr),
    .byte_len_i(dma_byte_len),
    .burst_len_i(burst_len_q),
    .spad_offset_i(dma_spad_offset),
    .busy_o(dma_busy),
    .done_o(dma_done),
    .error_o(dma_error),
    .cross_4kb_o(dma_cross_4kb),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awid(m_axi_awid),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bid(m_axi_bid),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .spad_req_o(spad_req_o),
    .spad_we_o(spad_we_o),
    .spad_addr_o(spad_addr_o),
    .spad_rdata_i(spad_rdata_i),
    .spad_ready_i(spad_ready_i)
  );
endmodule
