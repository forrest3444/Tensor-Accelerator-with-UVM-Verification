`ifndef TENSOR_START_WHILE_DONE_VSEQ_SV
`define TENSOR_START_WHILE_DONE_VSEQ_SV

class tensor_start_while_done_vseq extends tensor_matmul_vseq;
  `uvm_object_utils(tensor_start_while_done_vseq)

  function new(string name = "tensor_start_while_done_vseq");
    super.new(name);
    m_size = 4;
    n_size = 4;
    k_size = 4;
    precision = PREC_INT8;
    post_op = POST_NONE;
    sat_mode = SAT_WRAP;
    burst_len = 8'd4;
    auto_clear_status = 1'b0;
  endfunction

  virtual task body();
    `uvm_info(get_type_name(),
              "Running start-while-DONE command error scenario",
              UVM_MEDIUM)

    super.body();
    check_done_before_second_start();

    `uvm_info(get_type_name(),
              "Issuing CTRL.start while DONE is still uncleared",
              UVM_MEDIUM)
    ral_write(reg_model.CTRL, CTRL_START);
    wait_cfg_clocks(4);

    check_start_while_done_error();
    reset_dut_state();
  endtask

  protected virtual task check_done_before_second_start();
    uvm_reg_data_t status_data;

    ral_read(reg_model.STATUS, status_data);
    if ((status_data[31:0] & STATUS_DONE) == 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("Expected DONE before second start; STATUS=0x%08x",
                           status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  protected virtual task check_start_while_done_error();
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    error_code_e actual_error_code;
    error_code_e expected_error_code;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.ERROR_CODE, error_data);
    actual_error_code = error_code_e'(error_data[3:0]);
    expected_error_code = ERR_COMMAND_WHILE_BUSY;

    if ((status_data[31:0] & STATUS_ERROR) == 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("STATUS.error was not set after second start; STATUS=0x%08x",
                           status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if ((status_data[31:0] & STATUS_DONE) == 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("STATUS.done was cleared by second start; STATUS=0x%08x",
                           status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (actual_error_code != ERR_COMMAND_WHILE_BUSY) begin
      `uvm_error(get_type_name(),
                 $sformatf("ERROR_CODE mismatch exp=%s act=%s raw=0x%08x",
                           expected_error_code.name(),
                           actual_error_code.name(),
                           error_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  protected virtual task reset_dut_state();
    if (cfg == null || cfg.vif == null) begin
      `uvm_error(get_type_name(), "Cannot reset DUT: cfg.vif is null")
      if (cfg != null) cfg.add_seq_check_error();
      return;
    end

    cfg.vif.apply_reset(8);
    if (reg_model != null) reg_model.reset();
    wait_cfg_clocks(2);
  endtask
endclass

`endif
