module axi_write_dma #(
  parameter int AXI_ADDR_WIDTH = 32,
  parameter int AXI_DATA_WIDTH = 64,
  parameter int SPAD_ADDR_WIDTH = 16,
  parameter int SPAD_DATA_WIDTH = 32,
  parameter int MAX_BURST_BEATS = 16
) (
  input  logic clk,
  input  logic rst_n,
  input  logic start_i,
  input  logic [AXI_ADDR_WIDTH-1:0] addr_i,
  input  logic [31:0] byte_len_i,
  input  logic [SPAD_ADDR_WIDTH-1:0] spad_offset_i,
  output logic busy_o,
  output logic done_o,
  output logic error_o,
  output logic cross_4kb_o,

  output logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
  output logic m_axi_awid,
  output logic [7:0] m_axi_awlen,
  output logic [2:0] m_axi_awsize,
  output logic [1:0] m_axi_awburst,
  output logic m_axi_awvalid,
  input  logic m_axi_awready,
  output logic [AXI_DATA_WIDTH-1:0] m_axi_wdata,
  output logic [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
  output logic m_axi_wlast,
  output logic m_axi_wvalid,
  input  logic m_axi_wready,
  input  logic [1:0] m_axi_bresp,
  input  logic m_axi_bid,
  input  logic m_axi_bvalid,
  output logic m_axi_bready,

  output logic spad_req_o,
  output logic spad_we_o,
  output logic [SPAD_ADDR_WIDTH-1:0] spad_addr_o,
  input  logic [SPAD_DATA_WIDTH-1:0] spad_rdata_i,
  input  logic spad_ready_i
);
  localparam int AXI_BYTES = AXI_DATA_WIDTH / 8;
  localparam int SPAD_WORDS_PER_BEAT = AXI_DATA_WIDTH / SPAD_DATA_WIDTH;
  localparam logic [2:0] AXI_SIZE = 3'($clog2(AXI_BYTES));
  localparam logic [$clog2(SPAD_WORDS_PER_BEAT)-1:0] LAST_WORD =
      $clog2(SPAD_WORDS_PER_BEAT)'(SPAD_WORDS_PER_BEAT - 1);
  localparam logic [SPAD_ADDR_WIDTH-1:0] SPAD_WORD_BYTES =
      SPAD_ADDR_WIDTH'(SPAD_DATA_WIDTH / 8);

  typedef enum logic [2:0] {S_IDLE, S_AW, S_READ_REQ, S_READ_DATA, S_W, S_B, S_DONE} state_e;
  state_e state_q, state_d;
  logic [7:0] burst_beats;
  logic [31:0] burst_bytes;
  logic splitter_valid;
  logic [7:0] beat_count_q;
  logic [$clog2(SPAD_WORDS_PER_BEAT)-1:0] word_count_q;
  logic [AXI_DATA_WIDTH-1:0] wdata_q;
  logic [31:0] bytes_sent;
  logic [31:0] aligned_addr;
  logic [31:0] addr_byte_offset;
  logic [31:0] transfer_bytes;
  logic [31:0] slot_index;
  logic [31:0] slot_byte_base;
  logic [31:0] slot_word_index;
  logic        slot_valid;
  logic        word_aligned_xfer;
  logic [AXI_DATA_WIDTH/8-1:0] active_wstrb;

  dma_burst_splitter #(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .MAX_BURST_BEATS(MAX_BURST_BEATS),
    .AUTO_SPLIT_4KB(1'b0)
  ) u_splitter (
    .addr_i(aligned_addr),
    .bytes_i(transfer_bytes),
    .burst_beats_o(burst_beats),
    .burst_bytes_o(burst_bytes),
    .crosses_4kb_o(cross_4kb_o),
    .valid_o(splitter_valid)
  );

  assign aligned_addr = {addr_i[AXI_ADDR_WIDTH-1:3], 3'b000};
  assign addr_byte_offset = {29'd0, addr_i[2:0]};
  assign transfer_bytes = byte_len_i + addr_byte_offset;
  assign word_aligned_xfer = (addr_i[1:0] == 2'b00) && (byte_len_i[1:0] == 2'b00);
  assign m_axi_awaddr = aligned_addr;
  assign m_axi_awid = 1'b0;
  assign m_axi_awlen = burst_beats - 8'd1;
  assign m_axi_awsize = AXI_SIZE;
  assign m_axi_awburst = 2'b01;
  assign m_axi_awvalid = (state_q == S_AW);
  assign m_axi_wdata = wdata_q;
  assign bytes_sent = {24'd0, beat_count_q} * AXI_BYTES;
  assign slot_index = (bytes_sent + (word_count_q * SPAD_WORD_BYTES)) >> 2;
  assign slot_byte_base = slot_index << 2;
  assign slot_valid = (slot_byte_base >= addr_byte_offset) &&
                      (slot_byte_base < (addr_byte_offset + byte_len_i));
  assign slot_word_index = slot_valid ? ((slot_byte_base - addr_byte_offset) >> 2) : 32'd0;
  always_comb begin
    active_wstrb = '0;
    for (int lane = 0; lane < AXI_BYTES; lane++) begin
      logic [31:0] byte_pos;

      byte_pos = bytes_sent + lane[31:0];
      active_wstrb[lane] = (byte_pos >= addr_byte_offset) &&
                            (byte_pos < (addr_byte_offset + byte_len_i));
    end
  end
  assign m_axi_wstrb = active_wstrb;
  assign m_axi_wlast = (beat_count_q == burst_beats - 1);
  assign m_axi_wvalid = (state_q == S_W);
  assign m_axi_bready = (state_q == S_B);
  assign spad_req_o = (state_q == S_READ_REQ) && slot_valid;
  assign spad_we_o = 1'b0;
  assign spad_addr_o = spad_offset_i + (SPAD_ADDR_WIDTH'(slot_word_index) * SPAD_WORD_BYTES);
  assign busy_o = (state_q != S_IDLE) && (state_q != S_DONE);
  assign done_o = (state_q == S_DONE);

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      S_IDLE: if (start_i && splitter_valid && word_aligned_xfer) state_d = S_AW;
      S_AW:   if (m_axi_awvalid && m_axi_awready) state_d = S_READ_REQ;
      S_READ_REQ: if (!slot_valid || spad_ready_i) state_d = S_READ_DATA;
      S_READ_DATA: state_d = (word_count_q == LAST_WORD) ? S_W : S_READ_REQ;
      S_W:    if (m_axi_wvalid && m_axi_wready) begin
                state_d = m_axi_wlast ? S_B : S_READ_REQ;
              end
      S_B:    if (m_axi_bvalid && m_axi_bready) state_d = S_DONE;
      S_DONE: state_d = S_IDLE;
      default: state_d = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      error_o <= 1'b0;
      beat_count_q <= '0;
      word_count_q <= '0;
      wdata_q <= '0;
    end else begin
      state_q <= state_d;
      if (state_q == S_IDLE && start_i) begin
        error_o <= !splitter_valid || !word_aligned_xfer;
        beat_count_q <= '0;
        word_count_q <= '0;
        wdata_q <= '0;
      end
      if (state_q == S_READ_DATA) begin
        if (slot_valid) begin
          wdata_q[word_count_q*SPAD_DATA_WIDTH +: SPAD_DATA_WIDTH] <= spad_rdata_i;
        end else begin
          wdata_q[word_count_q*SPAD_DATA_WIDTH +: SPAD_DATA_WIDTH] <= '0;
        end
        if (word_count_q == LAST_WORD) begin
          word_count_q <= '0;
        end else begin
          word_count_q <= word_count_q + 1'b1;
        end
      end
      if (m_axi_wvalid && m_axi_wready) begin
        beat_count_q <= beat_count_q + 1'b1;
      end
      if (m_axi_bvalid && m_axi_bready && m_axi_bresp[1]) begin
        error_o <= 1'b1;
      end
    end
  end
endmodule
