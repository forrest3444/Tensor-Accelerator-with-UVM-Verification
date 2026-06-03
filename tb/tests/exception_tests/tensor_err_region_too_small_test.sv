`ifndef TENSOR_ERR_REGION_TOO_SMALL_TEST_SV
`define TENSOR_ERR_REGION_TOO_SMALL_TEST_SV

class tensor_err_region_too_small_test extends base_test;
  `uvm_component_utils(tensor_err_region_too_small_test)

  function new(string name = "tensor_err_region_too_small_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_region_too_small_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_region_too_small_vseq::type_id::create("vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
