`ifndef TENSOR_ACCEL_EXCEPTION_TESTS_SVH
`define TENSOR_ACCEL_EXCEPTION_TESTS_SVH

`include "exception_tests/tensor_err_illegal_matrix_size_test.sv"
`include "exception_tests/tensor_err_illegal_precision_test.sv"
`include "exception_tests/tensor_err_unaligned_base_test.sv"
`include "exception_tests/tensor_err_clear_error_recovery_test.sv"
`include "exception_tests/tensor_err_axi_read_slverr_test.sv"
`include "exception_tests/tensor_err_axi_read_bias_error_test.sv"
`include "exception_tests/tensor_err_axi_write_slverr_test.sv"
`include "exception_tests/tensor_err_axi_write_mid_row_error_test.sv"
`include "exception_tests/tensor_err_command_fsm_error_arc_test.sv"
`include "exception_tests/tensor_err_command_while_busy_test.sv"
`include "exception_tests/tensor_err_start_while_done_test.sv"
`include "exception_tests/tensor_err_burst_len_zero_test.sv"
`include "exception_tests/tensor_err_burst_len_exceed_test.sv"
`include "exception_tests/tensor_err_internal_timeout_test.sv"
`include "exception_tests/tensor_reset_during_load_test.sv"
`include "exception_tests/tensor_reset_during_compute_test.sv"
`include "exception_tests/tensor_reset_during_store_test.sv"
`include "exception_tests/tensor_soft_reset_test.sv"
`include "exception_tests/tensor_soft_reset_during_idle_test.sv"
`include "exception_tests/tensor_err_irq_on_error_test.sv"

`endif
