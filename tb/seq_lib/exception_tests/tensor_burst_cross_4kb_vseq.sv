`ifndef TENSOR_BURST_CROSS_4KB_VSEQ_SV
`define TENSOR_BURST_CROSS_4KB_VSEQ_SV

class tensor_burst_cross_4kb_vseq extends base_vseq;
  `uvm_object_utils(tensor_burst_cross_4kb_vseq)

  typedef enum int unsigned {
    CROSS_A_READ,
    CROSS_B_READ
  } cross_target_e;

  typedef struct {
    cross_target_e target;
    bit [31:0]     m_size;
    bit [31:0]     n_size;
    bit [31:0]     k_size;
    bit [31:0]     a_base;
    bit [31:0]     b_base;
    string         label;
  } burst_cross_case_t;

  bit stop_ar_monitor;
  bit illegal_ar_seen;

  localparam bit [31:0] CROSS_BASE = 32'h0000_0ff8;
  localparam bit [31:0] SAFE_A_BASE = 32'h0001_0000;
  localparam bit [31:0] SAFE_B_BASE = 32'h0002_0000;
  localparam bit [31:0] C_BASE = 32'h0003_0000;
  localparam bit [31:0] BIAS_BASE = 32'h0004_0000;
  localparam int unsigned AXI_BEAT_BYTES = 8;

  function new(string name = "tensor_burst_cross_4kb_vseq");
    super.new(name);
  endfunction

  virtual task body();
    burst_cross_case_t burst_cases[$];

    burst_cases.push_back('{CROSS_A_READ, 32'd4, 32'd4, 32'd5,
                            CROSS_BASE, SAFE_B_BASE, "A read"});
    burst_cases.push_back('{CROSS_B_READ, 32'd4, 32'd5, 32'd4,
                            SAFE_A_BASE, CROSS_BASE, "B read"});

    foreach (burst_cases[i]) begin
      run_burst_cross_case(burst_cases[i]);
      reset_dut_state();
    end
  endtask

  protected virtual task run_burst_cross_case(burst_cross_case_t burst_case);
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    tensor_wait_done_seq wait_seq;

    `uvm_info(get_type_name(),
              $sformatf("Running 4KB-crossing read-DMA case on %s M=%0d N=%0d K=%0d A=0x%08x B=0x%08x",
                        burst_case.label,
                        burst_case.m_size,
                        burst_case.n_size,
                        burst_case.k_size,
                        burst_case.a_base,
                        burst_case.b_base),
              UVM_MEDIUM)

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.m_size = burst_case.m_size;
    program_seq.n_size = burst_case.n_size;
    program_seq.k_size = burst_case.k_size;
    program_seq.precision = PREC_INT8;
    program_seq.post_op = POST_NONE;
    program_seq.sat_mode = SAT_WRAP;
    program_seq.a_base = burst_case.a_base;
    program_seq.b_base = burst_case.b_base;
    program_seq.c_base = C_BASE;
    program_seq.bias_base = BIAS_BASE;
    program_seq.burst_len = 8'd16;
    program_seq.start(p_sequencer);

    stop_ar_monitor = 1'b0;
    illegal_ar_seen = 1'b0;

    fork
      monitor_no_illegal_ar_burst();
      begin
        start_seq = tensor_start_seq::type_id::create("start_seq");
        start_seq.start(p_sequencer);

        wait_seq = tensor_wait_done_seq::type_id::create("wait_seq");
        wait_seq.timeout_cycles = 2000;
        wait_seq.poll_interval_cycles = 10;
        wait_seq.expect_error = 1'b1;
        wait_seq.check_error_code = 1'b1;
        wait_seq.exp_error_code = ERR_BURST_CROSS_4KB;
        wait_seq.start(p_sequencer);

        stop_ar_monitor = 1'b1;
      end
    join

    repeat (4) begin
      wait_cfg_clocks(1);
      sample_ar_channel();
    end

    check_error_state();
    check_no_illegal_ar_seen(burst_case);
  endtask

  protected virtual task monitor_no_illegal_ar_burst();
    while (!stop_ar_monitor) begin
      wait_cfg_clocks(1);
      sample_ar_channel();
    end
  endtask

  protected virtual function void sample_ar_channel();
    bit [31:0] araddr;
    bit [7:0] arlen;
    int unsigned burst_bytes;
    int unsigned offset_4kb;

    if (cfg == null || cfg.axi_slave_vif == null) begin
      return;
    end

    if (cfg.axi_slave_vif.arvalid === 1'b1) begin
      araddr = cfg.axi_slave_vif.araddr[31:0];
      arlen = cfg.axi_slave_vif.arlen[7:0];
      burst_bytes = (int'(arlen) + 1) * AXI_BEAT_BYTES;
      offset_4kb = int'(araddr[11:0]);

      if ((offset_4kb + burst_bytes) > 4096) begin
        illegal_ar_seen = 1'b1;
        `uvm_error(get_type_name(),
                   $sformatf("Illegal 4KB-crossing AR burst issued addr=0x%08x arlen=%0d bytes=%0d",
                             araddr, arlen, burst_bytes))
        if (cfg != null) cfg.add_seq_check_error();
      end
    end
  endfunction

  protected virtual task check_error_state();
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    error_code_e actual_error_code;
    error_code_e expected_error_code;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.ERROR_CODE, error_data);
    actual_error_code = error_code_e'(error_data[3:0]);
    expected_error_code = ERR_BURST_CROSS_4KB;

    if ((status_data[31:0] & STATUS_ERROR) == 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("STATUS.error was not set; STATUS=0x%08x", status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (actual_error_code != ERR_BURST_CROSS_4KB) begin
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

  protected virtual function void check_no_illegal_ar_seen(burst_cross_case_t burst_case);
    if (illegal_ar_seen) begin
      `uvm_error(get_type_name(),
                 $sformatf("Illegal AXI read burst was issued for %s crossing case",
                           burst_case.label))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endfunction

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
