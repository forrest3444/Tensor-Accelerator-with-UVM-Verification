`ifndef TENSOR_IRQ_ON_ERROR_VSEQ_SV
`define TENSOR_IRQ_ON_ERROR_VSEQ_SV

class tensor_irq_on_error_vseq extends base_vseq;
  `uvm_object_utils(tensor_irq_on_error_vseq)

  rand bit [1:0] illegal_precision;

  constraint c_illegal_precision {
    illegal_precision inside {2'd2, 2'd3};
  }

  function new(string name = "tensor_irq_on_error_vseq");
    super.new(name);
    illegal_precision = 2'd2;
  endfunction

  virtual task body();
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    tensor_wait_done_seq wait_seq;

    `uvm_info(get_type_name(),
              $sformatf("Running IRQ-on-error case PRECISION=%0d", illegal_precision),
              UVM_MEDIUM)

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.m_size = 32'd4;
    program_seq.n_size = 32'd4;
    program_seq.k_size = 32'd4;
    program_seq.precision = PREC_INT8;
    program_seq.post_op = POST_NONE;
    program_seq.sat_mode = SAT_WRAP;
    program_seq.a_base = 32'h0001_0000;
    program_seq.b_base = 32'h0002_0000;
    program_seq.c_base = 32'h0003_0000;
    program_seq.bias_base = 32'h0004_0000;
    program_seq.burst_len = 8'd16;
    program_seq.irq_en = 1'b1;
    program_seq.start(p_sequencer);

    ral_write(reg_model.PRECISION, {30'd0, illegal_precision});

    start_seq = tensor_start_seq::type_id::create("start_seq");
    start_seq.irq_en = 1'b1;
    start_seq.start(p_sequencer);

    wait_seq = tensor_wait_done_seq::type_id::create("wait_seq");
    wait_seq.timeout_cycles = 1000;
    wait_seq.poll_interval_cycles = 10;
    wait_seq.expect_error = 1'b1;
    wait_seq.check_error_code = 1'b1;
    wait_seq.exp_error_code = ERR_ILLEGAL_PRECISION;
    wait_seq.start(p_sequencer);

    check_irq_error_state();
    clear_error_status();
    check_irq_clear();
  endtask

  protected virtual task check_irq_error_state();
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    error_code_e actual_error_code;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.ERROR_CODE, error_data);
    actual_error_code = error_code_e'(error_data[3:0]);

    if (((status_data[31:0] & STATUS_ERROR) == 0) ||
        ((status_data[31:0] & STATUS_IRQ) == 0) ||
        (actual_error_code != ERR_ILLEGAL_PRECISION)) begin
      `uvm_error(get_type_name(),
                 $sformatf("Expected ERROR+IRQ with ILLEGAL_PRECISION, STATUS=0x%08x ERROR_CODE=%s",
                           status_data[31:0], actual_error_code.name()))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (cfg == null || cfg.vif == null || cfg.vif.irq !== 1'b1) begin
      `uvm_error(get_type_name(), "External irq pin was not asserted on error")
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  protected virtual task clear_error_status();
    ral_write(reg_model.CTRL, CTRL_IRQ_EN | CTRL_CLEAR_ERROR);
    wait_cfg_clocks(2);
  endtask

  protected virtual task check_irq_clear();
    uvm_reg_data_t status_data;

    ral_read(reg_model.STATUS, status_data);

    if ((status_data[31:0] & STATUS_IRQ) != 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("STATUS.irq was not cleared after clear_error, STATUS=0x%08x",
                           status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (cfg == null || cfg.vif == null || cfg.vif.irq !== 1'b0) begin
      `uvm_error(get_type_name(), "External irq pin was not deasserted after clear_error")
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask
endclass

`endif
