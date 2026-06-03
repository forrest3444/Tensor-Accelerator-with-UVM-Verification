`ifndef TENSOR_ACCEL_DEGENERATE_DIMS_VSEQ_SV
`define TENSOR_ACCEL_DEGENERATE_DIMS_VSEQ_SV

class tensor_degenerate_dims_vseq extends tensor_matmul_vseq;
  `uvm_object_utils(tensor_degenerate_dims_vseq)

  typedef struct {
    int unsigned m;
    int unsigned n;
    int unsigned k;
    precision_e precision;
    int unsigned burst_len;
    string name;
  } degenerate_case_t;

  function new(string name = "tensor_degenerate_dims_vseq");
    super.new(name);
  endfunction

  virtual function int unsigned effective_timeout_cycles();
    int unsigned base_timeout;

    base_timeout = super.effective_timeout_cycles();
    return (base_timeout < 20000) ? 20000 : base_timeout;
  endfunction

  virtual task body();
    degenerate_case_t cases[$];

    add_single_row_cases(cases);
    add_narrow_matrix_cases(cases);
    add_extreme_cases(cases);

    foreach (cases[idx]) begin
      m_size = cases[idx].m;
      n_size = cases[idx].n;
      k_size = cases[idx].k;
      precision = cases[idx].precision;
      burst_len = cases[idx].burst_len[7:0];
      auto_clear_status = 1'b1;

      `uvm_info(get_type_name(),
                $sformatf("Degenerate dims case[%0d] %s M=%0d N=%0d K=%0d precision=%0d burst_len=%0d",
                          idx, cases[idx].name, m_size, n_size, k_size,
                          precision, burst_len),
                UVM_LOW)
      super.body();
      auto_clear_status = 1'b1;
    end
  endtask

  virtual function void add_single_row_cases(ref degenerate_case_t cases[$]);
    int unsigned n_values[$];

    n_values = {4, 8, 13, 16, 32};
    foreach (n_values[idx]) begin
      cases.push_back('{m:1, n:n_values[idx], k:8, precision:PREC_INT8,
                        burst_len:4, name:"single_row_int8"});
      cases.push_back('{m:1, n:n_values[idx], k:8, precision:PREC_INT16,
                        burst_len:4, name:"single_row_int16"});
    end
  endfunction

  virtual function void add_narrow_matrix_cases(ref degenerate_case_t cases[$]);
    int unsigned m_values[$];
    int unsigned n_values[$];

    m_values = {4, 8, 20};
    n_values = {1, 2, 3};
    foreach (m_values[m_idx]) begin
      foreach (n_values[n_idx]) begin
        cases.push_back('{m:m_values[m_idx], n:n_values[n_idx], k:4,
                          precision:PREC_INT8, burst_len:4,
                          name:"narrow_matrix_int8"});
        cases.push_back('{m:m_values[m_idx], n:n_values[n_idx], k:4,
                          precision:PREC_INT16, burst_len:4,
                          name:"narrow_matrix_int16"});
      end
    end
  endfunction

  virtual function void add_extreme_cases(ref degenerate_case_t cases[$]);
    cases.push_back('{m:1, n:1, k:8, precision:PREC_INT8, burst_len:4,
                      name:"extreme_1x1x8_int8"});
    cases.push_back('{m:1, n:2, k:2, precision:PREC_INT8, burst_len:4,
                      name:"extreme_1x2x2_int8"});
    cases.push_back('{m:64, n:1, k:64, precision:PREC_INT8, burst_len:4,
                      name:"extreme_64x1x64_int8"});
  endfunction
endclass

`endif
