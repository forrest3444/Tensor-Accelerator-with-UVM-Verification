`ifndef TENSOR_ACCEL_MATMUL_VSEQ_SV
`define TENSOR_ACCEL_MATMUL_VSEQ_SV

class tensor_matmul_vseq extends base_vseq;
  `uvm_object_utils(tensor_matmul_vseq)

  rand bit [31:0] m_size;
  rand bit [31:0] n_size;
  rand bit [31:0] k_size;
  rand precision_e precision;
  rand post_op_e post_op;
  rand sat_mode_e sat_mode;
  rand bit [31:0] a_base;
  rand bit [31:0] b_base;
  rand bit [31:0] c_base;
  rand bit [31:0] bias_base;
  rand bit [7:0] burst_len;
  rand int unsigned timeout_cycles;
  rand int unsigned poll_interval_cycles;
  bit irq_en;
  bit auto_clear_status;

  tensor_accel_env env;

  constraint c_dims {
    m_size inside {[1:MAX_DIM]};
    n_size inside {[1:MAX_DIM]};
    k_size inside {[1:MAX_DIM]};
  }

  constraint c_burst {
    burst_len inside {[1:16]};
  }

  constraint c_poll {
    poll_interval_cycles inside {[1:1000]};
  }

  function new(string name = "tensor_matmul_vseq");
    super.new(name);
    m_size = 32'd4;
    n_size = 32'd4;
    k_size = 32'd4;
    precision = PREC_INT8;
    post_op = POST_NONE;
    sat_mode = SAT_WRAP;
    a_base = 32'h0001_0000;
    b_base = 32'h0002_0000;
    c_base = 32'h0003_0000;
    bias_base = 32'h0004_0000;
    burst_len = 8'd4;
    timeout_cycles = 0;
    poll_interval_cycles = 1000;
    irq_en = 1'b0;
    auto_clear_status = 1'b1;
  endfunction

  virtual task body();
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    tensor_wait_done_seq wait_seq;
    tensor_clear_status_seq clear_seq;
    int signed a_data[];
    int signed b_data[];
    int signed golden_c[];
    int signed actual_c[];
    uvm_component comp;

    comp = uvm_top.find("uvm_test_top.env");
    if (!$cast(env, comp) || env == null) begin
      `uvm_fatal(get_type_name(), "Unable to find tensor_accel_env at uvm_test_top.env")
    end

    a_data = new[m_size * k_size];
    b_data = new[k_size * n_size];
    golden_c = new[m_size * n_size];
    actual_c = new[m_size * n_size];

    init_matrices(a_data, b_data, golden_c);
    preload_input_memory(a_data, b_data);
    poison_c_memory();

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.m_size = m_size;
    program_seq.n_size = n_size;
    program_seq.k_size = k_size;
    program_seq.precision = precision;
    program_seq.post_op = post_op;
    program_seq.sat_mode = sat_mode;
    program_seq.a_base = a_base;
    program_seq.b_base = b_base;
    program_seq.c_base = c_base;
    program_seq.bias_base = bias_base;
    program_seq.burst_len = burst_len;
    program_seq.irq_en = irq_en;
    program_seq.use_cfg_regions = 1'b1;
    program_seq.start(p_sequencer);

    start_seq = tensor_start_seq::type_id::create("start_seq");
    start_seq.irq_en = irq_en;
    start_seq.start(p_sequencer);

    wait_seq = tensor_wait_done_seq::type_id::create("wait_seq");
    wait_seq.timeout_cycles = effective_timeout_cycles();
    wait_seq.poll_interval_cycles = poll_interval_cycles;
    wait_seq.expect_error = 1'b0;
    wait_seq.start(p_sequencer);

    check_done_no_error();
    post_done_checks();
    read_c_memory(actual_c);
    compare_c_memory(golden_c, actual_c);

    if (auto_clear_status) begin
      clear_seq = tensor_clear_status_seq::type_id::create("clear_seq");
      clear_seq.start(p_sequencer);
      wait_for_status_clear();
    end
  endtask

  virtual function int unsigned effective_timeout_cycles();
    if (timeout_cycles != 0) begin
      return timeout_cycles;
    end
    return int'(m_size * n_size * k_size * 20);
  endfunction

  virtual function void init_matrices(ref int signed a_data[],
                                      ref int signed b_data[],
                                      ref int signed golden_c[]);
    for (int row = 0; row < m_size; row++) begin
      for (int kk = 0; kk < k_size; kk++) begin
        a_data[(row * k_size) + kk] = pattern_value(row, kk, 3, 5);
      end
    end

    for (int kk = 0; kk < k_size; kk++) begin
      for (int col = 0; col < n_size; col++) begin
        b_data[(kk * n_size) + col] = pattern_value(kk, col, 7, 2);
      end
    end

    compute_reference(a_data, b_data, golden_c);
  endfunction

  virtual function void compute_reference(const ref int signed a_data[],
                                          const ref int signed b_data[],
                                          ref int signed golden_c[]);
    for (int row = 0; row < m_size; row++) begin
      for (int col = 0; col < n_size; col++) begin
        longint signed acc;

        acc = 0;
        for (int kk = 0; kk < k_size; kk++) begin
          acc += a_data[(row * k_size) + kk] * b_data[(kk * n_size) + col];
        end
        golden_c[(row * n_size) + col] = wrap_int32(acc);
      end
    end
  endfunction

  virtual task preload_input_memory(const ref int signed a_data[],
                                    const ref int signed b_data[]);
    bit [7:0] a_bytes[];
    bit [7:0] b_bytes[];
    int unsigned elem_b;
    int unsigned panel_row_stride;

    elem_b = elem_bytes_local();
    panel_row_stride = align8_local(k_size * elem_b);
    a_bytes = new[m_size * panel_row_stride];
    b_bytes = new[n_size * panel_row_stride];

    foreach (a_bytes[idx]) begin
      a_bytes[idx] = 8'd0;
    end
    foreach (b_bytes[idx]) begin
      b_bytes[idx] = 8'd0;
    end

    for (int row = 0; row < m_size; row++) begin
      for (int kk = 0; kk < k_size; kk++) begin
        int unsigned src_idx;
        int unsigned dst_byte;

        src_idx = (row * k_size) + kk;
        dst_byte = (row * panel_row_stride) + (kk * elem_b);
        pack_elem_le(a_data[src_idx], a_bytes, dst_byte);
      end
    end
    for (int col = 0; col < n_size; col++) begin
      for (int kk = 0; kk < k_size; kk++) begin
        int unsigned src_idx;
        int unsigned dst_byte;

        src_idx = (kk * n_size) + col;
        dst_byte = (col * panel_row_stride) + (kk * elem_b);
        pack_elem_le(b_data[src_idx], b_bytes, dst_byte);
      end
    end

    env.axi_system_env.slave[0].write_num_byte(a_base, a_bytes.size(), a_bytes);
    env.axi_system_env.slave[0].write_num_byte(b_base, b_bytes.size(), b_bytes);
  endtask

  virtual task poison_c_memory();
    bit [7:0] c_bytes[];

    c_bytes = new[m_size * n_size * 4];
    foreach (c_bytes[idx]) begin
      c_bytes[idx] = 8'ha5;
    end
    env.axi_system_env.slave[0].write_num_byte(c_base, c_bytes.size(), c_bytes);
  endtask

  virtual task read_c_memory(ref int signed actual_c[]);
    bit [7:0] c_bytes[];
    bit signed [31:0] word_data;

    c_bytes = new[m_size * n_size * 4];
    env.axi_system_env.slave[0].read_num_byte(c_base, c_bytes.size(), c_bytes);

    for (int idx = 0; idx < m_size * n_size; idx++) begin
      word_data = {c_bytes[(idx * 4) + 3], c_bytes[(idx * 4) + 2],
                   c_bytes[(idx * 4) + 1], c_bytes[(idx * 4) + 0]};
      actual_c[idx] = word_data;
    end
  endtask

  virtual task compare_c_memory(const ref int signed golden_c[],
                                const ref int signed actual_c[]);
    for (int row = 0; row < m_size; row++) begin
      for (int col = 0; col < n_size; col++) begin
        int unsigned idx;

        idx = (row * n_size) + col;
        if (actual_c[idx] !== golden_c[idx]) begin
          `uvm_error(get_type_name(),
                     $sformatf("M=%0d N=%0d K=%0d C[%0d,%0d] mismatch exp=%0d act=%0d",
                               m_size, n_size, k_size, row, col,
                               golden_c[idx], actual_c[idx]))
          if (cfg != null) cfg.add_seq_check_error();
        end else if (cfg != null) begin
          cfg.add_seq_check_count();
        end
      end
    end
  endtask

  virtual task check_done_no_error();
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.ERROR_CODE, error_data);

    if ((status_data[1] !== 1'b1) || (status_data[2] !== 1'b0)) begin
      `uvm_error(get_type_name(),
                 $sformatf("Expected done=1 error=0, STATUS=0x%08x",
                           status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (error_data[3:0] !== ERR_NO_ERROR) begin
      `uvm_error(get_type_name(),
                 $sformatf("Expected ERROR_CODE=0, got 0x%08x", error_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  virtual task wait_for_status_clear();
    wait_cfg_clocks(2);
  endtask

  virtual task post_done_checks();
    report_performance_counters();
  endtask

  virtual task report_performance_counters();
    uvm_reg_data_t total_cycles;
    uvm_reg_data_t load_cycles;
    uvm_reg_data_t compute_cycles;
    uvm_reg_data_t post_cycles;
    uvm_reg_data_t store_cycles;
    uvm_reg_data_t idle_cycles;
    uvm_reg_data_t read_bytes;
    uvm_reg_data_t write_bytes;
    uvm_reg_data_t tile_count;
    uvm_reg_data_t read_bursts;
    uvm_reg_data_t write_bursts;
    uvm_reg_data_t read_stall;
    uvm_reg_data_t write_stall;
    uvm_reg_data_t spad_stall;

    ral_read(reg_model.PERF_TOTAL, total_cycles);
    ral_read(reg_model.PERF_LOAD, load_cycles);
    ral_read(reg_model.PERF_COMPUTE, compute_cycles);
    ral_read(reg_model.PERF_POST, post_cycles);
    ral_read(reg_model.PERF_STORE, store_cycles);
    ral_read(reg_model.PERF_IDLE, idle_cycles);
    ral_read(reg_model.PERF_RD_BYTES, read_bytes);
    ral_read(reg_model.PERF_WR_BYTES, write_bytes);
    ral_read(reg_model.PERF_TILE_COUNT, tile_count);
    ral_read(reg_model.PERF_RD_BURSTS, read_bursts);
    ral_read(reg_model.PERF_WR_BURSTS, write_bursts);
    ral_read(reg_model.PERF_RD_STALL, read_stall);
    ral_read(reg_model.PERF_WR_STALL, write_stall);
    ral_read(reg_model.PERF_SPAD_STALL, spad_stall);

    `uvm_info("PERF_BASELINE",
              $sformatf("m=%0d n=%0d k=%0d precision=%0d total=%0d load=%0d compute=%0d post=%0d store=%0d idle=%0d rd_bytes=%0d wr_bytes=%0d tiles=%0d rd_bursts=%0d wr_bursts=%0d rd_stall=%0d wr_stall=%0d spad_stall=%0d",
                        m_size, n_size, k_size, precision,
                        total_cycles, load_cycles, compute_cycles, post_cycles,
                        store_cycles, idle_cycles, read_bytes, write_bytes,
                        tile_count, read_bursts, write_bursts,
                        read_stall, write_stall, spad_stall),
              UVM_LOW)

    if ((total_cycles == 0) || (load_cycles == 0) || (compute_cycles == 0) ||
        (store_cycles == 0) || (read_bytes == 0) || (write_bytes == 0) ||
        (tile_count == 0)) begin
      `uvm_error(get_type_name(),
                 $sformatf("Performance counters did not advance as expected: total=%0d load=%0d compute=%0d store=%0d rd_bytes=%0d wr_bytes=%0d tiles=%0d",
                           total_cycles, load_cycles, compute_cycles, store_cycles,
                           read_bytes, write_bytes, tile_count))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  virtual function int signed pattern_value(input int unsigned row,
                                            input int unsigned col,
                                            input int unsigned row_mul,
                                            input int unsigned col_mul);
    return (precision == PREC_INT16) ? int16_pattern(row, col, row_mul, col_mul) :
                                       int8_pattern(row, col, row_mul, col_mul);
  endfunction

  virtual function int signed int8_pattern(input int unsigned row,
                                           input int unsigned col,
                                           input int unsigned row_mul,
                                           input int unsigned col_mul);
    int unsigned raw;

    raw = ((row * row_mul) + (col * col_mul) + (row ^ col)) % 9;
    return int'(raw) - 4;
  endfunction

  virtual function int signed int16_pattern(input int unsigned row,
                                            input int unsigned col,
                                            input int unsigned row_mul,
                                            input int unsigned col_mul);
    int signed raw;

    raw = int'(((row * row_mul * 97) + (col * col_mul * 53) +
                ((row ^ col) * 29)) % 4096);
    return raw - 2048;
  endfunction

  virtual function bit [7:0] int8_to_byte(int signed value);
    bit signed [7:0] signed_byte;

    signed_byte = value[7:0];
    return signed_byte[7:0];
  endfunction

  virtual function void pack_elem_le(int signed value,
                                     ref bit [7:0] bytes[],
                                     input int unsigned byte_idx);
    bit signed [15:0] half_data;

    if (precision == PREC_INT16) begin
      half_data = value[15:0];
      bytes[byte_idx + 0] = half_data[7:0];
      bytes[byte_idx + 1] = half_data[15:8];
    end else begin
      bytes[byte_idx] = int8_to_byte(value);
    end
  endfunction

  virtual function int unsigned elem_bytes_local();
    return (precision == PREC_INT16) ? 2 : 1;
  endfunction

  virtual function int unsigned align8_local(input int unsigned value);
    return (value + 7) & ~7;
  endfunction

  virtual function int signed wrap_int32(longint signed value);
    bit signed [31:0] word_data;

    word_data = value[31:0];
    return word_data;
  endfunction
endclass

`endif
