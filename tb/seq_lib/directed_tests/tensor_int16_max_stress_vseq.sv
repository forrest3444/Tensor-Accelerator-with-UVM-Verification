`ifndef TENSOR_ACCEL_INT16_MAX_STRESS_VSEQ_SV
`define TENSOR_ACCEL_INT16_MAX_STRESS_VSEQ_SV

class tensor_int16_max_stress_vseq extends tensor_bias_vseq;
  `uvm_object_utils(tensor_int16_max_stress_vseq)

  function new(string name = "tensor_int16_max_stress_vseq");
    super.new(name);
    m_size = 32'd64;
    n_size = 32'd64;
    k_size = 32'd64;
    precision = PREC_INT16;
    post_op = POST_BIAS_RELU;
    sat_mode = SAT_SATURATE;
    burst_len = 8'd16;
    timeout_cycles = 64 * 64 * 64 * 80;
    poll_interval_cycles = 1000;
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

    foreach (bias_data[col]) begin
      bias_data[col] = int'($urandom_range(0, 65535)) - 32768;
    end

    compute_bias_relu_saturating_reference(a_data, b_data, golden_c);
  endfunction

  virtual function void compute_bias_relu_saturating_reference(
      const ref int signed a_data[],
      const ref int signed b_data[],
      ref int signed golden_c[]);
    for (int row = 0; row < m_size; row++) begin
      for (int col = 0; col < n_size; col++) begin
        longint signed acc;

        acc = 0;
        for (int kk = 0; kk < k_size; kk++) begin
          acc += a_data[(row * k_size) + kk] * b_data[(kk * n_size) + col];
        end

        acc = wrap_int32(acc);
        acc += bias_data[col];
        if (acc < 0) begin
          acc = 0;
        end
        golden_c[(row * n_size) + col] = clamp_int32(acc);
      end
    end
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
