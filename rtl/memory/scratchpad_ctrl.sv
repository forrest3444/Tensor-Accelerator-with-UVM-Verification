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

  output logic                  spad_req_o,
  output logic                  spad_we_o,
  output logic [ADDR_WIDTH-1:0] spad_addr_o,
  output logic [DATA_WIDTH-1:0] spad_wdata_o,
  output logic [DATA_WIDTH/8-1:0] spad_wstrb_o,
  input  logic [DATA_WIDTH-1:0] spad_rdata_i,
  input  logic                  spad_ready_i
);
  assign spad_req_o = dma_req_i;
  assign spad_we_o = dma_we_i;
  assign spad_addr_o = dma_addr_i;
  assign spad_wdata_o = dma_wdata_i;
  assign spad_wstrb_o = dma_wstrb_i;

  assign dma_rdata_o = spad_rdata_i;
  assign dma_ready_o = spad_ready_i && dma_req_i;
endmodule
