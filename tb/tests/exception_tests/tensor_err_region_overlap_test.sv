`ifndef TENSOR_ERR_REGION_OVERLAP_TEST_SV
`define TENSOR_ERR_REGION_OVERLAP_TEST_SV

class tensor_err_region_overlap_test extends base_test;
  `uvm_component_utils(tensor_err_region_overlap_test)

  function new(string name = "tensor_err_region_overlap_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_region_overlap_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_region_overlap_vseq::type_id::create("vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
