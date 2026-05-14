module scratchpad #(
  parameter int ADDR_WIDTH = 16,
  parameter int DATA_WIDTH = 32,
  parameter int DEPTH_WORDS = 16384
) (
  input  logic                  clk,
  input  logic                  req_i,
  input  logic                  we_i,
  input  logic [ADDR_WIDTH-1:0] addr_i,
  input  logic [DATA_WIDTH-1:0] wdata_i,
  input  logic [DATA_WIDTH/8-1:0] wstrb_i,
  output logic [DATA_WIDTH-1:0] rdata_o,
  output logic                  ready_o
);
  localparam int WORD_ADDR_WIDTH = (DEPTH_WORDS <= 2) ? 1 : $clog2(DEPTH_WORDS);
  logic [DATA_WIDTH-1:0] mem [DEPTH_WORDS];
  logic [WORD_ADDR_WIDTH-1:0] word_addr;

  assign word_addr = addr_i[WORD_ADDR_WIDTH+1:2];
  assign ready_o = req_i;

  always_ff @(posedge clk) begin
    if (req_i) begin
      if (we_i) begin
        for (int b = 0; b < DATA_WIDTH/8; b++) begin
          if (wstrb_i[b]) begin
            mem[word_addr][8*b +: 8] <= wdata_i[8*b +: 8];
          end
        end
      end
      rdata_o <= mem[word_addr];
    end
  end
endmodule
