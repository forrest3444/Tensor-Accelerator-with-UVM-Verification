module scratchpad_ctrl #(
  parameter int ADDR_WIDTH = 16,
  parameter int DATA_WIDTH = 32
) (
  input  logic                  dma_req_i,
  input  logic                  dma_we_i,
  input  logic [ADDR_WIDTH-1:0] dma_addr_i,
  input  logic [DATA_WIDTH-1:0] dma_wdata_i,
  input  logic [DATA_WIDTH/8-1:0] dma_wstrb_i,
  output logic [DATA_WIDTH-1:0] dma_rdata_o,
  output logic                  dma_ready_o,

  input  logic                  compute_req_i,
  input  logic                  compute_we_i,
  input  logic [ADDR_WIDTH-1:0] compute_addr_i,
  input  logic [DATA_WIDTH-1:0] compute_wdata_i,
  input  logic [DATA_WIDTH/8-1:0] compute_wstrb_i,
  output logic [DATA_WIDTH-1:0] compute_rdata_o,
  output logic                  compute_ready_o,

  output logic                  spad_req_o,
  output logic                  spad_we_o,
  output logic [ADDR_WIDTH-1:0] spad_addr_o,
  output logic [DATA_WIDTH-1:0] spad_wdata_o,
  output logic [DATA_WIDTH/8-1:0] spad_wstrb_o,
  input  logic [DATA_WIDTH-1:0] spad_rdata_i,
  input  logic                  spad_ready_i
);
  logic grant_dma;

  assign grant_dma = dma_req_i || !compute_req_i;
  assign spad_req_o = grant_dma ? dma_req_i : compute_req_i;
  assign spad_we_o = grant_dma ? dma_we_i : compute_we_i;
  assign spad_addr_o = grant_dma ? dma_addr_i : compute_addr_i;
  assign spad_wdata_o = grant_dma ? dma_wdata_i : compute_wdata_i;
  assign spad_wstrb_o = grant_dma ? dma_wstrb_i : compute_wstrb_i;

  assign dma_rdata_o = spad_rdata_i;
  assign compute_rdata_o = spad_rdata_i;
  assign dma_ready_o = spad_ready_i && grant_dma && dma_req_i;
  assign compute_ready_o = spad_ready_i && !grant_dma && compute_req_i;
endmodule
