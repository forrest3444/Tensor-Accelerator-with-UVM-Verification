module dma_burst_splitter #(
  parameter int AXI_DATA_WIDTH = 64,
  parameter int MAX_BURST_BEATS = 16,
  parameter bit AUTO_SPLIT_4KB = 1'b0
) (
  input  logic [31:0] addr_i,
  input  logic [31:0] bytes_i,
  input  logic [7:0]  burst_len_i,
  output logic [7:0]  burst_beats_o,
  output logic [31:0] burst_bytes_o,
  output logic        crosses_4kb_o,
  output logic        valid_o
);
  localparam int BEAT_BYTES = AXI_DATA_WIDTH / 8;
  logic [31:0] bytes_to_4kb;
  logic [31:0] max_burst_bytes;
  logic [31:0] legal_bytes;
  logic [31:0] aligned_bytes;
  logic [31:0] burst_beats_32;
  logic [31:0] requested_burst_beats;
  logic [31:0] effective_burst_beats;
  logic [31:0] max_burst_beats;

  always_comb begin
    bytes_to_4kb = 32'd4096 - {20'd0, addr_i[11:0]};
    max_burst_beats = (MAX_BURST_BEATS > 256) ? 32'd256 : 32'(MAX_BURST_BEATS);
    requested_burst_beats = {24'd0, burst_len_i};
    if ((MAX_BURST_BEATS >= 256) && (burst_len_i == 8'hff)) begin
      requested_burst_beats = 32'd256;
    end
    effective_burst_beats = requested_burst_beats;
    if (effective_burst_beats > max_burst_beats) begin
      effective_burst_beats = max_burst_beats;
    end
    max_burst_bytes = effective_burst_beats * BEAT_BYTES;
    crosses_4kb_o = bytes_i > bytes_to_4kb;
    legal_bytes = bytes_i;
    if (legal_bytes > max_burst_bytes) legal_bytes = max_burst_bytes;
    if (AUTO_SPLIT_4KB && legal_bytes > bytes_to_4kb) legal_bytes = bytes_to_4kb;
    aligned_bytes = legal_bytes;

    valid_o = (bytes_i != 0) &&
              (effective_burst_beats != 32'd0) &&
              ((addr_i % BEAT_BYTES) == 0) &&
              (AUTO_SPLIT_4KB || !crosses_4kb_o);
    burst_beats_32 = (aligned_bytes + BEAT_BYTES - 1) / BEAT_BYTES;
    burst_bytes_o = aligned_bytes;
    burst_beats_o = (burst_beats_32 == 32'd256) ? 8'd0 : burst_beats_32[7:0];
  end
endmodule
