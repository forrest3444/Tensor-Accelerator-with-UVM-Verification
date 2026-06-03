`ifndef TENSOR_ACCEL_BB_PRECISION_SWITCH_VSEQ_SV
`define TENSOR_ACCEL_BB_PRECISION_SWITCH_VSEQ_SV

class tensor_bb_precision_switch_vseq extends base_vseq;
  `uvm_object_utils(tensor_bb_precision_switch_vseq)

  function new(string name = "tensor_bb_precision_switch_vseq");
    super.new(name);
  endfunction

  virtual task body();
    for (int round = 0; round < 3; round++) begin
      run_precision_case(round, PREC_INT8);
      run_precision_case(round, PREC_INT16);
    end
  endtask

  virtual task run_precision_case(int unsigned round, precision_e precision);
    tensor_matmul_vseq matmul_seq;
    string precision_name;

    precision_name = (precision == PREC_INT16) ? "INT16" : "INT8";
    `uvm_info(get_type_name(),
              $sformatf("Round %0d running %s 4x4x4 matmul",
                        round, precision_name),
              UVM_MEDIUM)

    matmul_seq = tensor_matmul_vseq::type_id::create(
        $sformatf("matmul_%s_round_%0d", precision_name, round));
    matmul_seq.m_size = 32'd4;
    matmul_seq.n_size = 32'd4;
    matmul_seq.k_size = 32'd4;
    matmul_seq.precision = precision;
    matmul_seq.post_op = POST_NONE;
    matmul_seq.sat_mode = SAT_WRAP;
    matmul_seq.a_base = 32'h0001_0000;
    matmul_seq.b_base = 32'h0002_0000;
    matmul_seq.c_base = 32'h0003_0000;
    matmul_seq.bias_base = 32'h0004_0000;
    matmul_seq.burst_len = 8'd4;
    matmul_seq.timeout_cycles = 10000;
    matmul_seq.poll_interval_cycles = 100;
    matmul_seq.auto_clear_status = 1'b1;
    matmul_seq.start(p_sequencer);

    check_status_cleared(round, precision_name);
  endtask

  virtual task check_status_cleared(int unsigned round, string precision_name);
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    uvm_reg_data_t ovf_count_data;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.ERROR_CODE, error_data);
    ral_read(reg_model.OVF_COUNT, ovf_count_data);

    if ((status_data[31:0] &
         (STATUS_BUSY | STATUS_DONE | STATUS_ERROR | STATUS_IRQ |
          STATUS_OVERFLOW_SEEN)) != 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("Round %0d %s retained stale STATUS=0x%08x after clear",
                           round, precision_name, status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (error_data[3:0] != ERR_NO_ERROR) begin
      `uvm_error(get_type_name(),
                 $sformatf("Round %0d %s retained ERROR_CODE=0x%08x after clear",
                           round, precision_name, error_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (ovf_count_data[31:0] != 32'd0) begin
      `uvm_error(get_type_name(),
                 $sformatf("Round %0d %s unexpected OVF_COUNT=%0d",
                           round, precision_name, ovf_count_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask
endclass

`endif
