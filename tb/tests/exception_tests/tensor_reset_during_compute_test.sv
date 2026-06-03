`ifndef TENSOR_RESET_DURING_COMPUTE_TEST_SV
`define TENSOR_RESET_DURING_COMPUTE_TEST_SV

class tensor_reset_during_compute_test extends base_test;
  `uvm_component_utils(tensor_reset_during_compute_test)

  function new(string name = "tensor_reset_during_compute_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_reset_during_operation_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_reset_during_operation_vseq::type_id::create("vseq");
    vseq.reset_phase = RESET_DURING_COMPUTE;
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
