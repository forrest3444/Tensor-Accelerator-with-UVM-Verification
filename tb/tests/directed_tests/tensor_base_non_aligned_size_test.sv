`ifndef TENSOR_ACCEL_BASE_NON_ALIGNED_SIZE_TEST_SV
`define TENSOR_ACCEL_BASE_NON_ALIGNED_SIZE_TEST_SV

class tensor_base_non_aligned_size_test extends tensor_rect_legacy_test_base;
  `uvm_component_utils(tensor_base_non_aligned_size_test)

  function new(string name = "tensor_base_non_aligned_size_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    rect_case_t cases[$];

    phase.raise_objection(this);
    wait_for_reset_done();
    cases.push_back('{m:1,  n:1,  k:1});
    cases.push_back('{m:3,  n:5,  k:7});
    cases.push_back('{m:5,  n:4,  k:6});
    cases.push_back('{m:4,  n:5,  k:6});
    cases.push_back('{m:63, n:61, k:59});

    foreach (cases[idx]) begin
      tensor_non_aligned_vseq vseq;

      vseq = tensor_non_aligned_vseq::type_id::create($sformatf("vseq_case%0d", idx));
      vseq.m_size = cases[idx].m;
      vseq.n_size = cases[idx].n;
      vseq.k_size = cases[idx].k;
      vseq.case_idx = idx;
      vseq.start(env.axi_system_env.sequencer);
    end

    phase.drop_objection(this);
  endtask
endclass

`endif
