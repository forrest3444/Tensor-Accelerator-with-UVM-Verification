`timescale 1ns/1ps

package tensor_accel_seq_lib_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import svt_uvm_pkg::*;
  import svt_axi_uvm_pkg::*;
  import tensor_pkg::*;
  import tensor_accel_tb_cfg_pkg::*;

  `include "base_vseq.sv"
  `include "tensor_common_vseqs.sv"
endpackage
