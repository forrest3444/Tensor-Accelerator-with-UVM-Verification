`ifndef TENSOR_ACCEL_BASE_BIAS_RELU_ORDER_TEST_SV
`define TENSOR_ACCEL_BASE_BIAS_RELU_ORDER_TEST_SV

class tensor_base_bias_relu_order_test extends base_test;
  `uvm_component_utils(tensor_base_bias_relu_order_test)

  function new(string name = "tensor_base_bias_relu_order_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_bias_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_bias_vseq::type_id::create("vseq");
    vseq.m_size = 4;
    vseq.n_size = 5;
    vseq.k_size = 3;
    vseq.precision = PREC_INT8;
    vseq.post_op = POST_BIAS_RELU;
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
