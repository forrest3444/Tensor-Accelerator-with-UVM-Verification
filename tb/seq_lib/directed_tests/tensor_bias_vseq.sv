`ifndef TENSOR_ACCEL_BIAS_VSEQ_SV
`define TENSOR_ACCEL_BIAS_VSEQ_SV

class tensor_bias_vseq extends tensor_matmul_vseq;
  `uvm_object_utils(tensor_bias_vseq)

  int signed bias_data[];

  function new(string name = "tensor_bias_vseq");
    super.new(name);
    post_op = POST_BIAS;
    bias_base = 32'h0005_0080;
  endfunction

  virtual task body();
    bias_data = new[n_size];
    super.body();
  endtask

  virtual function void init_matrices(ref int signed a_data[],
                                      ref int signed b_data[],
                                      ref int signed golden_c[]);
    super.init_matrices(a_data, b_data, golden_c);

    foreach (bias_data[col]) begin
      bias_data[col] = int'($urandom_range(0, 63)) - 31;
    end

    for (int row = 0; row < m_size; row++) begin
      for (int col = 0; col < n_size; col++) begin
        longint signed acc;

        acc = golden_c[(row * n_size) + col];
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
    env.axi_system_env.slave[0].write_num_byte(bias_base, bias_bytes.size(), bias_bytes);
  endtask
endclass

`endif
