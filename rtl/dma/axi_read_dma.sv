module axi_read_dma #(
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

  output logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
  output logic m_axi_arid,
  output logic [7:0] m_axi_arlen,
  output logic [2:0] m_axi_arsize,
  output logic [1:0] m_axi_arburst,
  output logic m_axi_arvalid,
  input  logic m_axi_arready,
  input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
  input  logic m_axi_rid,
  input  logic [1:0] m_axi_rresp,
  input  logic m_axi_rlast,
  input  logic m_axi_rvalid,
  output logic m_axi_rready,

  output logic spad_req_o,
  output logic spad_we_o,
  output logic [SPAD_ADDR_WIDTH-1:0] spad_addr_o,
  output logic [SPAD_DATA_WIDTH-1:0] spad_wdata_o,
  output logic [SPAD_DATA_WIDTH/8-1:0] spad_wstrb_o,
  input  logic spad_ready_i
);
  localparam int AXI_BYTES = AXI_DATA_WIDTH / 8;
  localparam int SPAD_WORDS_PER_BEAT = AXI_DATA_WIDTH / SPAD_DATA_WIDTH;
  localparam logic [2:0] AXI_SIZE = 3'($clog2(AXI_BYTES));
  localparam logic [$clog2(SPAD_WORDS_PER_BEAT)-1:0] LAST_WORD =
      $clog2(SPAD_WORDS_PER_BEAT)'(SPAD_WORDS_PER_BEAT - 1);
  localparam logic [SPAD_ADDR_WIDTH-1:0] SPAD_WORD_BYTES =
      SPAD_ADDR_WIDTH'(SPAD_DATA_WIDTH / 8);

  typedef enum logic [1:0] {S_IDLE, S_AR, S_R, S_DONE} state_e;
  state_e state_q, state_d;
  logic [7:0] burst_beats;
  logic [31:0] burst_bytes;
  logic splitter_valid;
  logic [AXI_ADDR_WIDTH-1:0] dma_addr_q;
  logic [31:0] bytes_remaining_q;
  logic [AXI_ADDR_WIDTH-1:0] split_addr;
  logic [31:0] split_bytes;
  logic [$clog2(SPAD_WORDS_PER_BEAT)-1:0] beat_word_q;
  logic [SPAD_ADDR_WIDTH-1:0] spad_addr_q;
  logic [AXI_DATA_WIDTH-1:0] rdata_q;
  logic write_words_q;
  logic last_read_q;

  dma_burst_splitter #(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .MAX_BURST_BEATS(MAX_BURST_BEATS),
    .AUTO_SPLIT_4KB(1'b0)
  ) u_splitter (
    .addr_i(split_addr),
    .bytes_i(split_bytes),
    .burst_beats_o(burst_beats),
    .burst_bytes_o(burst_bytes),
    .crosses_4kb_o(cross_4kb_o),
    .valid_o(splitter_valid)
  );

  assign split_addr = (state_q == S_IDLE) ? addr_i : dma_addr_q;
  assign split_bytes = (state_q == S_IDLE) ? byte_len_i : bytes_remaining_q;
  assign m_axi_araddr = dma_addr_q;
  assign m_axi_arid = 1'b0;
  assign m_axi_arlen = burst_beats - 8'd1;
  assign m_axi_arsize = AXI_SIZE;
  assign m_axi_arburst = 2'b01;
  assign m_axi_arvalid = (state_q == S_AR);
  assign m_axi_rready = (state_q == S_R) && !write_words_q;

  assign spad_req_o = write_words_q;
  assign spad_we_o = 1'b1;
  assign spad_addr_o = spad_addr_q;
  assign spad_wdata_o = rdata_q[beat_word_q*SPAD_DATA_WIDTH +: SPAD_DATA_WIDTH];
  assign spad_wstrb_o = '1;
  assign busy_o = (state_q != S_IDLE) && (state_q != S_DONE);
  assign done_o = (state_q == S_DONE);

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      S_IDLE: if (start_i && splitter_valid) state_d = S_AR;
      S_AR:   if (m_axi_arvalid && m_axi_arready) state_d = S_R;
      S_R:    if (write_words_q && spad_ready_i && (beat_word_q == LAST_WORD) &&
                  last_read_q) begin
                state_d = (bytes_remaining_q == burst_bytes) ? S_DONE : S_AR;
              end
      S_DONE: state_d = S_IDLE;
      default: state_d = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      error_o <= 1'b0;
      dma_addr_q <= '0;
      bytes_remaining_q <= 32'd0;
      beat_word_q <= '0;
      spad_addr_q <= '0;
      rdata_q <= '0;
      write_words_q <= 1'b0;
      last_read_q <= 1'b0;
    end else begin
      state_q <= state_d;
      if (state_q == S_IDLE && start_i) begin
        error_o <= !splitter_valid;
        dma_addr_q <= addr_i;
        bytes_remaining_q <= byte_len_i;
        spad_addr_q <= spad_offset_i;
        beat_word_q <= '0;
        last_read_q <= 1'b0;
      end
      if (m_axi_rvalid && m_axi_rready) begin
        rdata_q <= m_axi_rdata;
        beat_word_q <= '0;
        write_words_q <= 1'b1;
        last_read_q <= m_axi_rlast;
        if (m_axi_rresp[1]) error_o <= 1'b1;
      end else if (write_words_q && spad_ready_i) begin
        if (beat_word_q == LAST_WORD) begin
          beat_word_q <= '0;
          write_words_q <= 1'b0;
          last_read_q <= 1'b0;
          if (last_read_q) begin
            dma_addr_q <= dma_addr_q + AXI_ADDR_WIDTH'(burst_bytes);
            bytes_remaining_q <= bytes_remaining_q - burst_bytes;
          end
        end else begin
          beat_word_q <= beat_word_q + 1'b1;
        end
        spad_addr_q <= spad_addr_q + SPAD_WORD_BYTES;
      end
    end
  end
endmodule
