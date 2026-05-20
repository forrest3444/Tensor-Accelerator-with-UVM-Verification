`ifndef TENSOR_ACCEL_BASE_RECT_MATRIX_TEST_SV
`define TENSOR_ACCEL_BASE_RECT_MATRIX_TEST_SV

class tensor_base_rect_matrix_test extends base_test;
  `uvm_component_utils(tensor_base_rect_matrix_test)

  localparam bit [31:0] A_BASE = 32'h0001_0000;
  localparam bit [31:0] B_BASE = 32'h0002_0000;
  localparam bit [31:0] C_BASE = 32'h0003_0000;

  typedef struct {
    int unsigned m;
    int unsigned n;
    int unsigned k;
  } rect_case_t;

  function new(string name = "tensor_base_rect_matrix_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    rect_case_t cases[$];

    phase.raise_objection(this);
    wait_for_reset_done();

    cases.push_back('{m:4,  n:8,  k:16});
    cases.push_back('{m:8,  n:4,  k:12});
    cases.push_back('{m:13, n:7,  k:9});
    cases.push_back('{m:1,  n:64, k:3});
    cases.push_back('{m:64, n:1,  k:5});

    foreach (cases[idx]) begin
      run_rect_case(cases[idx], idx);
    end

    phase.drop_objection(this);
  endtask

  virtual task wait_for_reset_done();
    if (cfg != null && cfg.vif != null) begin
      @(posedge cfg.vif.rst_n);
      repeat (2) @(posedge cfg.vif.clk);
    end
  endtask

  virtual task run_rect_case(rect_case_t test_case, int unsigned case_idx);
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    tensor_wait_done_seq wait_seq;
    tensor_clear_status_seq clear_seq;
    int signed a_data[];
    int signed b_data[];
    int signed golden_c[];
    int signed actual_c[];

    a_data = new[test_case.m * test_case.k];
    b_data = new[test_case.k * test_case.n];
    golden_c = new[test_case.m * test_case.n];
    actual_c = new[test_case.m * test_case.n];

    `uvm_info(get_type_name(),
              $sformatf("Running rectangular case[%0d] M=%0d N=%0d K=%0d",
                        case_idx, test_case.m, test_case.n, test_case.k),
              UVM_MEDIUM)

    init_matrices(test_case, a_data, b_data, golden_c);
    preload_input_memory(test_case, a_data, b_data);
    poison_c_memory(test_case);

    program_seq = tensor_program_seq::type_id::create($sformatf("program_seq_case%0d",
                                                                case_idx));
    program_seq.m_size = test_case.m;
    program_seq.n_size = test_case.n;
    program_seq.k_size = test_case.k;
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

    start_seq = tensor_start_seq::type_id::create($sformatf("start_seq_case%0d",
                                                            case_idx));
    start_seq.start(env.axi_system_env.sequencer);

    wait_seq = tensor_wait_done_seq::type_id::create($sformatf("wait_seq_case%0d",
                                                               case_idx));
    wait_seq.timeout_cycles = test_case.m * test_case.n * test_case.k * 40 + 10000;
    wait_seq.expect_error = 1'b0;
    wait_seq.start(env.axi_system_env.sequencer);

    check_done_no_error(case_idx);
    read_c_memory(test_case, actual_c);
    compare_c_memory(test_case, golden_c, actual_c, case_idx);

    clear_seq = tensor_clear_status_seq::type_id::create($sformatf("clear_seq_case%0d",
                                                                   case_idx));
    clear_seq.start(env.axi_system_env.sequencer);
    wait_for_status_clear();
  endtask

  virtual function void init_matrices(rect_case_t test_case,
                                      ref int signed a_data[],
                                      ref int signed b_data[],
                                      ref int signed golden_c[]);
    for (int row = 0; row < test_case.m; row++) begin
      for (int kk = 0; kk < test_case.k; kk++) begin
        a_data[(row * test_case.k) + kk] = int8_pattern(row, kk, 3, 5);
      end
    end

    for (int kk = 0; kk < test_case.k; kk++) begin
      for (int col = 0; col < test_case.n; col++) begin
        b_data[(kk * test_case.n) + col] = int8_pattern(kk, col, 7, 2);
      end
    end

    for (int row = 0; row < test_case.m; row++) begin
      for (int col = 0; col < test_case.n; col++) begin
        int signed acc;

        acc = 0;
        for (int kk = 0; kk < test_case.k; kk++) begin
          acc += a_data[(row * test_case.k) + kk] *
                 b_data[(kk * test_case.n) + col];
        end
        golden_c[(row * test_case.n) + col] = acc;
      end
    end
  endfunction

  virtual task preload_input_memory(rect_case_t test_case,
                                    const ref int signed a_data[],
                                    const ref int signed b_data[]);
    bit [7:0] a_bytes[];
    bit [7:0] b_bytes[];

    a_bytes = new[test_case.m * test_case.k];
    b_bytes = new[test_case.k * test_case.n];

    foreach (a_bytes[i]) begin
      a_bytes[i] = int8_to_byte(a_data[i]);
    end
    foreach (b_bytes[i]) begin
      b_bytes[i] = int8_to_byte(b_data[i]);
    end

    env.axi_system_env.slave[0].write_num_byte(A_BASE, a_bytes.size(), a_bytes);
    env.axi_system_env.slave[0].write_num_byte(B_BASE, b_bytes.size(), b_bytes);
  endtask

  virtual task poison_c_memory(rect_case_t test_case);
    bit [7:0] c_bytes[];

    c_bytes = new[test_case.m * test_case.n * 4];
    foreach (c_bytes[i]) begin
      c_bytes[i] = 8'ha5;
    end
    env.axi_system_env.slave[0].write_num_byte(C_BASE, c_bytes.size(), c_bytes);
  endtask

  virtual task read_c_memory(rect_case_t test_case, ref int signed actual_c[]);
    bit [7:0] c_bytes[];
    bit signed [31:0] word_data;

    c_bytes = new[test_case.m * test_case.n * 4];
    env.axi_system_env.slave[0].read_num_byte(C_BASE, c_bytes.size(), c_bytes);

    for (int idx = 0; idx < test_case.m * test_case.n; idx++) begin
      word_data = {c_bytes[(idx * 4) + 3], c_bytes[(idx * 4) + 2],
                   c_bytes[(idx * 4) + 1], c_bytes[(idx * 4) + 0]};
      actual_c[idx] = word_data;
    end
  endtask

  virtual task compare_c_memory(rect_case_t test_case,
                                const ref int signed golden_c[],
                                const ref int signed actual_c[],
                                int unsigned case_idx);
    for (int row = 0; row < test_case.m; row++) begin
      for (int col = 0; col < test_case.n; col++) begin
        int unsigned idx;

        idx = (row * test_case.n) + col;
        if (actual_c[idx] !== golden_c[idx]) begin
          `uvm_error(get_type_name(),
                     $sformatf("case[%0d] M=%0d N=%0d K=%0d C[%0d,%0d] mismatch exp=%0d act=%0d",
                               case_idx, test_case.m, test_case.n, test_case.k,
                               row, col, golden_c[idx], actual_c[idx]))
          if (cfg != null) cfg.add_seq_check_error();
        end
        else if (cfg != null) begin
          cfg.add_seq_check_count();
        end
      end
    end
  endtask

  virtual task check_done_no_error(int unsigned case_idx);
    uvm_status_e status;
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;

    env.reg_model.STATUS.read(status, status_data, UVM_FRONTDOOR,
                              env.reg_model.default_map);
    if (status != UVM_IS_OK) begin
      `uvm_error(get_type_name(), $sformatf("case[%0d] STATUS read failed", case_idx))
      if (cfg != null) cfg.add_seq_check_error();
    end

    env.reg_model.ERROR_CODE.read(status, error_data, UVM_FRONTDOOR,
                                  env.reg_model.default_map);
    if (status != UVM_IS_OK) begin
      `uvm_error(get_type_name(), $sformatf("case[%0d] ERROR_CODE read failed", case_idx))
      if (cfg != null) cfg.add_seq_check_error();
    end

    if ((status_data[1] !== 1'b1) || (status_data[2] !== 1'b0)) begin
      `uvm_error(get_type_name(),
                 $sformatf("case[%0d] expected done=1 error=0, STATUS=0x%08x",
                           case_idx, status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (error_data[3:0] !== ERR_NO_ERROR) begin
      `uvm_error(get_type_name(),
                 $sformatf("case[%0d] expected ERROR_CODE=0, got 0x%08x",
                           case_idx, error_data[31:0]))
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

`endif
