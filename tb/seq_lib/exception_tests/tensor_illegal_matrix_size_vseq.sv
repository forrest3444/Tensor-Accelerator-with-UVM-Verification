`ifndef TENSOR_ILLEGAL_MATRIX_SIZE_VSEQ_SV
`define TENSOR_ILLEGAL_MATRIX_SIZE_VSEQ_SV

class tensor_illegal_matrix_size_vseq extends base_vseq;
  `uvm_object_utils(tensor_illegal_matrix_size_vseq)

  typedef struct packed {
    bit [31:0] m_size;
    bit [31:0] n_size;
    bit [31:0] k_size;
  } illegal_size_case_t;

  localparam bit [31:0] A_BASE    = 32'h0001_0000;
  localparam bit [31:0] B_BASE    = 32'h0002_0000;
  localparam bit [31:0] C_BASE    = 32'h0003_0000;
  localparam bit [31:0] BIAS_BASE = 32'h0004_0000;

  function new(string name = "tensor_illegal_matrix_size_vseq");
    super.new(name);
  endfunction

  virtual task body();
    illegal_size_case_t illegal_cases[$];

    illegal_cases.push_back('{32'd0,  32'd4,  32'd4});
    illegal_cases.push_back('{32'd4,  32'd0,  32'd4});
    illegal_cases.push_back('{32'd4,  32'd4,  32'd0});
    illegal_cases.push_back('{32'd65, 32'd4,  32'd4});
    illegal_cases.push_back('{32'd4,  32'd65, 32'd4});
    illegal_cases.push_back('{32'd4,  32'd4,  32'd65});

    foreach (illegal_cases[i]) begin
      run_illegal_case(illegal_cases[i]);
    end
  endtask

  protected virtual task run_illegal_case(illegal_size_case_t illegal_case);
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    tensor_wait_done_seq wait_seq;
    tensor_clear_status_seq clear_seq;
    bit terminal_seen;
    bit dma_seen;

    `uvm_info(get_type_name(),
              $sformatf("Running illegal matrix size case M=%0d N=%0d K=%0d",
                        illegal_case.m_size, illegal_case.n_size, illegal_case.k_size),
              UVM_MEDIUM)

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.m_size = illegal_case.m_size;
    program_seq.n_size = illegal_case.n_size;
    program_seq.k_size = illegal_case.k_size;
    program_seq.precision = PREC_INT8;
    program_seq.post_op = POST_NONE;
    program_seq.sat_mode = SAT_WRAP;
    program_seq.a_base = A_BASE;
    program_seq.b_base = B_BASE;
    program_seq.c_base = C_BASE;
    program_seq.bias_base = BIAS_BASE;
    program_seq.burst_len = 8'd16;
    program_seq.start(p_sequencer);

    terminal_seen = 1'b0;
    dma_seen = 1'b0;

    fork
      begin
        while (!terminal_seen) begin
          if (dma_request_active()) begin
            dma_seen = 1'b1;
          end
          wait_cfg_clocks(1);
          if (dma_request_active()) begin
            dma_seen = 1'b1;
          end
        end
      end
      begin
        start_seq = tensor_start_seq::type_id::create("start_seq");
        start_seq.start(p_sequencer);

        wait_seq = tensor_wait_done_seq::type_id::create("wait_seq");
        wait_seq.timeout_cycles = 1000;
        wait_seq.poll_interval_cycles = 10;
        wait_seq.expect_error = 1'b1;
        wait_seq.check_error_code = 1'b1;
        wait_seq.exp_error_code = ERR_ILLEGAL_MATRIX_SIZE;
        wait_seq.start(p_sequencer);
        terminal_seen = 1'b1;
      end
    join

    repeat (4) begin
      wait_cfg_clocks(1);
      if (dma_request_active()) begin
        dma_seen = 1'b1;
      end
    end

    check_error_state();
    check_no_dma_access(dma_seen, illegal_case);

    clear_seq = tensor_clear_status_seq::type_id::create("clear_seq");
    clear_seq.start(p_sequencer);
  endtask

  protected virtual function bit dma_request_active();
    if (cfg == null || cfg.axi_slave_vif == null) begin
      return 1'b0;
    end

    return (cfg.axi_slave_vif.arvalid === 1'b1) ||
           (cfg.axi_slave_vif.awvalid === 1'b1) ||
           (cfg.axi_slave_vif.wvalid  === 1'b1);
  endfunction

  protected virtual task check_error_state();
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    error_code_e actual_error_code;
    error_code_e expected_error_code;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.ERROR_CODE, error_data);
    actual_error_code = error_code_e'(error_data[3:0]);
    expected_error_code = ERR_ILLEGAL_MATRIX_SIZE;

    if ((status_data[31:0] & STATUS_ERROR) == 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("STATUS.error was not set; STATUS=0x%08x", status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (actual_error_code != ERR_ILLEGAL_MATRIX_SIZE) begin
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

  protected virtual function void check_no_dma_access(bit dma_seen,
                                                      illegal_size_case_t illegal_case);
    if (dma_seen) begin
      `uvm_error(get_type_name(),
                 $sformatf("Unexpected DMA access for illegal matrix size M=%0d N=%0d K=%0d",
                           illegal_case.m_size, illegal_case.n_size, illegal_case.k_size))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endfunction
endclass

`endif
