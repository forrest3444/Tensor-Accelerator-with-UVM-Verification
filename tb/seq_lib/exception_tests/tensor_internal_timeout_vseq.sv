`ifndef TENSOR_INTERNAL_TIMEOUT_VSEQ_SV
`define TENSOR_INTERNAL_TIMEOUT_VSEQ_SV

class tensor_axi_read_hang_slave_seq extends svt_axi_slave_memory_sequence;
  `uvm_object_utils(tensor_axi_read_hang_slave_seq)

  static bit enabled = 1'b0;
  static int unsigned hang_rvalid_delay = 16;

  function new(string name = "tensor_axi_read_hang_slave_seq");
    super.new(name);
    OKAY_wt = 100;
    EXOKAY_wt = 0;
    SLVERR_wt = 0;
    DECERR_wt = 0;
  endfunction

  static function void arm_read_hang(int unsigned delay_cycles = 16);
    enabled = 1'b1;
    hang_rvalid_delay = delay_cycles;
  endfunction

  static function void disarm_read_hang();
    enabled = 1'b0;
    hang_rvalid_delay = 16;
  endfunction

  virtual task randomize_slave_xact(`SVT_AXI_SLAVE_TRANSACTION_TYPE slave_xact,
                                    bit is_slv_decerr,
                                    bit enable_perf_mode = 0);
    bit status;
    bit hang_read;

    hang_read = enabled && (slave_xact.xact_type == svt_axi_transaction::READ);
    status = slave_xact.randomize() with {
      addr_ready_delay == 0;
      bresp == svt_axi_slave_transaction::OKAY;
      foreach (wready_delay[idx]) wready_delay[idx] == 0;
      bvalid_delay == 0;
      foreach (rresp[index]) rresp[index] == svt_axi_slave_transaction::OKAY;
      foreach (rvalid_delay[idx]) rvalid_delay[idx] == 0;
    };

    if (!status) begin
      `uvm_fatal(get_type_name(), "Randomization of AXI read-hang slave response failed")
    end

    if (hang_read) begin
      foreach (slave_xact.rvalid_delay[idx]) slave_xact.rvalid_delay[idx] = hang_rvalid_delay;
      slave_xact.reference_event_for_first_rvalid_delay =
          svt_axi_transaction::READ_ADDR_HANDSHAKE;
      slave_xact.reference_event_for_next_rvalid_delay =
          svt_axi_transaction::PREV_READ_HANDSHAKE;
      `uvm_info(get_type_name(),
                $sformatf("Preparing AXI read response with max legal rvalid_delay=%0d for AR addr=0x%08x",
                          hang_rvalid_delay, slave_xact.addr),
                UVM_MEDIUM)
    end
  endtask
endclass

class tensor_internal_timeout_vseq extends base_vseq;
  `uvm_object_utils(tensor_internal_timeout_vseq)

  localparam int unsigned WATCHDOG_TIMEOUT_CYCLES = 32'h000f_ffff;
  localparam int unsigned TIMEOUT_POLL_CYCLES = 8192;
  localparam int unsigned TIMEOUT_MARGIN_CYCLES = 65536;

  bit ar_seen;
  bit rvalid_before_timeout;
  bit rvalid_forced;
  int unsigned cycles_after_ar;
  int unsigned timeout_observed_cycles;

  function new(string name = "tensor_internal_timeout_vseq");
    super.new(name);
    ar_seen = 1'b0;
    rvalid_before_timeout = 1'b0;
    rvalid_forced = 1'b0;
    cycles_after_ar = 0;
    timeout_observed_cycles = 0;
  endfunction

  virtual task body();
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;

    `uvm_info(get_type_name(), "Running AXI read-hang internal watchdog scenario", UVM_MEDIUM)
    tensor_axi_read_hang_slave_seq::arm_read_hang(16);

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
    program_seq.burst_len = 8'd16;
    program_seq.start(p_sequencer);

    start_seq = tensor_start_seq::type_id::create("start_seq");
    start_seq.start(p_sequencer);

    fork
      monitor_read_channel();
      wait_for_internal_timeout();
    join_any
    disable fork;

    if (!ar_seen) begin
      `uvm_error(get_type_name(), "No AXI AR handshake was observed before timeout check completed")
      if (cfg != null) cfg.add_seq_check_error();
    end
    if (rvalid_before_timeout) begin
      `uvm_error(get_type_name(), "AXI RVALID asserted before the internal timeout was reported")
      if (cfg != null) cfg.add_seq_check_error();
    end

    reset_dut_state();
  endtask

  protected virtual task monitor_read_channel();
    bit counting;

    counting = 1'b0;
    forever begin
      wait_cfg_clocks(1);
      if (!counting && cfg != null && cfg.axi_slave_vif != null &&
          cfg.axi_slave_vif.arvalid && cfg.axi_slave_vif.arready) begin
        ar_seen = 1'b1;
        counting = 1'b1;
        cycles_after_ar = 0;
        if (cfg != null && cfg.vif != null) begin
          cfg.vif.force_axi_rvalid_low = 1'b1;
          rvalid_forced = 1'b1;
        end else begin
          `uvm_error(get_type_name(), "Cannot suppress AXI RVALID: cfg.vif is null")
          if (cfg != null) cfg.add_seq_check_error();
        end
      end
      else if (counting) begin
        cycles_after_ar++;
      end

      if (counting && cfg != null && cfg.vif != null &&
          cfg.vif.axi_rvalid_to_dut) begin
        rvalid_before_timeout = 1'b1;
      end
    end
  endtask

  protected virtual task wait_for_internal_timeout();
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    error_code_e actual_error_code;
    error_code_e expected_error_code;
    int unsigned waited_cycles;
    int unsigned max_wait_cycles;

    waited_cycles = 0;
    max_wait_cycles = WATCHDOG_TIMEOUT_CYCLES + TIMEOUT_MARGIN_CYCLES;
    expected_error_code = ERR_INTERNAL_TIMEOUT;

    while (waited_cycles <= max_wait_cycles) begin
      ral_read(reg_model.STATUS, status_data);
      ral_read(reg_model.ERROR_CODE, error_data);
      actual_error_code = error_code_e'(error_data[3:0]);

      if ((status_data[31:0] & STATUS_ERROR) != 0) begin
        timeout_observed_cycles = cycles_after_ar;
        if (actual_error_code != ERR_INTERNAL_TIMEOUT) begin
          `uvm_error(get_type_name(),
                     $sformatf("ERROR_CODE mismatch exp=%s act=%s raw=0x%08x",
                               expected_error_code.name(),
                               actual_error_code.name(),
                               error_data[31:0]))
          if (cfg != null) cfg.add_seq_check_error();
        end
        else if (timeout_observed_cycles < WATCHDOG_TIMEOUT_CYCLES ||
                 timeout_observed_cycles >
                   (WATCHDOG_TIMEOUT_CYCLES + TIMEOUT_MARGIN_CYCLES)) begin
          `uvm_error(get_type_name(),
                     $sformatf("Watchdog timeout cycle mismatch exp~0x%08x act=%0d",
                               WATCHDOG_TIMEOUT_CYCLES,
                               timeout_observed_cycles))
          if (cfg != null) cfg.add_seq_check_error();
        end
        else if (cfg != null) begin
          cfg.add_seq_check_count();
        end
        return;
      end

      if ((status_data[31:0] & STATUS_DONE) != 0) begin
        `uvm_error(get_type_name(),
                   $sformatf("Read-hang scenario completed normally; STATUS=0x%08x",
                             status_data[31:0]))
        if (cfg != null) cfg.add_seq_check_error();
        return;
      end

      wait_cfg_clocks(TIMEOUT_POLL_CYCLES);
      waited_cycles += TIMEOUT_POLL_CYCLES;
    end

    `uvm_error(get_type_name(), "Timed out waiting for ERR_INTERNAL_TIMEOUT")
    if (cfg != null) cfg.add_seq_check_error();
  endtask

  protected virtual task reset_dut_state();
    tensor_axi_read_hang_slave_seq::disarm_read_hang();
    if (rvalid_forced && cfg != null && cfg.vif != null) begin
      cfg.vif.force_axi_rvalid_low = 1'b0;
      rvalid_forced = 1'b0;
    end
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
