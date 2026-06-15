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
  input  logic [7:0] burst_len_i,
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
  localparam int BEAT_COUNT_WIDTH = (MAX_BURST_BEATS <= 1) ? 1 : $clog2(MAX_BURST_BEATS);
  localparam int WORD_COUNT_WIDTH = (SPAD_WORDS_PER_BEAT <= 1) ? 1 : $clog2(SPAD_WORDS_PER_BEAT);
  localparam int SEG_BYTES_WIDTH = 16;
  localparam logic [SEG_BYTES_WIDTH-1:0] AXI_BYTES_SEG = SEG_BYTES_WIDTH'(AXI_BYTES);
  localparam logic [SEG_BYTES_WIDTH-1:0] SPAD_WORD_BYTES_SEG = SEG_BYTES_WIDTH'(SPAD_DATA_WIDTH / 8);
  localparam logic [2:0] AXI_SIZE = 3'($clog2(AXI_BYTES));
  localparam logic [WORD_COUNT_WIDTH-1:0] LAST_WORD =
      WORD_COUNT_WIDTH'(SPAD_WORDS_PER_BEAT - 1);
  localparam logic [SPAD_ADDR_WIDTH-1:0] SPAD_WORD_BYTES =
      SPAD_ADDR_WIDTH'(SPAD_DATA_WIDTH / 8);

  typedef enum logic [10:0] {
    S_IDLE      = 11'b000_0000_0001,
    S_START     = 11'b000_0000_0010,
    S_SPLIT     = 11'b000_0000_0100,
    S_PLAN      = 11'b000_0000_1000,
    S_AW        = 11'b000_0001_0000,
    S_READ_REQ  = 11'b000_0010_0000,
    S_READ_DATA = 11'b000_0100_0000,
    S_W         = 11'b000_1000_0000,
    S_B         = 11'b001_0000_0000,
    S_B_RESP    = 11'b010_0000_0000,
    S_DONE      = 11'b100_0000_0000
  } state_e;
  state_e state_q, state_d;
  logic [7:0] burst_beats;
  logic [31:0] burst_bytes;
  logic splitter_valid;
  logic splitter_cross_4kb;
  logic [7:0] burst_beats_q;
  logic [SEG_BYTES_WIDTH-1:0] burst_bytes_q;
  logic splitter_valid_q;
  logic splitter_cross_4kb_q;
  logic plan_ready_q;
  logic segment_continue_q;
  logic [BEAT_COUNT_WIDTH-1:0] beat_count_q;
  logic [WORD_COUNT_WIDTH-1:0] word_count_q;
  logic [AXI_DATA_WIDTH-1:0] wdata_q;
  logic [AXI_ADDR_WIDTH-1:0] addr_q;
  logic [31:0] bytes_remaining_q;
  logic [SPAD_ADDR_WIDTH-1:0] spad_offset_q;
  logic [7:0] burst_len_q;
  logic [AXI_ADDR_WIDTH-1:0] aligned_addr;
  logic [2:0] addr_byte_offset;
  logic [2:0] addr_byte_offset_q;
  logic [31:0] transfer_bytes;
  logic [31:0] splitter_addr_q;
  logic [31:0] splitter_bytes_q;
  logic [7:0] splitter_burst_len_q;
  logic [SEG_BYTES_WIDTH-1:0] segment_data_bytes;
  logic [SEG_BYTES_WIDTH-1:0] segment_data_bytes_q;
  logic word_aligned_xfer_q;
  logic slot_valid_q;
  logic [AXI_DATA_WIDTH/8-1:0] wstrb_q;
  logic beat_last_q;
  logic bresp_error_q;
  logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr_q;
  logic m_axi_awid_q;
  logic [7:0] m_axi_awlen_q;
  logic [2:0] m_axi_awsize_q;
  logic [1:0] m_axi_awburst_q;
  logic m_axi_awvalid_q;
  logic [SPAD_ADDR_WIDTH-1:0] spad_addr_q;

  function automatic logic [SEG_BYTES_WIDTH-1:0] beat_byte_base(
    input logic [BEAT_COUNT_WIDTH-1:0] beat_idx
  );
    beat_byte_base = SEG_BYTES_WIDTH'(beat_idx) * AXI_BYTES_SEG;
  endfunction

  function automatic logic [SEG_BYTES_WIDTH-1:0] slot_byte_base_for(
    input logic [BEAT_COUNT_WIDTH-1:0] beat_idx,
    input logic [WORD_COUNT_WIDTH-1:0] word_idx
  );
    slot_byte_base_for = beat_byte_base(beat_idx) +
                         (SEG_BYTES_WIDTH'(word_idx) * SPAD_WORD_BYTES_SEG);
  endfunction

  function automatic logic slot_valid_for(
    input logic [BEAT_COUNT_WIDTH-1:0] beat_idx,
    input logic [WORD_COUNT_WIDTH-1:0] word_idx
  );
    logic [SEG_BYTES_WIDTH-1:0] slot_byte_base;
    logic [SEG_BYTES_WIDTH-1:0] byte_offset;
    logic [SEG_BYTES_WIDTH-1:0] segment_limit;
    begin
      slot_byte_base = slot_byte_base_for(beat_idx, word_idx);
      byte_offset = {13'd0, addr_byte_offset_q};
      segment_limit = byte_offset + segment_data_bytes_q;
      slot_valid_for = (slot_byte_base >= byte_offset) && (slot_byte_base < segment_limit);
    end
  endfunction

  function automatic logic [SPAD_ADDR_WIDTH-1:0] spad_addr_for(
    input logic [BEAT_COUNT_WIDTH-1:0] beat_idx,
    input logic [WORD_COUNT_WIDTH-1:0] word_idx
  );
    logic [SEG_BYTES_WIDTH-1:0] slot_byte_base;
    logic [SEG_BYTES_WIDTH-1:0] byte_offset;
    logic [SEG_BYTES_WIDTH-1:0] slot_word_index;
    begin
      slot_byte_base = slot_byte_base_for(beat_idx, word_idx);
      byte_offset = {13'd0, addr_byte_offset_q};
      slot_word_index = (slot_byte_base - byte_offset) >> 2;
      spad_addr_for = spad_offset_q +
                      (SPAD_ADDR_WIDTH'(slot_word_index) * SPAD_WORD_BYTES);
    end
  endfunction

  function automatic logic [AXI_DATA_WIDTH/8-1:0] wstrb_for(
    input logic [BEAT_COUNT_WIDTH-1:0] beat_idx
  );
    logic [SEG_BYTES_WIDTH-1:0] byte_base;
    logic [SEG_BYTES_WIDTH-1:0] byte_offset;
    logic [SEG_BYTES_WIDTH-1:0] segment_limit;
    logic [SEG_BYTES_WIDTH-1:0] byte_pos;
    begin
      byte_base = beat_byte_base(beat_idx);
      byte_offset = {13'd0, addr_byte_offset_q};
      segment_limit = byte_offset + segment_data_bytes_q;
      wstrb_for = '0;
      for (int lane = 0; lane < AXI_BYTES; lane++) begin
        byte_pos = byte_base + SEG_BYTES_WIDTH'(lane);
        wstrb_for[lane] = (byte_pos >= byte_offset) && (byte_pos < segment_limit);
      end
    end
  endfunction

  dma_burst_splitter #(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .MAX_BURST_BEATS(MAX_BURST_BEATS),
    .AUTO_SPLIT_4KB(1'b1)
  ) u_splitter (
    .addr_i(splitter_addr_q),
    .bytes_i(splitter_bytes_q),
    .burst_len_i(splitter_burst_len_q),
    .burst_beats_o(burst_beats),
    .burst_bytes_o(burst_bytes),
    .crosses_4kb_o(splitter_cross_4kb),
    .valid_o(splitter_valid)
  );

  assign aligned_addr = {addr_q[AXI_ADDR_WIDTH-1:3], 3'b000};
  assign addr_byte_offset = addr_q[2:0];
  assign transfer_bytes = bytes_remaining_q + {29'd0, addr_byte_offset};
  assign segment_data_bytes = (burst_bytes[SEG_BYTES_WIDTH-1:0] > {13'd0, addr_byte_offset_q}) ?
                              (burst_bytes[SEG_BYTES_WIDTH-1:0] - {13'd0, addr_byte_offset_q}) :
                              '0;
  assign cross_4kb_o = 1'b0;
  assign m_axi_awaddr = m_axi_awaddr_q;
  assign m_axi_awid = m_axi_awid_q;
  assign m_axi_awlen = m_axi_awlen_q;
  assign m_axi_awsize = m_axi_awsize_q;
  assign m_axi_awburst = m_axi_awburst_q;
  assign m_axi_awvalid = m_axi_awvalid_q;
  assign m_axi_wdata = wdata_q;
  assign m_axi_wstrb = wstrb_q;
  assign m_axi_wlast = beat_last_q;
  assign m_axi_wvalid = (state_q == S_W);
  assign m_axi_bready = (state_q == S_B);
  assign spad_req_o = (state_q == S_READ_REQ) && slot_valid_q;
  assign spad_we_o = 1'b0;
  assign spad_addr_o = spad_addr_q;
  assign busy_o = (state_q != S_IDLE) && (state_q != S_DONE);
  assign done_o = (state_q == S_DONE);

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      S_IDLE: if (start_i) state_d = S_START;
      S_START: state_d = S_SPLIT;
      S_SPLIT: state_d = S_PLAN;
      S_PLAN: begin
        if (plan_ready_q) state_d = splitter_valid_q ? S_AW : S_DONE;
      end
      S_AW:   if (m_axi_awvalid_q && m_axi_awready) state_d = S_READ_REQ;
      S_READ_REQ: if (!slot_valid_q || spad_ready_i) state_d = S_READ_DATA;
      S_READ_DATA: state_d = (word_count_q == LAST_WORD) ? S_W : S_READ_REQ;
      S_W:    if (m_axi_wvalid && m_axi_wready) begin
                state_d = beat_last_q ? S_B : S_READ_REQ;
              end
      S_B:    if (m_axi_bvalid && m_axi_bready) state_d = S_B_RESP;
      S_B_RESP: begin
        if (bresp_error_q) state_d = S_DONE;
        else if (segment_continue_q) state_d = S_SPLIT;
        else state_d = S_DONE;
      end
      S_DONE: state_d = S_IDLE;
      default: state_d = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      error_o <= 1'b0;
      addr_q <= '0;
      bytes_remaining_q <= '0;
      spad_offset_q <= '0;
      burst_len_q <= '0;
      splitter_addr_q <= '0;
      splitter_bytes_q <= '0;
      splitter_burst_len_q <= '0;
      burst_beats_q <= '0;
      burst_bytes_q <= '0;
      splitter_valid_q <= 1'b0;
      splitter_cross_4kb_q <= 1'b0;
      plan_ready_q <= 1'b0;
      segment_continue_q <= 1'b0;
      addr_byte_offset_q <= '0;
      segment_data_bytes_q <= '0;
      word_aligned_xfer_q <= 1'b0;
      beat_count_q <= '0;
      word_count_q <= '0;
      wdata_q <= '0;
      wstrb_q <= '0;
      beat_last_q <= 1'b0;
      bresp_error_q <= 1'b0;
      slot_valid_q <= 1'b0;
      spad_addr_q <= '0;
      m_axi_awaddr_q <= '0;
      m_axi_awid_q <= 1'b0;
      m_axi_awlen_q <= '0;
      m_axi_awsize_q <= AXI_SIZE;
      m_axi_awburst_q <= 2'b01;
      m_axi_awvalid_q <= 1'b0;
    end else begin
      state_q <= state_d;
      if (state_q == S_START) begin
        error_o <= 1'b0;
        addr_q <= addr_i;
        bytes_remaining_q <= byte_len_i;
        spad_offset_q <= spad_offset_i;
        burst_len_q <= burst_len_i;
        word_aligned_xfer_q <= (addr_i[1:0] == 2'b00) && (byte_len_i[1:0] == 2'b00);
        plan_ready_q <= 1'b0;
        beat_count_q <= '0;
        word_count_q <= '0;
        wdata_q <= '0;
        wstrb_q <= '0;
        beat_last_q <= 1'b0;
        slot_valid_q <= 1'b0;
        spad_addr_q <= spad_offset_i;
        m_axi_awvalid_q <= 1'b0;
      end
      if (state_q == S_SPLIT) begin
        splitter_addr_q <= aligned_addr;
        splitter_bytes_q <= transfer_bytes;
        splitter_burst_len_q <= burst_len_q;
        addr_byte_offset_q <= addr_byte_offset;
        plan_ready_q <= 1'b0;
      end
      if (state_q == S_PLAN && !plan_ready_q) begin
        burst_beats_q <= burst_beats;
        burst_bytes_q <= burst_bytes[SEG_BYTES_WIDTH-1:0];
        splitter_valid_q <= splitter_valid && word_aligned_xfer_q;
        splitter_cross_4kb_q <= splitter_cross_4kb;
        segment_data_bytes_q <= segment_data_bytes;
        segment_continue_q <= bytes_remaining_q > {16'd0, segment_data_bytes};
        plan_ready_q <= 1'b1;
      end
      if (state_q == S_PLAN && plan_ready_q) begin
        if (splitter_valid_q) begin
          m_axi_awaddr_q <= splitter_addr_q;
          m_axi_awid_q <= 1'b0;
          m_axi_awlen_q <= burst_beats_q - 8'd1;
          m_axi_awsize_q <= AXI_SIZE;
          m_axi_awburst_q <= 2'b01;
          m_axi_awvalid_q <= 1'b1;
          beat_count_q <= '0;
          word_count_q <= '0;
          wdata_q <= '0;
          wstrb_q <= '0;
          beat_last_q <= (burst_beats_q == 8'd1);
          slot_valid_q <= slot_valid_for('0, '0);
          spad_addr_q <= spad_addr_for('0, '0);
        end else begin
          error_o <= 1'b1;
        end
        plan_ready_q <= 1'b0;
      end
      if (m_axi_awvalid_q && m_axi_awready) begin
        m_axi_awvalid_q <= 1'b0;
      end
      if (m_axi_bvalid && m_axi_bready) begin
        bresp_error_q <= m_axi_bresp[1];
      end
      if (state_q == S_B_RESP && !bresp_error_q && segment_continue_q) begin
        addr_q <= addr_q + AXI_ADDR_WIDTH'(segment_data_bytes_q);
        bytes_remaining_q <= bytes_remaining_q - {16'd0, segment_data_bytes_q};
        spad_offset_q <= spad_offset_q + SPAD_ADDR_WIDTH'(segment_data_bytes_q);
        plan_ready_q <= 1'b0;
        beat_count_q <= '0;
        word_count_q <= '0;
        wdata_q <= '0;
        wstrb_q <= '0;
        beat_last_q <= 1'b0;
        slot_valid_q <= 1'b0;
      end
      if (state_q == S_READ_DATA) begin
        if (slot_valid_q) begin
          wdata_q[word_count_q*SPAD_DATA_WIDTH +: SPAD_DATA_WIDTH] <= spad_rdata_i;
        end else begin
          wdata_q[word_count_q*SPAD_DATA_WIDTH +: SPAD_DATA_WIDTH] <= '0;
        end
        if (word_count_q == LAST_WORD) begin
          word_count_q <= '0;
          wstrb_q <= wstrb_for(beat_count_q);
        end else begin
          word_count_q <= word_count_q + 1'b1;
          slot_valid_q <= slot_valid_for(beat_count_q, word_count_q + 1'b1);
          spad_addr_q <= spad_addr_for(beat_count_q, word_count_q + 1'b1);
        end
      end
      if (m_axi_wvalid && m_axi_wready) begin
        beat_count_q <= beat_count_q + 1'b1;
        beat_last_q <= (8'(beat_count_q) + 8'd1) == (burst_beats_q - 8'd1);
        word_count_q <= '0;
        slot_valid_q <= slot_valid_for(beat_count_q + 1'b1, '0);
        spad_addr_q <= spad_addr_for(beat_count_q + 1'b1, '0);
      end
      if (state_q == S_B_RESP && bresp_error_q) begin
        error_o <= 1'b1;
      end
    end
  end
endmodule
