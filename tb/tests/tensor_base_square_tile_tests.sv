`ifndef TENSOR_ACCEL_BASE_SQUARE_TILE_TESTS_SV
`define TENSOR_ACCEL_BASE_SQUARE_TILE_TESTS_SV

virtual class tensor_base_square_tile_test_base extends base_test;
  localparam bit [31:0] A_BASE = 32'h0001_0000;
  localparam bit [31:0] B_BASE = 32'h0002_0000;
  localparam bit [31:0] C_BASE = 32'h0003_0000;

  function new(string name = "tensor_base_square_tile_test_base",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  pure virtual function int unsigned dim();

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    wait_for_reset_done();
    run_square_tile_test();
    phase.drop_objection(this);
  endtask

  virtual task wait_for_reset_done();
    if (cfg != null && cfg.vif != null) begin
      @(posedge cfg.vif.rst_n);
      repeat (2) @(posedge cfg.vif.clk);
    end
  endtask

  virtual task run_square_tile_test();
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    tensor_wait_done_seq wait_seq;
    tensor_clear_status_seq clear_seq;
    int unsigned d;
    int signed a_data[];
    int signed b_data[];
    int signed golden_c[];
    int signed actual_c[];

    d = dim();
    a_data = new[d * d];
    b_data = new[d * d];
    golden_c = new[d * d];
    actual_c = new[d * d];

    init_matrices(d, a_data, b_data, golden_c);
    preload_input_memory(d, a_data, b_data);
    poison_c_memory(d);

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.m_size = d;
    program_seq.n_size = d;
    program_seq.k_size = d;
    program_seq.precision = PREC_INT8;
    program_seq.post_op = POST_NONE;
    program_seq.sat_mode = SAT_WRAP;
    program_seq.a_base = A_BASE;
    program_seq.b_base = B_BASE;
    program_seq.c_base = C_BASE;
    program_seq.bias_base = 32'h0004_0000;
    program_seq.burst_len = 8'd4;
    program_seq.use_cfg_regions = 1'b1;
    program_seq.start(env.axi_system_env.sequencer);

    start_seq = tensor_start_seq::type_id::create("start_seq");
    start_seq.start(env.axi_system_env.sequencer);

    wait_seq = tensor_wait_done_seq::type_id::create("wait_seq");
    wait_seq.timeout_cycles = d * d * d * 20;
    wait_seq.expect_error = 1'b0;
    wait_seq.start(env.axi_system_env.sequencer);

    check_done_no_error();
    read_c_memory(d, actual_c);
    compare_c_memory(d, golden_c, actual_c);

    clear_seq = tensor_clear_status_seq::type_id::create("clear_seq");
    clear_seq.start(env.axi_system_env.sequencer);
    wait_for_status_clear();
  endtask

  virtual function void init_matrices(input int unsigned d,
                                      ref int signed a_data[],
                                      ref int signed b_data[],
                                      ref int signed golden_c[]);
    for (int row = 0; row < d; row++) begin
      for (int col = 0; col < d; col++) begin
        a_data[row * d + col] = int8_pattern(row, col, 3, 5);
        b_data[row * d + col] = int8_pattern(row, col, 7, 2);
      end
    end

    for (int row = 0; row < d; row++) begin
      for (int col = 0; col < d; col++) begin
        int signed acc;

        acc = 0;
        for (int kk = 0; kk < d; kk++) begin
          acc += a_data[row * d + kk] * b_data[kk * d + col];
        end
        golden_c[row * d + col] = acc;
      end
    end
  endfunction

  virtual task preload_input_memory(input int unsigned d,
                                    const ref int signed a_data[],
                                    const ref int signed b_data[]);
    bit [7:0] a_bytes[];
    bit [7:0] b_bytes[];

    a_bytes = new[d * d];
    b_bytes = new[d * d];

    for (int i = 0; i < d * d; i++) begin
      a_bytes[i] = int8_to_byte(a_data[i]);
      b_bytes[i] = int8_to_byte(b_data[i]);
    end

    env.axi_system_env.slave[0].write_num_byte(A_BASE, a_bytes.size(), a_bytes);
    env.axi_system_env.slave[0].write_num_byte(B_BASE, b_bytes.size(), b_bytes);
  endtask

  virtual task poison_c_memory(input int unsigned d);
    bit [7:0] c_bytes[];

    c_bytes = new[d * d * 4];
    foreach (c_bytes[i]) begin
      c_bytes[i] = 8'ha5;
    end
    env.axi_system_env.slave[0].write_num_byte(C_BASE, c_bytes.size(), c_bytes);
  endtask

  virtual task read_c_memory(input int unsigned d, ref int signed actual_c[]);
    bit [7:0] byte0;
    bit [7:0] byte1;
    bit [7:0] byte2;
    bit [7:0] byte3;
    bit signed [31:0] word_data;

    for (int i = 0; i < d * d; i++) begin
      env.axi_system_env.slave[0].read_byte(C_BASE + (i * 4) + 0, byte0);
      env.axi_system_env.slave[0].read_byte(C_BASE + (i * 4) + 1, byte1);
      env.axi_system_env.slave[0].read_byte(C_BASE + (i * 4) + 2, byte2);
      env.axi_system_env.slave[0].read_byte(C_BASE + (i * 4) + 3, byte3);
      word_data = {byte3, byte2, byte1, byte0};
      actual_c[i] = word_data;
    end
  endtask

  virtual task compare_c_memory(input int unsigned d,
                                const ref int signed golden_c[],
                                const ref int signed actual_c[]);
    for (int row = 0; row < d; row++) begin
      for (int col = 0; col < d; col++) begin
        int unsigned idx;

        idx = row * d + col;
        if (actual_c[idx] !== golden_c[idx]) begin
          `uvm_error(get_type_name(),
                     $sformatf("C[%0d,%0d] mismatch exp=%0d act=%0d",
                               row, col, golden_c[idx], actual_c[idx]))
          if (cfg != null) cfg.add_seq_check_error();
        end
        else if (cfg != null) begin
          cfg.add_seq_check_count();
        end
      end
    end
  endtask

  virtual task check_done_no_error();
    uvm_status_e status;
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;

    env.reg_model.STATUS.read(status, status_data, UVM_FRONTDOOR,
                              env.reg_model.default_map);
    if (status != UVM_IS_OK) begin
      `uvm_error(get_type_name(), "STATUS read failed")
      if (cfg != null) cfg.add_seq_check_error();
    end

    env.reg_model.ERROR_CODE.read(status, error_data, UVM_FRONTDOOR,
                                  env.reg_model.default_map);
    if (status != UVM_IS_OK) begin
      `uvm_error(get_type_name(), "ERROR_CODE read failed")
      if (cfg != null) cfg.add_seq_check_error();
    end

    if ((status_data[1] !== 1'b1) || (status_data[2] !== 1'b0)) begin
      `uvm_error(get_type_name(),
                 $sformatf("Expected done=1 error=0, STATUS=0x%08x",
                           status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (error_data[3:0] !== ERR_NO_ERROR) begin
      `uvm_error(get_type_name(),
                 $sformatf("Expected ERROR_CODE=0, got 0x%08x", error_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  virtual task wait_for_status_clear();
    if (cfg != null && cfg.vif != null) begin
      repeat (2) @(posedge cfg.vif.clk);
    end
  endtask

  virtual function int signed int8_pattern(input int unsigned row,
                                           input int unsigned col,
                                           input int unsigned row_mul,
                                           input int unsigned col_mul);
    int unsigned raw;

    raw = ((row * row_mul) + (col * col_mul) + (row ^ col)) % 9;
    return int'(raw) - 4;
  endfunction

  virtual function bit [7:0] int8_to_byte(int signed value);
    bit signed [7:0] signed_byte;

    signed_byte = value[7:0];
    return signed_byte[7:0];
  endfunction

  virtual function void final_phase(uvm_phase phase);
    uvm_report_server svr;
    super.final_phase(phase);
    svr = uvm_report_server::get_server();

    if ((svr.get_severity_count(UVM_FATAL) +
         svr.get_severity_count(UVM_ERROR)) == 0) begin
      `uvm_info("TEST_RESULT", $sformatf("%s PASSED", get_type_name()), UVM_LOW)
    end
    else begin
      `uvm_info("TEST_RESULT", $sformatf("%s FAILED", get_type_name()), UVM_LOW)
    end
  endfunction
endclass

class tensor_base_8x8_test extends tensor_base_square_tile_test_base;
  `uvm_component_utils(tensor_base_8x8_test)

  function new(string name = "tensor_base_8x8_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function int unsigned dim();
    return 8;
  endfunction
endclass

class tensor_base_16x16_test extends tensor_base_square_tile_test_base;
  `uvm_component_utils(tensor_base_16x16_test)

  function new(string name = "tensor_base_16x16_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function int unsigned dim();
    return 16;
  endfunction
endclass

class tensor_base_32x32_test extends tensor_base_square_tile_test_base;
  `uvm_component_utils(tensor_base_32x32_test)

  function new(string name = "tensor_base_32x32_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function int unsigned dim();
    return 32;
  endfunction
endclass

class tensor_base_64x64_test extends tensor_base_square_tile_test_base;
  `uvm_component_utils(tensor_base_64x64_test)

  function new(string name = "tensor_base_64x64_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function int unsigned dim();
    return 64;
  endfunction
endclass

`endif
