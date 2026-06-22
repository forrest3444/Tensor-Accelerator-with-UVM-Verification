`ifndef TENSOR_AXI_READ_ERROR_VSEQ_SV
`define TENSOR_AXI_READ_ERROR_VSEQ_SV

class tensor_axi_read_error_slave_seq extends svt_axi_slave_memory_sequence;
  `uvm_object_utils(tensor_axi_read_error_slave_seq)

  static bit enabled = 1'b0;
  static bit [31:0] error_base = 32'd0;
  static bit [31:0] error_limit = 32'd0;
  static svt_axi_transaction::resp_type_enum error_resp =
      svt_axi_transaction::SLVERR;

  function new(string name = "tensor_axi_read_error_slave_seq");
    super.new(name);
    OKAY_wt = 100;
    EXOKAY_wt = 0;
    SLVERR_wt = 0;
    DECERR_wt = 0;
  endfunction

  static function void arm_read_error(bit [31:0] base,
                                      bit [31:0] byte_len,
                                      svt_axi_transaction::resp_type_enum resp);
    enabled = 1'b1;
    error_base = base;
    error_limit = base + byte_len;
    error_resp = resp;
  endfunction

  static function void disarm_read_error();
    enabled = 1'b0;
    error_base = 32'd0;
    error_limit = 32'd0;
    error_resp = svt_axi_transaction::SLVERR;
  endfunction

  protected function bit should_error_read(`SVT_AXI_SLAVE_TRANSACTION_TYPE slave_xact);
    bit [31:0] min_addr;
    bit [31:0] max_addr;

    if (!enabled) return 1'b0;
    if (slave_xact.xact_type != svt_axi_transaction::READ) return 1'b0;

    min_addr = slave_xact.get_min_byte_address(slave_xact.addr);
    max_addr = slave_xact.get_max_byte_address(slave_xact.addr);
    return (min_addr < error_limit) && (max_addr >= error_base);
  endfunction

  virtual task randomize_slave_xact(`SVT_AXI_SLAVE_TRANSACTION_TYPE slave_xact,
                                    bit is_slv_decerr,
                                    bit enable_perf_mode = 0);
    bit inject_error;
    bit status;

    inject_error = should_error_read(slave_xact);
    status = slave_xact.randomize() with {
      bresp == svt_axi_slave_transaction::OKAY;
      foreach (rresp[index]) {
        if (local::inject_error) {
          rresp[index] == local::error_resp;
        } else if (is_slv_decerr) {
          rresp[index] == svt_axi_slave_transaction::DECERR;
        } else {
          rresp[index] == svt_axi_slave_transaction::OKAY;
        }
      }
      if (is_slv_decerr) {
        bresp == svt_axi_slave_transaction::DECERR;
      }
      if (enable_perf_mode) {
        addr_ready_delay == 0;
        foreach (wready_delay[idx]) wready_delay[idx] == 0;
        bvalid_delay == 0;
        foreach (rvalid_delay[idx]) rvalid_delay[idx] == 0;
      }
    };

    if (!status) begin
      `uvm_fatal(get_type_name(), "Randomization of AXI read-error slave response failed")
    end

    if (inject_error) begin
      `uvm_info(get_type_name(),
                $sformatf("Injecting %s on AXI read addr=0x%08x target=[0x%08x:0x%08x)",
                          error_resp.name(), slave_xact.addr, error_base, error_limit),
                UVM_MEDIUM)
    end
  endtask
endclass

class tensor_axi_read_error_vseq extends base_vseq;
  `uvm_object_utils(tensor_axi_read_error_vseq)

  typedef struct packed {
    tensor_type_e tensor_type;
    bit [31:0]    base;
    bit [31:0]    byte_len;
    post_op_e     post_op;
    bit           use_decerr;
  } read_error_case_t;

  bit fail_on_compute_active;

  function new(string name = "tensor_axi_read_error_vseq");
    super.new(name);
    fail_on_compute_active = 1'b0;
  endfunction

  virtual task body();
    read_error_case_t error_cases[$];

    error_cases.push_back('{TENSOR_A, 32'h0001_0000, 32'd16, POST_NONE, 1'b0});
    error_cases.push_back('{TENSOR_B, 32'h0002_0000, 32'd16, POST_NONE, 1'b1});
    error_cases.push_back('{TENSOR_BIAS, 32'h0004_0000, 32'd16, POST_BIAS, 1'b0});

    foreach (error_cases[i]) begin
      run_read_error_case(error_cases[i]);
    end
    tensor_axi_read_error_slave_seq::disarm_read_error();
  endtask

  protected virtual task run_read_error_case(read_error_case_t error_case);
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    tensor_wait_done_seq wait_seq;
    svt_axi_transaction::resp_type_enum resp;
    bit compute_seen;

    resp = error_case.use_decerr ? svt_axi_transaction::DECERR :
                                   svt_axi_transaction::SLVERR;
    compute_seen = 1'b0;
    tensor_axi_read_error_slave_seq::arm_read_error(error_case.base,
                                                    error_case.byte_len,
                                                    resp);

    `uvm_info(get_type_name(),
              $sformatf("Running AXI read-error case tensor=%0d base=0x%08x len=%0d resp=%s",
                        error_case.tensor_type, error_case.base,
                        error_case.byte_len, resp.name()),
              UVM_MEDIUM)

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.m_size = 32'd4;
    program_seq.n_size = 32'd4;
    program_seq.k_size = 32'd4;
    program_seq.precision = PREC_INT8;
    program_seq.post_op = error_case.post_op;
    program_seq.sat_mode = SAT_WRAP;
    program_seq.a_base = 32'h0001_0000;
    program_seq.b_base = 32'h0002_0000;
    program_seq.c_base = 32'h0003_0000;
    program_seq.bias_base = 32'h0004_0000;
    program_seq.burst_len = 8'd16;
    program_seq.start(p_sequencer);

    start_seq = tensor_start_seq::type_id::create("start_seq");
    start_seq.start(p_sequencer);

    wait_seq = tensor_wait_done_seq::type_id::create("wait_seq");
    wait_seq.timeout_cycles = 5000;
    wait_seq.poll_interval_cycles = 10;
    wait_seq.expect_error = 1'b1;
    wait_seq.check_error_code = 1'b1;
    wait_seq.exp_error_code = ERR_AXI_READ_ERROR;

    fork
      begin
        forever begin
          wait_cfg_clocks(1);
          if (cfg != null && cfg.vif != null && cfg.vif.compute_active) begin
            compute_seen = 1'b1;
          end
        end
      end
      begin
        wait_seq.start(p_sequencer);
      end
    join_any
    disable fork;

    check_error_state();
    if (fail_on_compute_active && compute_seen) begin
      `uvm_error(get_type_name(),
                 "COMPUTE became active after the injected AXI read error")
      if (cfg != null) cfg.add_seq_check_error();
    end else if (fail_on_compute_active && cfg != null) begin
      cfg.add_seq_check_count();
    end
    wait_for_axi_read_idle();
    reset_dut_state();
  endtask

  protected virtual task wait_for_axi_read_idle();
    int unsigned idle_cycles;
    int unsigned waited_cycles;

    idle_cycles = 0;
    waited_cycles = 0;
    while (idle_cycles < 5 && waited_cycles < 1000) begin
      wait_cfg_clocks(1);
      waited_cycles++;
      if (cfg != null && cfg.axi_slave_vif != null &&
          !cfg.axi_slave_vif.arvalid &&
          !cfg.axi_slave_vif.rvalid &&
          !cfg.axi_slave_vif.rready) begin
        idle_cycles++;
      end else begin
        idle_cycles = 0;
      end
    end

    if (idle_cycles < 5) begin
      `uvm_error(get_type_name(), "Timed out waiting for AXI read channel to go idle")
      if (cfg != null) cfg.add_seq_check_error();
    end
  endtask

  protected virtual task reset_dut_state();
    tensor_axi_read_error_slave_seq::disarm_read_error();
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
    expected_error_code = ERR_AXI_READ_ERROR;

    if ((status_data[31:0] & STATUS_ERROR) == 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("STATUS.error was not set; STATUS=0x%08x", status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (actual_error_code != ERR_AXI_READ_ERROR) begin
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

class tensor_axi_read_bias_error_vseq extends tensor_axi_read_error_vseq;
  `uvm_object_utils(tensor_axi_read_bias_error_vseq)

  function new(string name = "tensor_axi_read_bias_error_vseq");
    super.new(name);
    fail_on_compute_active = 1'b1;
  endfunction

  virtual task body();
    read_error_case_t bias_error_case;

    bias_error_case = '{TENSOR_BIAS,
                        32'h0004_0000,
                        32'd16,
                        POST_BIAS,
                        1'b0};

    run_read_error_case(bias_error_case);
    tensor_axi_read_error_slave_seq::disarm_read_error();
  endtask
endclass

`endif
