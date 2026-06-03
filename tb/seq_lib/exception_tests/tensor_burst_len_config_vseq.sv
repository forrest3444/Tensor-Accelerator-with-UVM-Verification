`ifndef TENSOR_BURST_LEN_CONFIG_VSEQ_SV
`define TENSOR_BURST_LEN_CONFIG_VSEQ_SV

class tensor_burst_len_zero_vseq extends base_vseq;
  `uvm_object_utils(tensor_burst_len_zero_vseq)

  function new(string name = "tensor_burst_len_zero_vseq");
    super.new(name);
  endfunction

  virtual task body();
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;

    `uvm_info(get_type_name(), "Running DMA_CFG=0 termination scenario", UVM_MEDIUM)

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.use_cfg_regions = 1'b0;
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
    program_seq.a_spad_offset = 32'h0000_0000;
    program_seq.a_spad_size = 32'h0000_2000;
    program_seq.b_spad_offset = 32'h0000_2000;
    program_seq.b_spad_size = 32'h0000_2000;
    program_seq.c_spad_offset = 32'h0000_4000;
    program_seq.c_spad_size = 32'h0000_4000;
    program_seq.bias_spad_offset = 32'h0000_8000;
    program_seq.bias_spad_size = 32'h0000_0400;
    program_seq.burst_len = 8'd0;
    program_seq.start(p_sequencer);

    start_seq = tensor_start_seq::type_id::create("start_seq");
    start_seq.start(p_sequencer);

    wait_for_expected_error();
    reset_dut_state();
  endtask

  protected virtual task wait_for_expected_error();
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    error_code_e actual_error_code;

    for (int unsigned cycle = 0; cycle < 5000; cycle += 10) begin
      ral_read(reg_model.STATUS, status_data);
      ral_read(reg_model.ERROR_CODE, error_data);
      actual_error_code = error_code_e'(error_data[3:0]);

      if ((status_data[31:0] & STATUS_ERROR) != 0) begin
        if (actual_error_code == ERR_AXI_READ_ERROR ||
            actual_error_code == ERR_BURST_CROSS_4KB) begin
          if (cfg != null) cfg.add_seq_check_count();
          return;
        end

        `uvm_error(get_type_name(),
                   $sformatf("Unexpected error code for DMA_CFG=0: %s raw=0x%08x",
                             actual_error_code.name(), error_data[31:0]))
        if (cfg != null) cfg.add_seq_check_error();
        return;
      end

      if ((status_data[31:0] & STATUS_DONE) != 0) begin
        `uvm_error(get_type_name(),
                   $sformatf("DMA_CFG=0 completed normally instead of erroring; STATUS=0x%08x",
                             status_data[31:0]))
        if (cfg != null) cfg.add_seq_check_error();
        return;
      end

      wait_cfg_clocks(10);
    end

    `uvm_error(get_type_name(), "Timed out waiting for DMA_CFG=0 to terminate")
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
endclass

class tensor_burst_len_exceed_vseq extends base_vseq;
  `uvm_object_utils(tensor_burst_len_exceed_vseq)

  bit ar_seen;

  function new(string name = "tensor_burst_len_exceed_vseq");
    super.new(name);
    ar_seen = 1'b0;
  endfunction

  virtual task body();
    tensor_matmul_vseq matmul_seq;

    `uvm_info(get_type_name(), "Running DMA_CFG=255 ARLEN clamp scenario", UVM_MEDIUM)

    matmul_seq = tensor_matmul_vseq::type_id::create("matmul_seq");
    matmul_seq.m_size = 32'd8;
    matmul_seq.n_size = 32'd8;
    matmul_seq.k_size = 32'd8;
    matmul_seq.precision = PREC_INT16;
    matmul_seq.post_op = POST_NONE;
    matmul_seq.sat_mode = SAT_WRAP;
    matmul_seq.burst_len = 8'hff;
    matmul_seq.timeout_cycles = 100000;
    matmul_seq.poll_interval_cycles = 100;

    fork
      monitor_arlen();
      matmul_seq.start(p_sequencer);
    join_any
    disable fork;

    if (!ar_seen) begin
      `uvm_error(get_type_name(), "No AXI read address burst was observed")
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  protected virtual task monitor_arlen();
    forever begin
      wait_cfg_clocks(1);
      if (cfg != null && cfg.axi_slave_vif != null &&
          cfg.axi_slave_vif.arvalid && cfg.axi_slave_vif.arready) begin
        ar_seen = 1'b1;
        if (cfg.axi_slave_vif.arlen[7:0] > 8'd15) begin
          `uvm_error(get_type_name(),
                     $sformatf("ARLEN exceeded MAX_BURST_BEATS-1: arlen=%0d",
                               cfg.axi_slave_vif.arlen[7:0]))
          if (cfg != null) cfg.add_seq_check_error();
        end
      end
    end
  endtask
endclass

`endif
