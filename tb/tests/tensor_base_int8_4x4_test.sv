`ifndef TENSOR_ACCEL_BASE_INT8_4X4_TEST_SV
`define TENSOR_ACCEL_BASE_INT8_4X4_TEST_SV

class tensor_base_int8_4x4_test extends base_test;
  `uvm_component_utils(tensor_base_int8_4x4_test)

  localparam bit [31:0] A_BASE = 32'h0001_0000;
  localparam bit [31:0] B_BASE = 32'h0002_0000;
  localparam bit [31:0] C_BASE = 32'h0003_0000;
  localparam int unsigned DIM = 4;
  localparam int unsigned C_BYTES = DIM * DIM * 4;

  function new(string name = "tensor_base_int8_4x4_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit [7:0] burst_lens[$];

    phase.raise_objection(this);
    wait_for_reset_done();

    burst_lens.push_back(8'd1);
    burst_lens.push_back(8'd4);

    foreach (burst_lens[idx]) begin
      run_int8_4x4_smoke(burst_lens[idx]);
    end

    phase.drop_objection(this);
  endtask

  virtual task wait_for_reset_done();
    if (cfg != null && cfg.vif != null) begin
      @(posedge cfg.vif.rst_n);
      repeat (2) @(posedge cfg.vif.clk);
    end
  endtask

  virtual task run_int8_4x4_smoke(bit [7:0] burst_len);
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    tensor_wait_done_seq wait_seq;
    tensor_clear_status_seq clear_seq;
    int signed a_data[DIM * DIM];
    int signed b_data[DIM * DIM];
    int signed golden_c[DIM * DIM];
    int signed actual_c[DIM * DIM];

    init_matrices(a_data, b_data, golden_c);
    preload_input_memory(a_data, b_data);
    poison_c_memory();

    program_seq = tensor_program_seq::type_id::create($sformatf("program_seq_burst%0d",
                                                                burst_len));
    program_seq.m_size = DIM;
    program_seq.n_size = DIM;
    program_seq.k_size = DIM;
    program_seq.precision = PREC_INT8;
    program_seq.post_op = POST_NONE;
    program_seq.sat_mode = SAT_WRAP;
    program_seq.a_base = A_BASE;
    program_seq.b_base = B_BASE;
    program_seq.c_base = C_BASE;
    program_seq.bias_base = 32'h0004_0000;
    program_seq.burst_len = burst_len;
    program_seq.use_cfg_regions = 1'b1;
    program_seq.start(env.axi_system_env.sequencer);

    start_seq = tensor_start_seq::type_id::create($sformatf("start_seq_burst%0d",
                                                            burst_len));
    start_seq.start(env.axi_system_env.sequencer);

    wait_seq = tensor_wait_done_seq::type_id::create($sformatf("wait_seq_burst%0d",
                                                               burst_len));
    wait_seq.timeout_cycles = 10000;
    wait_seq.expect_error = 1'b0;
    wait_seq.start(env.axi_system_env.sequencer);

    check_done_no_error();
    read_c_memory(actual_c);
    compare_c_memory(golden_c, actual_c, burst_len);

    clear_seq = tensor_clear_status_seq::type_id::create($sformatf("clear_seq_burst%0d",
                                                                   burst_len));
    clear_seq.start(env.axi_system_env.sequencer);
    wait_for_status_clear();
  endtask

  virtual function void init_matrices(ref int signed a_data[DIM * DIM],
                                      ref int signed b_data[DIM * DIM],
                                      ref int signed golden_c[DIM * DIM]);
    int signed a_init[DIM * DIM] = '{
       1,  -2,   3,   4,
      -5,   6,   7,  -8,
       9,  10, -11,  12,
      13, -14,  15,  16
    };
    int signed b_init[DIM * DIM] = '{
       2,   0,  -1,   3,
      -4,   5,   6,  -7,
       8,  -9,  10,  11,
      12,  13, -14,  15
    };

    for (int i = 0; i < DIM * DIM; i++) begin
      a_data[i] = a_init[i];
      b_data[i] = b_init[i];
    end

    for (int row = 0; row < DIM; row++) begin
      for (int col = 0; col < DIM; col++) begin
        int signed acc;

        acc = 0;
        for (int kk = 0; kk < DIM; kk++) begin
          acc += a_data[row * DIM + kk] * b_data[kk * DIM + col];
        end
        golden_c[row * DIM + col] = acc;
      end
    end
  endfunction

  virtual task preload_input_memory(const ref int signed a_data[DIM * DIM],
                                    const ref int signed b_data[DIM * DIM]);
    bit [7:0] a_bytes[];
    bit [7:0] b_bytes[];

    a_bytes = new[DIM * DIM];
    b_bytes = new[DIM * DIM];

    for (int i = 0; i < DIM * DIM; i++) begin
      a_bytes[i] = int8_to_byte(a_data[i]);
      b_bytes[i] = int8_to_byte(b_data[i]);
    end

    env.axi_system_env.slave[0].write_num_byte(A_BASE, a_bytes.size(), a_bytes);
    env.axi_system_env.slave[0].write_num_byte(B_BASE, b_bytes.size(), b_bytes);
  endtask

  virtual task poison_c_memory();
    bit [7:0] c_bytes[];

    c_bytes = new[C_BYTES];
    foreach (c_bytes[i]) begin
      c_bytes[i] = 8'ha5;
    end
    env.axi_system_env.slave[0].write_num_byte(C_BASE, c_bytes.size(), c_bytes);
  endtask

  virtual task read_c_memory(ref int signed actual_c[DIM * DIM]);
    bit [7:0] c_bytes[];
    bit signed [31:0] word_data;

    c_bytes = new[C_BYTES];
    env.axi_system_env.slave[0].read_num_byte(C_BASE, c_bytes.size(), c_bytes);

    for (int i = 0; i < DIM * DIM; i++) begin
      word_data = {c_bytes[(i * 4) + 3], c_bytes[(i * 4) + 2],
                   c_bytes[(i * 4) + 1], c_bytes[(i * 4) + 0]};
      actual_c[i] = word_data;
    end
  endtask

  virtual task compare_c_memory(const ref int signed golden_c[DIM * DIM],
                                const ref int signed actual_c[DIM * DIM],
                                bit [7:0] burst_len);
    for (int i = 0; i < DIM * DIM; i++) begin
      if (actual_c[i] !== golden_c[i]) begin
        `uvm_error(get_type_name(),
                   $sformatf("burst_len=%0d C[%0d] mismatch exp=%0d act=%0d",
                             burst_len, i, golden_c[i], actual_c[i]))
        if (cfg != null) cfg.add_seq_check_error();
      end
      else if (cfg != null) begin
        cfg.add_seq_check_count();
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
      `uvm_info("TEST_RESULT", "tensor_base_int8_4x4_test PASSED", UVM_LOW)
    end
    else begin
      `uvm_info("TEST_RESULT", "tensor_base_int8_4x4_test FAILED", UVM_LOW)
    end
  endfunction
endclass

`endif
