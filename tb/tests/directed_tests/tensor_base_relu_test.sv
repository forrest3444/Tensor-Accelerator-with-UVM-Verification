`ifndef TENSOR_ACCEL_BASE_RELU_TEST_SV
`define TENSOR_ACCEL_BASE_RELU_TEST_SV

class tensor_base_relu_test extends base_test;
  `uvm_component_utils(tensor_base_relu_test)

  function new(string name = "tensor_base_relu_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_relu_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_relu_vseq::type_id::create("vseq");
    vseq.m_size = 4;
    vseq.n_size = 5;
    vseq.k_size = 3;
    vseq.precision = PREC_INT8;
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
