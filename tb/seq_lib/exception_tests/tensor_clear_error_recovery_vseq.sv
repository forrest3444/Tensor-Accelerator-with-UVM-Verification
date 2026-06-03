`ifndef TENSOR_CLEAR_ERROR_RECOVERY_VSEQ_SV
`define TENSOR_CLEAR_ERROR_RECOVERY_VSEQ_SV

class tensor_clear_error_recovery_vseq extends base_vseq;
  `uvm_object_utils(tensor_clear_error_recovery_vseq)

  function new(string name = "tensor_clear_error_recovery_vseq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(),
              "Running clear-error recovery scenario",
              UVM_MEDIUM)

    trigger_unaligned_base_error();
    check_error_state("before clear_error", ERR_UNALIGNED_BASE_ADDR);
    clear_error_only();
    check_idle_no_error();
    run_recovery_matmul();
  endtask

  protected virtual task trigger_unaligned_base_error();
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    tensor_wait_done_seq wait_seq;

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.m_size = 32'd4;
    program_seq.n_size = 32'd4;
    program_seq.k_size = 32'd4;
    program_seq.precision = PREC_INT8;
    program_seq.post_op = POST_NONE;
    program_seq.sat_mode = SAT_WRAP;
    program_seq.a_base = 32'h0001_0001;
    program_seq.b_base = 32'h0002_0000;
    program_seq.c_base = 32'h0003_0000;
    program_seq.bias_base = 32'h0004_0000;
    program_seq.burst_len = 8'd16;
    program_seq.start(p_sequencer);

    start_seq = tensor_start_seq::type_id::create("start_seq");
    start_seq.start(p_sequencer);

    wait_seq = tensor_wait_done_seq::type_id::create("wait_seq");
    wait_seq.timeout_cycles = 1000;
    wait_seq.poll_interval_cycles = 10;
    wait_seq.expect_error = 1'b1;
    wait_seq.check_error_code = 1'b1;
    wait_seq.exp_error_code = ERR_UNALIGNED_BASE_ADDR;
    wait_seq.start(p_sequencer);
  endtask

  protected virtual task clear_error_only();
    tensor_clear_status_seq clear_seq;

    `uvm_info(get_type_name(), "Issuing CTRL.clear_error", UVM_MEDIUM)
    clear_seq = tensor_clear_status_seq::type_id::create("clear_error_seq");
    clear_seq.clear_done = 1'b0;
    clear_seq.clear_error = 1'b1;
    clear_seq.clear_irq = 1'b0;
    clear_seq.start(p_sequencer);
    wait_cfg_clocks(2);
  endtask

  protected virtual task run_recovery_matmul();
    tensor_matmul_vseq matmul_seq;

    `uvm_info(get_type_name(),
              "Starting legal recovery matmul after clear_error",
              UVM_MEDIUM)
    matmul_seq = tensor_matmul_vseq::type_id::create("recovery_matmul_seq");
    matmul_seq.m_size = 32'd4;
    matmul_seq.n_size = 32'd4;
    matmul_seq.k_size = 32'd4;
    matmul_seq.precision = PREC_INT8;
    matmul_seq.post_op = POST_NONE;
    matmul_seq.sat_mode = SAT_WRAP;
    matmul_seq.a_base = 32'h0001_0000;
    matmul_seq.b_base = 32'h0002_0000;
    matmul_seq.c_base = 32'h0003_0000;
    matmul_seq.bias_base = 32'h0004_0000;
    matmul_seq.burst_len = 8'd4;
    matmul_seq.timeout_cycles = 20000;
    matmul_seq.poll_interval_cycles = 100;
    matmul_seq.auto_clear_status = 1'b1;
    matmul_seq.start(p_sequencer);

    check_idle_no_error();
  endtask

  protected virtual task check_error_state(string check_context,
                                           error_code_e exp_error_code);
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    error_code_e actual_error_code;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.ERROR_CODE, error_data);
    actual_error_code = error_code_e'(error_data[3:0]);

    if ((status_data[31:0] & STATUS_ERROR) == 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("%s: STATUS.error was not set, STATUS=0x%08x",
                           check_context, status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (actual_error_code != exp_error_code) begin
      `uvm_error(get_type_name(),
                 $sformatf("%s: ERROR_CODE mismatch exp=%s act=%s raw=0x%08x",
                           check_context, exp_error_code.name(),
                           actual_error_code.name(), error_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  protected virtual task check_idle_no_error();
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    error_code_e actual_error_code;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.ERROR_CODE, error_data);
    actual_error_code = error_code_e'(error_data[3:0]);

    if ((status_data[31:0] &
         (STATUS_BUSY | STATUS_DONE | STATUS_ERROR | STATUS_IRQ)) != 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("Expected IDLE status after recovery step, STATUS=0x%08x",
                           status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (actual_error_code != ERR_NO_ERROR) begin
      `uvm_error(get_type_name(),
                 $sformatf("Expected ERROR_CODE=ERR_NO_ERROR, act=%s raw=0x%08x",
                           actual_error_code.name(), error_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask
endclass

`endif
