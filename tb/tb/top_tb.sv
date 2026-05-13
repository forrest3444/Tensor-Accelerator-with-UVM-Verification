`timescale 1ns/1ps

module top_tb;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import svt_uvm_pkg::*;
  import svt_axi_uvm_pkg::*;
  import tensor_pkg::*;
  import tensor_accel_tb_cfg_pkg::*;
  import tensor_accel_env_pkg::*;
  import tensor_accel_seq_lib_pkg::*;

  `include "tb/tests/base_test.sv"

  logic clk;
  tensor_accel_dut_if dut_if(clk);
  svt_axi_if axi_if();

  assign axi_if.common_aclk = clk;
  assign axi_if.master_if[0].aresetn = dut_if.rst_n;
  assign axi_if.slave_if[0].aresetn = dut_if.rst_n;

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

    .s_axil_bresp(axi_if.master_if[0].bresp),
    .s_axil_bvalid(axi_if.master_if[0].bvalid),
    .s_axil_bready(axi_if.master_if[0].bready),

    .s_axil_araddr(axi_if.master_if[0].araddr[15:0]),
    .s_axil_arvalid(axi_if.master_if[0].arvalid),
    .s_axil_arready(axi_if.master_if[0].arready),

    .s_axil_rdata(axi_if.master_if[0].rdata[31:0]),
    .s_axil_rresp(axi_if.master_if[0].rresp),
    .s_axil_rvalid(axi_if.master_if[0].rvalid),
    .s_axil_rready(axi_if.master_if[0].rready),

    .m_axi_araddr(axi_if.slave_if[0].araddr[31:0]),
    .m_axi_arlen(axi_if.slave_if[0].arlen),
    .m_axi_arsize(axi_if.slave_if[0].arsize),
    .m_axi_arburst(axi_if.slave_if[0].arburst),
    .m_axi_arvalid(axi_if.slave_if[0].arvalid),
    .m_axi_arready(axi_if.slave_if[0].arready),

    .m_axi_rdata(axi_if.slave_if[0].rdata[63:0]),
    .m_axi_rresp(axi_if.slave_if[0].rresp),
    .m_axi_rlast(axi_if.slave_if[0].rlast),
    .m_axi_rvalid(axi_if.slave_if[0].rvalid),
    .m_axi_rready(axi_if.slave_if[0].rready),

    .m_axi_awaddr(axi_if.slave_if[0].awaddr[31:0]),
    .m_axi_awlen(axi_if.slave_if[0].awlen),
    .m_axi_awsize(axi_if.slave_if[0].awsize),
    .m_axi_awburst(axi_if.slave_if[0].awburst),
    .m_axi_awvalid(axi_if.slave_if[0].awvalid),
    .m_axi_awready(axi_if.slave_if[0].awready),

    .m_axi_wdata(axi_if.slave_if[0].wdata[63:0]),
    .m_axi_wstrb(axi_if.slave_if[0].wstrb[7:0]),
    .m_axi_wlast(axi_if.slave_if[0].wlast),
    .m_axi_wvalid(axi_if.slave_if[0].wvalid),
    .m_axi_wready(axi_if.slave_if[0].wready),

    .m_axi_bresp(axi_if.slave_if[0].bresp),
    .m_axi_bvalid(axi_if.slave_if[0].bvalid),
    .m_axi_bready(axi_if.slave_if[0].bready),
    .irq(dut_if.irq)
  );

  initial begin
    tensor_accel_env_cfg env_cfg;
    env_cfg = tensor_accel_env_cfg::type_id::create("env_cfg");
    env_cfg.vif = dut_if;
    env_cfg.axil_master_vif = axi_if.master_if[0];
    env_cfg.axi_slave_vif = axi_if.slave_if[0];

    uvm_config_db #(tensor_accel_env_cfg)::set(null, "uvm_test_top.env", "cfg", env_cfg);
    uvm_config_db #(tensor_accel_env_cfg)::set(null, "uvm_test_top", "cfg", env_cfg);
    uvm_config_db #(virtual tensor_accel_dut_if)::set(null, "*", "dut_vif", dut_if);
    uvm_config_db #(virtual svt_axi_master_if)::set(null, "*", "axil_master_vif",
                                                    axi_if.master_if[0]);
    uvm_config_db #(virtual svt_axi_slave_if)::set(null, "*", "axi_slave_vif",
                                                   axi_if.slave_if[0]);
    uvm_config_db #(svt_axi_vif)::set(uvm_root::get(), "uvm_test_top.env.axi_system_env",
                                      "vif", axi_if);
    run_test("base_test");
  end
endmodule
