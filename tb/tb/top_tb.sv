module top_tb;
  import tensor_accel_uvm_pkg::*;

  logic clk;
  tensor_accel_dut_if dut_if(clk);
  svt_axi_if axi_if();
  logic [1:0] dut_s_axil_bresp;
  logic [1:0] dut_s_axil_rresp;
  logic [7:0] dut_m_axi_arlen;
  logic [7:0] dut_m_axi_awlen;
  localparam int AXIL_DATA_IF_WIDTH = $bits(axi_if.master_if[0].rdata);
  localparam int AXI_ADDR_IF_WIDTH  = $bits(axi_if.slave_if[0].araddr);
  localparam int AXI_DATA_IF_WIDTH  = $bits(axi_if.slave_if[0].wdata);
  localparam int AXI_STRB_IF_WIDTH  = $bits(axi_if.slave_if[0].wstrb);
  localparam int AXI_ID_IF_WIDTH    = $bits(axi_if.slave_if[0].arid);

  assign axi_if.common_aclk = clk;
  assign axi_if.master_if[0].aresetn = dut_if.rst_n;
  assign axi_if.slave_if[0].aresetn = dut_if.rst_n;
  assign axi_if.master_if[0].bresp = {2'b00, dut_s_axil_bresp};
  assign axi_if.master_if[0].rresp = {2'b00, dut_s_axil_rresp};
  assign axi_if.slave_if[0].arlen = {2'b00, dut_m_axi_arlen};
  assign axi_if.slave_if[0].awlen = {2'b00, dut_m_axi_awlen};
  assign axi_if.slave_if[0].arlock = '0;
  assign axi_if.slave_if[0].arcache = '0;
  assign axi_if.slave_if[0].arprot = '0;
  assign axi_if.slave_if[0].arqos = '0;
  assign axi_if.slave_if[0].arregion = '0;
  assign axi_if.slave_if[0].aruser = '0;
  assign axi_if.slave_if[0].awlock = '0;
  assign axi_if.slave_if[0].awcache = '0;
  assign axi_if.slave_if[0].awprot = '0;
  assign axi_if.slave_if[0].awqos = '0;
  assign axi_if.slave_if[0].awregion = '0;
  assign axi_if.slave_if[0].awuser = '0;
  assign axi_if.slave_if[0].wuser = '0;

  if (AXIL_DATA_IF_WIDTH > 32) begin : gen_axil_tieoffs
    assign axi_if.master_if[0].rdata[AXIL_DATA_IF_WIDTH-1:32] = '0;
  end

  if (AXI_ADDR_IF_WIDTH > 32) begin : gen_axi_addr_tieoffs
    assign axi_if.slave_if[0].araddr[AXI_ADDR_IF_WIDTH-1:32] = '0;
    assign axi_if.slave_if[0].awaddr[AXI_ADDR_IF_WIDTH-1:32] = '0;
  end

  if (AXI_DATA_IF_WIDTH > 64) begin : gen_axi_data_tieoffs
    assign axi_if.slave_if[0].wdata[AXI_DATA_IF_WIDTH-1:64] = '0;
  end

  if (AXI_STRB_IF_WIDTH > 8) begin : gen_axi_strb_tieoffs
    assign axi_if.slave_if[0].wstrb[AXI_STRB_IF_WIDTH-1:8] = '0;
  end

  if (AXI_ID_IF_WIDTH > 1) begin : gen_axi_id_tieoffs
    assign axi_if.slave_if[0].arid[AXI_ID_IF_WIDTH-1:1] = '0;
    assign axi_if.slave_if[0].awid[AXI_ID_IF_WIDTH-1:1] = '0;
  end

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    dut_if.rst_n = 1'b0;
    repeat (8) @(posedge clk);
    dut_if.rst_n = 1'b1;
  end

  tensor_accel_top u_dut (
    .clk(clk),
    .rst_n(dut_if.rst_n),

    .s_axil_awaddr(axi_if.master_if[0].awaddr[15:0]),
    .s_axil_awvalid(axi_if.master_if[0].awvalid),
    .s_axil_awready(axi_if.master_if[0].awready),

    .s_axil_wdata(axi_if.master_if[0].wdata[31:0]),
    .s_axil_wstrb(axi_if.master_if[0].wstrb[3:0]),
    .s_axil_wvalid(axi_if.master_if[0].wvalid),
    .s_axil_wready(axi_if.master_if[0].wready),

    .s_axil_bresp(dut_s_axil_bresp),
    .s_axil_bvalid(axi_if.master_if[0].bvalid),
    .s_axil_bready(axi_if.master_if[0].bready),

    .s_axil_araddr(axi_if.master_if[0].araddr[15:0]),
    .s_axil_arvalid(axi_if.master_if[0].arvalid),
    .s_axil_arready(axi_if.master_if[0].arready),

    .s_axil_rdata(axi_if.master_if[0].rdata[31:0]),
    .s_axil_rresp(dut_s_axil_rresp),
    .s_axil_rvalid(axi_if.master_if[0].rvalid),
    .s_axil_rready(axi_if.master_if[0].rready),

    .m_axi_araddr(axi_if.slave_if[0].araddr[31:0]),
    .m_axi_arid(axi_if.slave_if[0].arid[0]),
    .m_axi_arlen(dut_m_axi_arlen),
    .m_axi_arsize(axi_if.slave_if[0].arsize),
    .m_axi_arburst(axi_if.slave_if[0].arburst),
    .m_axi_arvalid(axi_if.slave_if[0].arvalid),
    .m_axi_arready(axi_if.slave_if[0].arready),

    .m_axi_rdata(axi_if.slave_if[0].rdata[63:0]),
    .m_axi_rid(axi_if.slave_if[0].rid[0]),
    .m_axi_rresp(axi_if.slave_if[0].rresp[1:0]),
    .m_axi_rlast(axi_if.slave_if[0].rlast),
    .m_axi_rvalid(axi_if.slave_if[0].rvalid),
    .m_axi_rready(axi_if.slave_if[0].rready),

    .m_axi_awaddr(axi_if.slave_if[0].awaddr[31:0]),
    .m_axi_awid(axi_if.slave_if[0].awid[0]),
    .m_axi_awlen(dut_m_axi_awlen),
    .m_axi_awsize(axi_if.slave_if[0].awsize),
    .m_axi_awburst(axi_if.slave_if[0].awburst),
    .m_axi_awvalid(axi_if.slave_if[0].awvalid),
    .m_axi_awready(axi_if.slave_if[0].awready),

    .m_axi_wdata(axi_if.slave_if[0].wdata[63:0]),
    .m_axi_wstrb(axi_if.slave_if[0].wstrb[7:0]),
    .m_axi_wlast(axi_if.slave_if[0].wlast),
    .m_axi_wvalid(axi_if.slave_if[0].wvalid),
    .m_axi_wready(axi_if.slave_if[0].wready),

    .m_axi_bresp(axi_if.slave_if[0].bresp[1:0]),
    .m_axi_bid(axi_if.slave_if[0].bid[0]),
    .m_axi_bvalid(axi_if.slave_if[0].bvalid),
    .m_axi_bready(axi_if.slave_if[0].bready),
    .irq(dut_if.irq)
  );

  initial begin
    run_tensor_accel_uvm_test(dut_if, axi_if.master_if[0], axi_if.slave_if[0], axi_if);
  end
endmodule
