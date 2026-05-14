package tensor_accel_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import svt_uvm_pkg::*;
  import svt_axi_uvm_pkg::*;
  import tensor_pkg::*;
  import tensor_accel_tb_cfg_pkg::*;
  import tensor_accel_reg_pkg::*;
  import tensor_accel_env_pkg::*;

  `include "tensor_accel_seq_lib.svh"
  `include "tensor_accel_tests.svh"

  task automatic run_tensor_accel_uvm_test(
      virtual tensor_accel_dut_if dut_vif,
      virtual svt_axi_master_if axil_master_vif,
      virtual svt_axi_slave_if axi_slave_vif,
      svt_axi_vif axi_vif
  );
    tensor_accel_env_cfg env_cfg;

    env_cfg = tensor_accel_env_cfg::type_id::create("env_cfg");
    env_cfg.vif = dut_vif;
    env_cfg.axil_master_vif = axil_master_vif;
    env_cfg.axi_slave_vif = axi_slave_vif;

    uvm_config_db #(tensor_accel_env_cfg)::set(null, "uvm_test_top.env", "cfg", env_cfg);
    uvm_config_db #(tensor_accel_env_cfg)::set(null, "uvm_test_top", "cfg", env_cfg);
    uvm_config_db #(virtual tensor_accel_dut_if)::set(null, "*", "dut_vif", dut_vif);
    uvm_config_db #(virtual svt_axi_master_if)::set(null, "*", "axil_master_vif",
                                                    axil_master_vif);
    uvm_config_db #(virtual svt_axi_slave_if)::set(null, "*", "axi_slave_vif",
                                                   axi_slave_vif);
    uvm_config_db #(svt_axi_vif)::set(uvm_root::get(), "uvm_test_top.env.axi_system_env",
                                      "vif", axi_vif);
    run_test();
  endtask
endpackage
