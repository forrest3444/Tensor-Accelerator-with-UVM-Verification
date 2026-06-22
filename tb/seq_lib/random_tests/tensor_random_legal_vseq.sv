`ifndef TENSOR_ACCEL_RANDOM_LEGAL_VSEQ_SV
`define TENSOR_ACCEL_RANDOM_LEGAL_VSEQ_SV

class tensor_random_legal_vseq extends tensor_matmul_vseq;
  `uvm_object_utils(tensor_random_legal_vseq)

  rand bit [5:0] a_base_slot;
  rand bit [5:0] b_base_slot;
  rand bit [5:0] c_base_slot;
  rand bit [5:0] bias_base_slot;

  int signed bias_data[];

  localparam bit [31:0] EXT_SLOT_BYTES  = 32'h0000_4000;

  constraint c_random_legal_dims {
    m_size inside {[1:64]};
    n_size inside {[1:64]};
    k_size inside {1, 2, 4, 8, 16, 32, 64};
  }

  constraint c_random_legal_modes {
    precision inside {PREC_INT8, PREC_INT16};
    post_op inside {POST_NONE, POST_BIAS, POST_RELU, POST_BIAS_RELU};
    sat_mode inside {SAT_WRAP, SAT_SATURATE};
    burst_len inside {8'd1, 8'd4, 8'd8, 8'd16};
  }

  constraint c_random_legal_bases {
    a_base_slot inside {[1:60]};
    b_base_slot inside {[1:60]};
    c_base_slot inside {[1:60]};
    bias_base_slot inside {[1:60]};
    a_base_slot != b_base_slot;
    a_base_slot != c_base_slot;
    a_base_slot != bias_base_slot;
    b_base_slot != c_base_slot;
    b_base_slot != bias_base_slot;
    c_base_slot != bias_base_slot;
    a_base == (a_base_slot * EXT_SLOT_BYTES);
    b_base == (b_base_slot * EXT_SLOT_BYTES);
    c_base == (c_base_slot * EXT_SLOT_BYTES);
    bias_base == (bias_base_slot * EXT_SLOT_BYTES);
  }

  constraint c_random_legal_runtime {
    timeout_cycles == 0;
    poll_interval_cycles == 1000;
  }

  function new(string name = "tensor_random_legal_vseq");
    super.new(name);
  endfunction

  virtual task body();
    bias_data = new[n_size];
    apply_random_cfg();
    `uvm_info(get_type_name(),
              $sformatf("Random legal case M=%0d N=%0d K=%0d precision=%0d post_op=%0d sat=%0d burst_len=%0d A=0x%08x B=0x%08x C=0x%08x Bias=0x%08x",
                        m_size, n_size, k_size, precision, post_op, sat_mode, burst_len,
                        a_base, b_base, c_base, bias_base),
              UVM_LOW)
    super.body();
  endtask

  virtual function void apply_random_cfg();
    if (cfg == null) begin
      return;
    end

    cfg.vip_cfg.max_burst_len = burst_len;
  endfunction

  virtual function int unsigned effective_timeout_cycles();
    return int'(m_size * n_size * k_size * 80) + 50000;
  endfunction

  virtual function void init_matrices(ref int signed a_data[],
                                      ref int signed b_data[],
                                      ref int signed golden_c[]);
    foreach (a_data[idx]) begin
      a_data[idx] = random_operand();
    end

    foreach (b_data[idx]) begin
      b_data[idx] = random_operand();
    end

    foreach (bias_data[col]) begin
      bias_data[col] = random_bias();
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
        if (bias_enabled(post_op)) begin
          acc += bias_data[col];
        end
        if (relu_enabled(post_op) && acc < 0) begin
          acc = 0;
        end
        golden_c[(row * n_size) + col] =
            (sat_mode == SAT_SATURATE) ? clamp_int32(acc) : wrap_int32(acc);
      end
    end
  endfunction

  virtual task preload_input_memory(const ref int signed a_data[],
                                    const ref int signed b_data[]);
    bit [7:0] bias_bytes[];

    super.preload_input_memory(a_data, b_data);
    if (!bias_enabled(post_op)) begin
      return;
    end

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

  virtual function int signed random_operand();
    if (precision == PREC_INT16) begin
      return int'($urandom_range(0, 2047)) - 1024;
    end
    return int'($urandom_range(0, 255)) - 128;
  endfunction

  virtual function int signed random_bias();
    return int'($urandom_range(0, 8191)) - 4096;
  endfunction

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
