`ifndef TENSOR_ACCEL_BASE_INT16_4X4_TEST_SV
`define TENSOR_ACCEL_BASE_INT16_4X4_TEST_SV

class tensor_base_int16_4x4_test extends base_test;
  `uvm_component_utils(tensor_base_int16_4x4_test)

  function new(string name = "tensor_base_int16_4x4_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_matmul_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_matmul_vseq::type_id::create("vseq");
    vseq.m_size = 4;
    vseq.n_size = 4;
    vseq.k_size = 4;
    vseq.precision = PREC_INT16;
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
