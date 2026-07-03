`ifndef TENSOR_ACCEL_DIRECTED_TESTS_SVH
`define TENSOR_ACCEL_DIRECTED_TESTS_SVH

`include "directed_tests/tensor_base_reg_rw_test.sv"
`include "directed_tests/tensor_base_int4_4x4_test.sv"
`include "directed_tests/tensor_base_int8_4x4_test.sv"
`include "directed_tests/tensor_base_int16_4x4_test.sv"
`include "directed_tests/tensor_base_int16_max_stress_test.sv"
`include "directed_tests/tensor_base_burst_len_test.sv"
`include "directed_tests/tensor_base_axi_ready_delay_test.sv"
`include "directed_tests/tensor_base_back_to_back_test.sv"
`include "directed_tests/tensor_base_bb_precision_switch_test.sv"
`include "directed_tests/tensor_base_write_unaligned_test.sv"
`include "directed_tests/tensor_base_irq_test.sv"
`include "directed_tests/tensor_base_ro_reg_protection_test.sv"
`include "directed_tests/tensor_base_square_tile_tests.sv"
`include "directed_tests/tensor_base_rect_matrix_test.sv"
`include "directed_tests/tensor_base_non_aligned_size_test.sv"
`include "directed_tests/tensor_base_degenerate_dims_test.sv"
`include "directed_tests/tensor_base_bias_test.sv"
`include "directed_tests/tensor_base_relu_test.sv"
`include "directed_tests/tensor_base_bias_relu_order_test.sv"
`include "directed_tests/tensor_base_saturation_test.sv"
`include "directed_tests/tensor_base_overflow_status_test.sv"
`include "directed_tests/tensor_base_partial_k_postop_isolation_test.sv"

`endif
