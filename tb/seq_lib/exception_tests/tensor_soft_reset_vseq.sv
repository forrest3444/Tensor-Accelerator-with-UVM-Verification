`ifndef TENSOR_SOFT_RESET_VSEQ_SV
`define TENSOR_SOFT_RESET_VSEQ_SV

class tensor_soft_reset_vseq extends base_vseq;
  `uvm_object_utils(tensor_soft_reset_vseq)

  tensor_accel_env env;

  localparam bit [31:0] A_BASE = 32'h0001_0000;
  localparam bit [31:0] B_BASE = 32'h0002_0000;
  localparam bit [31:0] C_BASE = 32'h0003_0000;
  localparam bit [31:0] BIAS_BASE = 32'h0004_0000;

  function new(string name = "tensor_soft_reset_vseq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(),
              "Running soft reset during BUSY recovery scenario",
              UVM_MEDIUM)

    find_env();
    preload_memory(32'd64, 32'd64, 32'd64);
    program_matmul(32'd64, 32'd64, 32'd64, 8'd16);
    start_matmul();
    wait_until_busy();
    apply_soft_reset();
    check_reset_status();
    run_recovery_task();
  endtask

  protected virtual task program_matmul(bit [31:0] m_size,
                                        bit [31:0] n_size,
                                        bit [31:0] k_size,
                                        bit [7:0] burst_len);
    tensor_program_seq program_seq;

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.use_cfg_regions = 1'b0;
    program_seq.m_size = m_size;
    program_seq.n_size = n_size;
    program_seq.k_size = k_size;
    program_seq.precision = PREC_INT8;
    program_seq.post_op = POST_NONE;
    program_seq.sat_mode = SAT_WRAP;
    program_seq.a_base = A_BASE;
    program_seq.b_base = B_BASE;
    program_seq.c_base = C_BASE;
    program_seq.bias_base = BIAS_BASE;
    program_seq.a_spad_offset = 32'h0000_0000;
    program_seq.a_spad_size = 32'h0000_2000;
    program_seq.b_spad_offset = 32'h0000_2000;
    program_seq.b_spad_size = 32'h0000_2000;
    program_seq.c_spad_offset = 32'h0000_4000;
    program_seq.c_spad_size = 32'h0000_4000;
    program_seq.bias_spad_offset = 32'h0000_8000;
    program_seq.bias_spad_size = 32'h0000_0400;
    program_seq.burst_len = burst_len;
    program_seq.start(p_sequencer);
  endtask

  protected virtual task start_matmul();
    tensor_start_seq start_seq;

    start_seq = tensor_start_seq::type_id::create("start_seq");
    start_seq.start(p_sequencer);
  endtask

  protected virtual task wait_until_busy();
    uvm_reg_data_t status_data;

    for (int unsigned cycle = 0; cycle < 5000; cycle += 10) begin
      ral_read(reg_model.STATUS, status_data);
      if ((status_data[31:0] & STATUS_BUSY) != 0) begin
        `uvm_info(get_type_name(),
                  $sformatf("Observed BUSY before soft reset, STATUS=0x%08x",
                            status_data[31:0]),
                  UVM_MEDIUM)
        if (cfg != null) cfg.add_seq_check_count();
        return;
      end
      wait_cfg_clocks(10);
    end

    `uvm_error(get_type_name(), "Timed out waiting for STATUS.busy before soft reset")
    if (cfg != null) cfg.add_seq_check_error();
  endtask

  protected virtual task apply_soft_reset();
    `uvm_info(get_type_name(), "Issuing CTRL.soft_reset", UVM_MEDIUM)
    ral_write(reg_model.CTRL, CTRL_SOFT_RESET);
    wait_cfg_clocks(8);
  endtask

  protected virtual task check_reset_status();
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    uvm_reg_data_t ovf_data;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.ERROR_CODE, error_data);
    ral_read(reg_model.OVF_COUNT, ovf_data);

    if (status_data[31:0] != 32'd0) begin
      `uvm_error(get_type_name(),
                 $sformatf("STATUS was not zero after soft_reset: 0x%08x",
                           status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (error_data[3:0] != ERR_NO_ERROR) begin
      `uvm_error(get_type_name(),
                 $sformatf("ERROR_CODE was not ERR_NO_ERROR after soft_reset: 0x%08x",
                           error_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (ovf_data[31:0] != 32'd0) begin
      `uvm_error(get_type_name(),
                 $sformatf("OVF_COUNT was not zero after soft_reset: 0x%08x",
                           ovf_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  protected virtual task run_recovery_task();
    tensor_matmul_vseq recovery_seq;

    `uvm_info(get_type_name(),
              "Starting post-soft-reset recovery matmul task",
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

  protected virtual task preload_memory(bit [31:0] m_size,
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

  protected virtual task find_env();
    uvm_component comp;

    comp = uvm_top.find("uvm_test_top.env");
    if (!$cast(env, comp) || env == null) begin
      `uvm_fatal(get_type_name(), "Unable to find tensor_accel_env at uvm_test_top.env")
    end
  endtask
endclass

`endif
