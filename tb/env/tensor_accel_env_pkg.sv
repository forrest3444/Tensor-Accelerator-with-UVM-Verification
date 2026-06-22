package tensor_accel_env_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import svt_uvm_pkg::*;
  import svt_axi_uvm_pkg::*;
  import tensor_pkg::*;
  import tensor_accel_tb_cfg_pkg::*;
  import tensor_accel_reg_pkg::*;

  `include "tensor_accel_matrix_item.sv"
  `include "tensor_accel_ref_model.sv"
  `include "tensor_accel_subscriber.sv"
  `include "tensor_accel_scoreboard.sv"
  `include "tensor_accel_coverage.sv"
  `include "tensor_perf_monitor.sv"
  `include "tensor_accel_env.sv"
endpackage
