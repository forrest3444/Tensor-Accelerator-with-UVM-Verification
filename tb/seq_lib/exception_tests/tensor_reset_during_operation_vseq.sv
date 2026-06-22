`ifndef TENSOR_RESET_DURING_OPERATION_VSEQ_SV
`define TENSOR_RESET_DURING_OPERATION_VSEQ_SV

typedef enum int unsigned {
  RESET_DURING_LOAD,
  RESET_DURING_COMPUTE,
  RESET_DURING_STORE
} tensor_reset_phase_e;

class tensor_reset_during_operation_vseq extends base_vseq;
  `uvm_object_utils(tensor_reset_during_operation_vseq)

  tensor_reset_phase_e reset_phase;
  tensor_accel_env env;

  localparam bit [31:0] A_BASE = 32'h0001_0000;
  localparam bit [31:0] B_BASE = 32'h0002_0000;
  localparam bit [31:0] C_BASE = 32'h0003_0000;
  localparam bit [31:0] BIAS_BASE = 32'h0004_0000;

  function new(string name = "tensor_reset_during_operation_vseq");
    super.new(name);
    reset_phase = RESET_DURING_LOAD;
  endfunction

  virtual task body();
    `uvm_info(get_type_name(),
              $sformatf("Running reset recovery scenario phase=%s",
                        reset_phase_name()),
              UVM_MEDIUM)

    find_env();
    run_interrupted_task();
    check_idle_after_reset();
    check_dma_quiet_after_reset();
    run_recovery_task();
  endtask

  protected virtual task run_interrupted_task();
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;

    preload_initial_memory(32'd16, 32'd16, 32'd16);

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.m_size = 32'd16;
    program_seq.n_size = 32'd16;
    program_seq.k_size = 32'd16;
    program_seq.precision = PREC_INT8;
    program_seq.post_op = POST_NONE;
    program_seq.sat_mode = SAT_WRAP;
    program_seq.a_base = A_BASE;
    program_seq.b_base = B_BASE;
    program_seq.c_base = C_BASE;
    program_seq.bias_base = BIAS_BASE;
    program_seq.burst_len = 8'd16;
    program_seq.start(p_sequencer);

    start_seq = tensor_start_seq::type_id::create("start_seq");
    start_seq.start(p_sequencer);

    wait_for_reset_phase();
    wait_cfg_clocks(1);
    apply_hard_reset();
  endtask

  protected virtual task run_recovery_task();
    tensor_matmul_vseq recovery_seq;

    `uvm_info(get_type_name(),
              "Starting post-reset recovery matmul task",
              UVM_MEDIUM)
    recovery_seq = tensor_matmul_vseq::type_id::create("recovery_seq");
    recovery_seq.m_size = 32'd4;
    recovery_seq.n_size = 32'd4;
    recovery_seq.k_size = 32'd4;
    recovery_seq.precision = PREC_INT8;
    recovery_seq.post_op = POST_NONE;
    recovery_seq.sat_mode = SAT_WRAP;
    recovery_seq.a_base = A_BASE;
    recovery_seq.b_base = B_BASE;
    recovery_seq.c_base = C_BASE;
    recovery_seq.bias_base = BIAS_BASE;
    recovery_seq.burst_len = 8'd4;
    recovery_seq.timeout_cycles = 10000;
    recovery_seq.poll_interval_cycles = 100;
    recovery_seq.start(p_sequencer);
  endtask

  protected virtual task wait_for_reset_phase();
    bit active;

    for (int unsigned cycle = 0; cycle < 50000; cycle++) begin
      active = phase_active();
      if (active) begin
        `uvm_info(get_type_name(),
                  $sformatf("Observed %s active at cycle %0d",
                            reset_phase_name(), cycle),
                  UVM_MEDIUM)
        if (cfg != null) cfg.add_seq_check_count();
        return;
      end
      wait_cfg_clocks(1);
    end

    `uvm_error(get_type_name(),
               $sformatf("Timed out waiting for %s before reset",
                         reset_phase_name()))
    if (cfg != null) cfg.add_seq_check_error();
  endtask

  protected virtual task apply_hard_reset();
    if (cfg == null || cfg.vif == null) begin
      `uvm_error(get_type_name(), "Cannot apply reset: cfg.vif is null")
      if (cfg != null) cfg.add_seq_check_error();
      return;
    end

    `uvm_info(get_type_name(),
              $sformatf("Applying hard reset during %s", reset_phase_name()),
              UVM_MEDIUM)
    cfg.vif.apply_reset(8);
    if (reg_model != null) reg_model.reset();
    wait_cfg_clocks(4);
  endtask

  protected virtual task check_idle_after_reset();
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.ERROR_CODE, error_data);

    if ((status_data[31:0] &
         (STATUS_BUSY | STATUS_DONE | STATUS_ERROR | STATUS_IRQ |
          STATUS_OVERFLOW_SEEN)) != 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("STATUS was not idle after reset: 0x%08x",
                           status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (error_data[3:0] != ERR_NO_ERROR) begin
      `uvm_error(get_type_name(),
                 $sformatf("ERROR_CODE was not clear after reset: 0x%08x",
                           error_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  protected virtual task check_dma_quiet_after_reset();
    bit active_seen;

    active_seen = 1'b0;
    repeat (12) begin
      wait_cfg_clocks(1);
      if (memory_axi_active()) begin
        active_seen = 1'b1;
      end
    end

    if (active_seen) begin
      `uvm_error(get_type_name(), "Memory AXI activity remained after reset")
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  protected virtual function bit memory_axi_active();
    if (cfg == null || cfg.axi_slave_vif == null) begin
      return 1'b0;
    end

    return (cfg.axi_slave_vif.arvalid === 1'b1) ||
           (cfg.axi_slave_vif.rvalid  === 1'b1) ||
           (cfg.axi_slave_vif.rready  === 1'b1) ||
           (cfg.axi_slave_vif.awvalid === 1'b1) ||
           (cfg.axi_slave_vif.wvalid  === 1'b1) ||
           (cfg.axi_slave_vif.bvalid  === 1'b1) ||
           (cfg.axi_slave_vif.bready  === 1'b1);
  endfunction

  protected virtual task preload_initial_memory(bit [31:0] m_size,
                                                bit [31:0] n_size,
                                                bit [31:0] k_size);
    bit [7:0] a_bytes[];
    bit [7:0] b_bytes[];
    bit [7:0] c_bytes[];

    a_bytes = new[m_size * k_size];
    b_bytes = new[k_size * n_size];
    c_bytes = new[m_size * n_size * 4];

    foreach (a_bytes[idx]) begin
      a_bytes[idx] = bit'(idx[0]) ? 8'h03 : 8'hfd;
    end
    foreach (b_bytes[idx]) begin
      b_bytes[idx] = bit'(idx[1]) ? 8'h02 : 8'hfe;
    end
    foreach (c_bytes[idx]) begin
      c_bytes[idx] = 8'ha5;
    end

    env.axi_system_env.slave[0].write_num_byte(A_BASE, a_bytes.size(), a_bytes);
    env.axi_system_env.slave[0].write_num_byte(B_BASE, b_bytes.size(), b_bytes);
    env.axi_system_env.slave[0].write_num_byte(C_BASE, c_bytes.size(), c_bytes);
  endtask

  protected virtual function bit phase_active();
    if (cfg == null || cfg.vif == null) begin
      return 1'b0;
    end

    case (reset_phase)
      RESET_DURING_LOAD: return cfg.vif.load_active;
      RESET_DURING_COMPUTE: return cfg.vif.compute_active;
      RESET_DURING_STORE: return cfg.vif.store_active;
      default: return 1'b0;
    endcase
  endfunction

  protected virtual function string reset_phase_name();
    case (reset_phase)
      RESET_DURING_LOAD: return "load";
      RESET_DURING_COMPUTE: return "compute";
      RESET_DURING_STORE: return "store";
      default: return "unknown";
    endcase
  endfunction

  protected virtual function void find_env();
    uvm_component comp;

    comp = uvm_top.find("uvm_test_top.env");
    if (!$cast(env, comp) || env == null) begin
      `uvm_fatal(get_type_name(), "Unable to find tensor_accel_env at uvm_test_top.env")
    end
  endfunction
endclass

`endif
