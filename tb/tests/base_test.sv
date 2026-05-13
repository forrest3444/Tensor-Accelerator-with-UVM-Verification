`ifndef TENSOR_ACCEL_BASE_TEST_SV
`define TENSOR_ACCEL_BASE_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import svt_axi_uvm_pkg::*;
import tensor_accel_tb_cfg_pkg::*;
import tensor_accel_env_pkg::*;
import tensor_accel_seq_lib_pkg::*;

class base_test extends uvm_test;
  `uvm_component_utils(base_test)

  tensor_accel_env env;
  tensor_accel_env_cfg cfg;

  function new(string name = "base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(tensor_accel_env_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = tensor_accel_env_cfg::type_id::create("cfg");
    end

    void'(uvm_config_db #(virtual tensor_accel_dut_if)::get(this, "", "dut_vif", cfg.vif));
    void'(uvm_config_db #(virtual svt_axi_master_if)::get(this, "", "axil_master_vif",
                                                          cfg.axil_master_vif));
    void'(uvm_config_db #(virtual svt_axi_slave_if)::get(this, "", "axi_slave_vif",
                                                         cfg.axi_slave_vif));

    uvm_config_db #(tensor_accel_env_cfg)::set(this, "env", "cfg", cfg);
    env = tensor_accel_env::type_id::create("env", this);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  virtual function void final_phase(uvm_phase phase);
    uvm_report_server svr;
    super.final_phase(phase);
    svr = uvm_report_server::get_server();

    if ((svr.get_severity_count(UVM_FATAL) +
         svr.get_severity_count(UVM_ERROR)) == 0) begin
      `uvm_info("TEST_RESULT", "base_test PASSED", UVM_LOW)
    end
    else begin
      `uvm_info("TEST_RESULT", "base_test FAILED", UVM_LOW)
    end
  endfunction
endclass

`endif
