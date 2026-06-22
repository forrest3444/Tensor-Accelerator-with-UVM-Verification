`ifndef TENSOR_ACCEL_SATURATION_VSEQ_SV
`define TENSOR_ACCEL_SATURATION_VSEQ_SV

class tensor_saturation_vseq extends tensor_matmul_vseq;
  `uvm_object_utils(tensor_saturation_vseq)

  bit check_overflow_status;
  int signed bias_data[];

  function new(string name = "tensor_saturation_vseq");
    super.new(name);
    m_size = 4;
    n_size = 4;
    k_size = 4;
    precision = PREC_INT8;
    post_op = POST_BIAS;
    sat_mode = SAT_SATURATE;
    bias_base = 32'h0005_1000;
    timeout_cycles = 20000;
    check_overflow_status = 1'b0;
  endfunction

  virtual task body();
    bias_data = new[n_size];
    super.body();
  endtask

  virtual function void init_matrices(ref int signed a_data[],
                                      ref int signed b_data[],
                                      ref int signed golden_c[]);
    int signed a_init[16] = '{
       1,  1,  0,  0,
      -1, -1,  0,  0,
       1,  1,  0,  0,
      -1, -1,  0,  0
    };
    int signed b_init[16] = '{
      1, 1, 1, 1,
      1, 1, 1, 1,
      0, 0, 0, 0,
      0, 0, 0, 0
    };
    int signed bias_init[4] = '{32'sh7fff_ffff, 32'sh8000_0000, 10, -10};

    foreach (a_data[idx]) begin
      a_data[idx] = a_init[idx];
    end
    foreach (b_data[idx]) begin
      b_data[idx] = b_init[idx];
    end
    foreach (bias_data[col]) begin
      bias_data[col] = bias_init[col];
    end

    for (int row = 0; row < m_size; row++) begin
      for (int col = 0; col < n_size; col++) begin
        longint signed acc;

        acc = 0;
        for (int kk = 0; kk < k_size; kk++) begin
          acc += a_data[(row * k_size) + kk] * b_data[(kk * n_size) + col];
        end
        acc += bias_data[col];
        golden_c[(row * n_size) + col] =
            (sat_mode == SAT_SATURATE) ? clamp_int32(acc) : wrap_int32(acc);
      end
    end
  endfunction

  virtual task preload_input_memory(const ref int signed a_data[],
                                    const ref int signed b_data[]);
    bit [7:0] bias_bytes[];

    super.preload_input_memory(a_data, b_data);
    bias_bytes = new[n_size * 4];
    foreach (bias_data[col]) begin
      bit signed [31:0] word_data;

      word_data = bias_data[col];
      bias_bytes[(col * 4) + 0] = word_data[7:0];
      bias_bytes[(col * 4) + 1] = word_data[15:8];
      bias_bytes[(col * 4) + 2] = word_data[23:16];
      bias_bytes[(col * 4) + 3] = word_data[31:24];
    end
    foreach (bias_bytes[idx]) begin
      env.axi_system_env.slave[0].write_byte(bias_base + idx, bias_bytes[idx]);
    end
  endtask

  virtual task post_done_checks();
    if (check_overflow_status) begin
      check_overflow_accounting();
    end
  endtask

  virtual task check_overflow_accounting();
    uvm_reg_data_t status_data;
    uvm_reg_data_t ovf_count_data;
    uvm_reg_data_t error_data;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.OVF_COUNT, ovf_count_data);
    ral_read(reg_model.ERROR_CODE, error_data);

    if (status_data[4] !== 1'b1) begin
      `uvm_error(get_type_name(),
                 $sformatf("Expected overflow_seen=1, STATUS=0x%08x",
                           status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (ovf_count_data[31:0] == 32'd0) begin
      `uvm_error(get_type_name(), "Expected nonzero OVF_COUNT")
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if ((status_data[2] !== 1'b0) || (error_data[3:0] !== ERR_NO_ERROR)) begin
      `uvm_error(get_type_name(),
                 $sformatf("Overflow should not be fatal STATUS=0x%08x ERROR_CODE=0x%08x",
                           status_data[31:0], error_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  virtual function int signed clamp_int32(longint signed value);
    if (value > 64'sd2147483647) begin
      return 32'sh7fff_ffff;
    end
    if (value < -64'sd2147483648) begin
      return 32'sh8000_0000;
    end
    return int'(value);
  endfunction
endclass

`endif
