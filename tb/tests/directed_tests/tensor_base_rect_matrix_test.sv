`ifndef TENSOR_ACCEL_BASE_RECT_MATRIX_TEST_SV
`define TENSOR_ACCEL_BASE_RECT_MATRIX_TEST_SV

virtual class tensor_rect_legacy_test_base extends base_test;
  typedef struct {
    int unsigned m;
    int unsigned n;
    int unsigned k;
  } rect_case_t;

  localparam bit [31:0] A_BASE = 32'h0001_0000;
  localparam bit [31:0] B_BASE = 32'h0002_0000;
  localparam bit [31:0] C_BASE = 32'h0003_0000;

  function new(string name = "tensor_rect_legacy_test_base",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task wait_for_reset_done();
    if (cfg != null && cfg.vif != null) begin
      @(posedge cfg.vif.rst_n);
      repeat (2) @(posedge cfg.vif.clk);
    end
  endtask
endclass

class tensor_base_rect_matrix_test extends tensor_rect_legacy_test_base;
  `uvm_component_utils(tensor_base_rect_matrix_test)

  function new(string name = "tensor_base_rect_matrix_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    rect_case_t cases[$];

    phase.raise_objection(this);
    cases.push_back('{m:4,  n:8,  k:16});
    cases.push_back('{m:8,  n:4,  k:12});
    cases.push_back('{m:13, n:7,  k:9});
    cases.push_back('{m:1,  n:64, k:3});
    cases.push_back('{m:64, n:1,  k:5});

    foreach (cases[idx]) begin
      tensor_matmul_vseq vseq;

      vseq = tensor_matmul_vseq::type_id::create($sformatf("vseq_case%0d", idx));
      vseq.m_size = cases[idx].m;
      vseq.n_size = cases[idx].n;
      vseq.k_size = cases[idx].k;
      vseq.precision = PREC_INT8;
      vseq.start(env.axi_system_env.sequencer);
    end

    phase.drop_objection(this);
  endtask
endclass

`endif
