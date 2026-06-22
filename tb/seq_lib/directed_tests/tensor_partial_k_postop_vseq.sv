`ifndef TENSOR_PARTIAL_K_POSTOP_VSEQ_SV
`define TENSOR_PARTIAL_K_POSTOP_VSEQ_SV

class tensor_partial_k_postop_vseq extends tensor_matmul_vseq;
  `uvm_object_utils(tensor_partial_k_postop_vseq)

  int signed bias_data[];

  function new(string name = "tensor_partial_k_postop_vseq");
    super.new(name);
    m_size = 4;
    n_size = 2;
    k_size = 2;
    precision = PREC_INT8;
    post_op = POST_NONE;
    sat_mode = SAT_WRAP;
    burst_len = 8'd1;
    bias_base = 32'h0004_8000;
    timeout_cycles = 10000;
  endfunction

  virtual task body();
    bias_data = new[n_size];
    super.body();
  endtask

  virtual function void init_matrices(ref int signed a_data[],
                                      ref int signed b_data[],
                                      ref int signed golden_c[]);
    foreach (a_data[idx]) begin
      int unsigned row;
      int unsigned kk;

      row = idx / k_size;
      kk = idx % k_size;
      a_data[idx] = int'(((row * 5) + (kk * 3)) % 11) - 5;
    end

    foreach (b_data[idx]) begin
      int unsigned kk;
      int unsigned col;

      kk = idx / n_size;
      col = idx % n_size;
      b_data[idx] = int'(((kk * 7) + (col * 5)) % 9) - 4;
    end

    foreach (bias_data[col]) begin
      bias_data[col] = (col == 0) ? 2275 : -961;
    end

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
        golden_c[(row * n_size) + col] = wrap_int32(acc);
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
endclass

`endif
