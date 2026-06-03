`ifndef TENSOR_SOFT_RESET_TEST_SV
`define TENSOR_SOFT_RESET_TEST_SV

class tensor_soft_reset_test extends base_test;
  `uvm_component_utils(tensor_soft_reset_test)

  function new(string name = "tensor_soft_reset_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_soft_reset_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_soft_reset_vseq::type_id::create("vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
