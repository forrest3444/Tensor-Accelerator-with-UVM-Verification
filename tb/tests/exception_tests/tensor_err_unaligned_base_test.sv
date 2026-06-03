`ifndef TENSOR_ERR_UNALIGNED_BASE_TEST_SV
`define TENSOR_ERR_UNALIGNED_BASE_TEST_SV

class tensor_err_unaligned_base_test extends base_test;
  `uvm_component_utils(tensor_err_unaligned_base_test)

  function new(string name = "tensor_err_unaligned_base_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_unaligned_base_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_unaligned_base_vseq::type_id::create("vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
