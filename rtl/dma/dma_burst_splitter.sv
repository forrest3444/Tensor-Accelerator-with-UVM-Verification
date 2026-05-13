`timescale 1ns/1ps

module dma_burst_splitter #(
  parameter int AXI_DATA_WIDTH = 64,
  parameter int MAX_BURST_BEATS = 16,
  parameter bit AUTO_SPLIT_4KB = 1'b0
) (
  input  logic [31:0] addr_i,
  input  logic [31:0] bytes_i,
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

  always_comb begin
    bytes_to_4kb = 32'd4096 - {20'd0, addr_i[11:0]};
    max_burst_bytes = MAX_BURST_BEATS * BEAT_BYTES;
    crosses_4kb_o = bytes_i > bytes_to_4kb;
    legal_bytes = bytes_i;
    if (legal_bytes > max_burst_bytes) legal_bytes = max_burst_bytes;
    if (AUTO_SPLIT_4KB && legal_bytes > bytes_to_4kb) legal_bytes = bytes_to_4kb;
    aligned_bytes = legal_bytes - (legal_bytes % BEAT_BYTES);
    if (aligned_bytes == 0 && legal_bytes != 0) aligned_bytes = BEAT_BYTES;

    valid_o = (bytes_i != 0) &&
              ((addr_i % BEAT_BYTES) == 0) &&
              (AUTO_SPLIT_4KB || !crosses_4kb_o);
    burst_beats_32 = aligned_bytes / BEAT_BYTES;
    burst_bytes_o = aligned_bytes;
    burst_beats_o = burst_beats_32[7:0];
  end
endmodule
