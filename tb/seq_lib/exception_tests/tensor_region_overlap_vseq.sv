`ifndef TENSOR_REGION_OVERLAP_VSEQ_SV
`define TENSOR_REGION_OVERLAP_VSEQ_SV

class tensor_region_overlap_vseq extends base_vseq;
  `uvm_object_utils(tensor_region_overlap_vseq)

  typedef struct packed {
    bit [31:0] a_spad_offset;
    bit [31:0] a_spad_size;
    bit [31:0] b_spad_offset;
    bit [31:0] b_spad_size;
    bit [31:0] c_spad_offset;
    bit [31:0] c_spad_size;
    bit [31:0] bias_spad_offset;
    bit [31:0] bias_spad_size;
    post_op_e  post_op;
  } overlap_case_t;

  function new(string name = "tensor_region_overlap_vseq");
    super.new(name);
  endfunction

  virtual task body();
    overlap_case_t overlap_cases[$];

    overlap_cases.push_back('{32'h0000_0000, 32'h0000_1000,
                              32'h0000_0800, 32'h0000_1000,
                              32'h0000_3000, 32'h0000_1000,
                              32'h0000_5000, 32'h0000_1000,
                              POST_NONE});
    overlap_cases.push_back('{32'h0000_0000, 32'h0000_0800,
                              32'h0000_2000, 32'h0000_1000,
                              32'h0000_2800, 32'h0000_1000,
                              32'h0000_5000, 32'h0000_1000,
                              POST_NONE});
    overlap_cases.push_back('{32'h0000_0000, 32'h0000_0800,
                              32'h0000_2000, 32'h0000_1000,
                              32'h0000_4000, 32'h0000_1000,
                              32'h0000_4800, 32'h0000_1000,
                              POST_BIAS});

    foreach (overlap_cases[i]) begin
      run_overlap_case(overlap_cases[i]);
    end
  endtask

  protected virtual task run_overlap_case(overlap_case_t overlap_case);
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    tensor_wait_done_seq wait_seq;
    tensor_clear_status_seq clear_seq;

    `uvm_info(get_type_name(),
              $sformatf("Running region overlap case A=[0x%08x,+0x%08x) B=[0x%08x,+0x%08x) C=[0x%08x,+0x%08x) BIAS=[0x%08x,+0x%08x) post_op=%0d",
                        overlap_case.a_spad_offset, overlap_case.a_spad_size,
                        overlap_case.b_spad_offset, overlap_case.b_spad_size,
                        overlap_case.c_spad_offset, overlap_case.c_spad_size,
                        overlap_case.bias_spad_offset, overlap_case.bias_spad_size,
                        overlap_case.post_op),
              UVM_MEDIUM)

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.use_cfg_regions = 1'b0;
    program_seq.m_size = 32'd4;
    program_seq.n_size = 32'd4;
    program_seq.k_size = 32'd4;
    program_seq.precision = PREC_INT8;
    program_seq.post_op = overlap_case.post_op;
    program_seq.sat_mode = SAT_WRAP;
    program_seq.a_base = 32'h0001_0000;
    program_seq.b_base = 32'h0002_0000;
    program_seq.c_base = 32'h0003_0000;
    program_seq.bias_base = 32'h0004_0000;
    program_seq.a_spad_offset = overlap_case.a_spad_offset;
    program_seq.a_spad_size = overlap_case.a_spad_size;
    program_seq.b_spad_offset = overlap_case.b_spad_offset;
    program_seq.b_spad_size = overlap_case.b_spad_size;
    program_seq.c_spad_offset = overlap_case.c_spad_offset;
    program_seq.c_spad_size = overlap_case.c_spad_size;
    program_seq.bias_spad_offset = overlap_case.bias_spad_offset;
    program_seq.bias_spad_size = overlap_case.bias_spad_size;
    program_seq.burst_len = 8'd16;
    program_seq.start(p_sequencer);

    start_seq = tensor_start_seq::type_id::create("start_seq");
    start_seq.start(p_sequencer);

    wait_seq = tensor_wait_done_seq::type_id::create("wait_seq");
    wait_seq.timeout_cycles = 1000;
    wait_seq.poll_interval_cycles = 10;
    wait_seq.expect_error = 1'b1;
    wait_seq.check_error_code = 1'b1;
    wait_seq.exp_error_code = ERR_REGION_OVERLAP;
    wait_seq.start(p_sequencer);

    check_error_state();

    clear_seq = tensor_clear_status_seq::type_id::create("clear_seq");
    clear_seq.start(p_sequencer);
  endtask

  protected virtual task check_error_state();
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    error_code_e actual_error_code;
    error_code_e expected_error_code;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.ERROR_CODE, error_data);
    actual_error_code = error_code_e'(error_data[3:0]);
    expected_error_code = ERR_REGION_OVERLAP;

    if ((status_data[31:0] & STATUS_ERROR) == 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("STATUS.error was not set; STATUS=0x%08x", status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (actual_error_code != ERR_REGION_OVERLAP) begin
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

`endif
