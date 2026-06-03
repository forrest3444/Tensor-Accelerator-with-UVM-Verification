`ifndef TENSOR_ACCEL_NON_ALIGNED_VSEQ_SV
`define TENSOR_ACCEL_NON_ALIGNED_VSEQ_SV

class tensor_non_aligned_vseq extends tensor_matmul_vseq;
  `uvm_object_utils(tensor_non_aligned_vseq)

  localparam int unsigned C_EXTRA_GUARD_WORDS = 16;
  localparam int unsigned INPUT_GUARD_BYTES = 256;
  localparam bit [31:0] C_POISON_WORD = 32'ha5a5_a5a5;
  localparam bit [7:0] INPUT_POISON_BYTE = 8'h6d;

  int unsigned case_idx;

  function new(string name = "tensor_non_aligned_vseq");
    super.new(name);
    precision = PREC_INT8;
    case_idx = 0;
  endfunction

  virtual function int unsigned effective_timeout_cycles();
    int unsigned base_timeout;

    base_timeout = super.effective_timeout_cycles();
    return (base_timeout < 20000) ? 20000 : base_timeout;
  endfunction

  virtual task preload_input_memory(const ref int signed a_data[],
                                    const ref int signed b_data[]);
    bit [7:0] a_bytes[];
    bit [7:0] b_bytes[];
    int unsigned a_active_bytes;
    int unsigned b_active_bytes;

    a_active_bytes = m_size * k_size;
    b_active_bytes = k_size * n_size;
    a_bytes = new[a_active_bytes + INPUT_GUARD_BYTES];
    b_bytes = new[b_active_bytes + INPUT_GUARD_BYTES];

    foreach (a_bytes[i]) begin
      a_bytes[i] = (i < a_active_bytes) ? int8_to_byte(a_data[i]) : INPUT_POISON_BYTE;
    end
    foreach (b_bytes[i]) begin
      b_bytes[i] = (i < b_active_bytes) ? int8_to_byte(b_data[i]) : INPUT_POISON_BYTE;
    end

    env.axi_system_env.slave[0].write_num_byte(a_base, a_bytes.size(), a_bytes);
    env.axi_system_env.slave[0].write_num_byte(b_base, b_bytes.size(), b_bytes);
  endtask

  virtual task poison_c_memory();
    bit [7:0] c_bytes[];
    int unsigned word_count;

    word_count = c_guard_word_count();
    c_bytes = new[word_count * 4];
    for (int unsigned idx = 0; idx < word_count; idx++) begin
      c_bytes[(idx * 4) + 0] = C_POISON_WORD[7:0];
      c_bytes[(idx * 4) + 1] = C_POISON_WORD[15:8];
      c_bytes[(idx * 4) + 2] = C_POISON_WORD[23:16];
      c_bytes[(idx * 4) + 3] = C_POISON_WORD[31:24];
    end

    env.axi_system_env.slave[0].write_num_byte(c_base, c_bytes.size(), c_bytes);
  endtask

  virtual task compare_c_memory(const ref int signed golden_c[],
                                const ref int signed actual_c[]);
    super.compare_c_memory(golden_c, actual_c);
    check_c_guard_region();
  endtask

  virtual task check_c_guard_region();
    bit [7:0] c_bytes[];
    bit [31:0] word_data;
    int unsigned active_words;
    int unsigned word_count;

    active_words = m_size * n_size;
    word_count = c_guard_word_count();
    c_bytes = new[word_count * 4];
    env.axi_system_env.slave[0].read_num_byte(c_base, c_bytes.size(), c_bytes);

    for (int unsigned idx = active_words; idx < word_count; idx++) begin
      word_data = {c_bytes[(idx * 4) + 3], c_bytes[(idx * 4) + 2],
                   c_bytes[(idx * 4) + 1], c_bytes[(idx * 4) + 0]};
      if (word_data !== C_POISON_WORD) begin
        `uvm_error(get_type_name(),
                   $sformatf("case[%0d] M=%0d N=%0d K=%0d invalid C word[%0d] was written, exp=0x%08x act=0x%08x",
                             case_idx, m_size, n_size, k_size, idx,
                             C_POISON_WORD, word_data))
        if (cfg != null) cfg.add_seq_check_error();
      end else if (cfg != null) begin
        cfg.add_seq_check_count();
      end
    end
  endtask

  virtual function int unsigned c_guard_word_count();
    int unsigned padded_m;
    int unsigned padded_n;
    int unsigned active_words;
    int unsigned padded_words;

    padded_m = ceil4(m_size);
    padded_n = ceil4(n_size);
    active_words = m_size * n_size;
    padded_words = padded_m * padded_n;
    return ((padded_words > active_words) ? padded_words : active_words) +
           C_EXTRA_GUARD_WORDS;
  endfunction

  virtual function int unsigned ceil4(input int unsigned value);
    return ((value + 3) / 4) * 4;
  endfunction
endclass

`endif
