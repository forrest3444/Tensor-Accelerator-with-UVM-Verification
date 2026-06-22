`ifndef TENSOR_ACCEL_EXCEPTION_SEQ_LIB_SVH
`define TENSOR_ACCEL_EXCEPTION_SEQ_LIB_SVH

`include "exception_tests/tensor_illegal_matrix_size_vseq.sv"
`include "exception_tests/tensor_illegal_precision_vseq.sv"
`include "exception_tests/tensor_unaligned_base_vseq.sv"
`include "exception_tests/tensor_clear_error_recovery_vseq.sv"
`include "exception_tests/tensor_axi_read_error_vseq.sv"
`include "exception_tests/tensor_axi_write_error_vseq.sv"
`include "exception_tests/tensor_command_while_busy_vseq.sv"
`include "exception_tests/tensor_start_while_done_vseq.sv"
`include "exception_tests/tensor_burst_cross_4kb_vseq.sv"
`include "exception_tests/tensor_burst_len_config_vseq.sv"
`include "exception_tests/tensor_internal_timeout_vseq.sv"
`include "exception_tests/tensor_reset_during_operation_vseq.sv"
`include "exception_tests/tensor_soft_reset_vseq.sv"
`include "exception_tests/tensor_soft_reset_during_idle_vseq.sv"
`include "exception_tests/tensor_irq_on_error_vseq.sv"

`endif
