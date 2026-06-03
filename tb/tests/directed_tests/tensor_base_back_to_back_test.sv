`ifndef TENSOR_ACCEL_BASE_BACK_TO_BACK_TEST_SV
`define TENSOR_ACCEL_BASE_BACK_TO_BACK_TEST_SV

class tensor_base_back_to_back_test extends base_test;
  `uvm_component_utils(tensor_base_back_to_back_test)

  function new(string name = "tensor_base_back_to_back_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_back_to_back_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_back_to_back_vseq::type_id::create("back_to_back_vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
