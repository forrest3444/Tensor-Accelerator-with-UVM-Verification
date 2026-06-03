`ifndef TENSOR_ACCEL_DIRECTED_SEQ_LIB_SVH
`define TENSOR_ACCEL_DIRECTED_SEQ_LIB_SVH

`include "directed_tests/tensor_axi_ready_delay_seq.sv"
`include "directed_tests/tensor_matmul_vseq.sv"
`include "directed_tests/tensor_irq_vseq.sv"
`include "directed_tests/tensor_back_to_back_vseq.sv"
`include "directed_tests/tensor_bb_precision_switch_vseq.sv"
`include "directed_tests/tensor_ro_reg_protection_vseq.sv"
`include "directed_tests/tensor_write_unaligned_vseq.sv"
`include "directed_tests/tensor_bias_vseq.sv"
`include "directed_tests/tensor_int16_max_stress_vseq.sv"
`include "directed_tests/tensor_relu_vseq.sv"
`include "directed_tests/tensor_saturation_vseq.sv"
`include "directed_tests/tensor_non_aligned_vseq.sv"
`include "directed_tests/tensor_degenerate_dims_vseq.sv"

`endif
