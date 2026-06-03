module axi_lite_slave #(
  parameter int ADDR_WIDTH = 16,
  parameter int DATA_WIDTH = 32
) (
  input  logic clk,
  input  logic rst_n,
  input  logic [ADDR_WIDTH-1:0] s_axil_awaddr,
  input  logic s_axil_awvalid,
  output logic s_axil_awready,
  input  logic [DATA_WIDTH-1:0] s_axil_wdata,
  input  logic [DATA_WIDTH/8-1:0] s_axil_wstrb,
  input  logic s_axil_wvalid,
  output logic s_axil_wready,
  output logic [1:0] s_axil_bresp,
  output logic s_axil_bvalid,
  input  logic s_axil_bready,
  input  logic [ADDR_WIDTH-1:0] s_axil_araddr,
  input  logic s_axil_arvalid,
  output logic s_axil_arready,
  output logic [DATA_WIDTH-1:0] s_axil_rdata,
  output logic [1:0] s_axil_rresp,
  output logic s_axil_rvalid,
  input  logic s_axil_rready,

  output logic reg_wr_en_o,
  output logic [ADDR_WIDTH-1:0] reg_wr_addr_o,
  output logic [DATA_WIDTH-1:0] reg_wr_data_o,
  output logic [DATA_WIDTH/8-1:0] reg_wr_strb_o,
  output logic reg_rd_en_o,
  output logic [ADDR_WIDTH-1:0] reg_rd_addr_o,
  input  logic [DATA_WIDTH-1:0] reg_rd_data_i
);
  logic [ADDR_WIDTH-1:0] awaddr_q;
  logic aw_seen_q;
  logic [1:0] rd_pending_q;

  assign s_axil_bresp = 2'b00;
  assign s_axil_rresp = 2'b00;
  assign s_axil_awready = !aw_seen_q;
  assign s_axil_wready = aw_seen_q && !s_axil_bvalid;
  assign s_axil_arready = !s_axil_rvalid && (rd_pending_q == 2'd0);
  assign reg_wr_en_o = s_axil_wvalid && s_axil_wready;
  assign reg_wr_addr_o = awaddr_q;
  assign reg_wr_data_o = s_axil_wdata;
  assign reg_wr_strb_o = s_axil_wstrb;
  assign reg_rd_en_o = s_axil_arvalid && s_axil_arready;
  assign reg_rd_addr_o = s_axil_araddr;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      awaddr_q <= '0;
      aw_seen_q <= 1'b0;
      rd_pending_q <= 2'd0;
      s_axil_bvalid <= 1'b0;
      s_axil_rvalid <= 1'b0;
      s_axil_rdata <= '0;
    end else begin
      if (s_axil_awvalid && s_axil_awready) begin
        awaddr_q <= s_axil_awaddr;
        aw_seen_q <= 1'b1;
      end
      if (reg_wr_en_o) begin
        s_axil_bvalid <= 1'b1;
        aw_seen_q <= 1'b0;
      end else if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end
      if (reg_rd_en_o) begin
        rd_pending_q <= 2'd2;
      end else if (rd_pending_q > 2'd1) begin
        rd_pending_q <= rd_pending_q - 2'd1;
      end else if (rd_pending_q == 2'd1) begin
        rd_pending_q <= 2'd0;
        s_axil_rvalid <= 1'b1;
        s_axil_rdata <= reg_rd_data_i;
      end else if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid <= 1'b0;
      end
    end
  end
endmodule
