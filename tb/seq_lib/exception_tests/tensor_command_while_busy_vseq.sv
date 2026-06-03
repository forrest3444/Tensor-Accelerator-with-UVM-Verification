`ifndef TENSOR_COMMAND_WHILE_BUSY_VSEQ_SV
`define TENSOR_COMMAND_WHILE_BUSY_VSEQ_SV

class tensor_command_while_busy_vseq extends base_vseq;
  `uvm_object_utils(tensor_command_while_busy_vseq)

  function new(string name = "tensor_command_while_busy_vseq");
    super.new(name);
  endfunction

  virtual task body();
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    tensor_wait_done_seq wait_seq;

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.use_cfg_regions = 1'b0;
    program_seq.m_size = 32'd64;
    program_seq.n_size = 32'd64;
    program_seq.k_size = 32'd64;
    program_seq.precision = PREC_INT8;
    program_seq.post_op = POST_NONE;
    program_seq.sat_mode = SAT_WRAP;
    program_seq.a_base = 32'h0001_0000;
    program_seq.b_base = 32'h0002_0000;
    program_seq.c_base = 32'h0003_0000;
    program_seq.bias_base = 32'h0004_0000;
    program_seq.a_spad_offset = 32'h0000_0000;
    program_seq.a_spad_size = 32'h0000_2000;
    program_seq.b_spad_offset = 32'h0000_2000;
    program_seq.b_spad_size = 32'h0000_2000;
    program_seq.c_spad_offset = 32'h0000_4000;
    program_seq.c_spad_size = 32'h0000_4000;
    program_seq.bias_spad_offset = 32'h0000_8000;
    program_seq.bias_spad_size = 32'h0000_0400;
    program_seq.burst_len = 8'd16;
    program_seq.start(p_sequencer);

    start_seq = tensor_start_seq::type_id::create("start_seq");
    start_seq.start(p_sequencer);

    wait_until_busy();

    `uvm_info(get_type_name(), "Issuing CTRL.start while DUT is busy", UVM_MEDIUM)
    ral_write(reg_model.CTRL, CTRL_START);

    wait_seq = tensor_wait_done_seq::type_id::create("wait_seq");
    wait_seq.timeout_cycles = 1000;
    wait_seq.poll_interval_cycles = 10;
    wait_seq.expect_error = 1'b1;
    wait_seq.check_error_code = 1'b1;
    wait_seq.exp_error_code = ERR_COMMAND_WHILE_BUSY;
    wait_seq.start(p_sequencer);

    check_error_state();
    reset_dut_state();
  endtask

  protected virtual task wait_until_busy();
    uvm_reg_data_t status_data;
    int unsigned waited_cycles;

    waited_cycles = 0;
    do begin
      ral_read(reg_model.STATUS, status_data);
      if ((status_data[31:0] & STATUS_BUSY) != 0) begin
        `uvm_info(get_type_name(),
                  $sformatf("Observed busy STATUS=0x%08x", status_data[31:0]),
                  UVM_MEDIUM)
        return;
      end
      wait_cfg_clocks(10);
      waited_cycles += 10;
    end while (waited_cycles < 5000);

    `uvm_error(get_type_name(), "Timed out waiting for STATUS.busy before second start")
    if (cfg != null) cfg.add_seq_check_error();
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

  protected virtual task check_error_state();
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
                 $sformatf("STATUS.error was not set; STATUS=0x%08x", status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (actual_error_code != ERR_COMMAND_WHILE_BUSY) begin
      `uvm_error(get_type_name(),
                 $sformatf("ERROR_CODE mismatch exp=%s act=%s raw=0x%08x",
                           expected_error_code.name(),
                           actual_error_code.name(),
                           error_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask
endclass

`endif
