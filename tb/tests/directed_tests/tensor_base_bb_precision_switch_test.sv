`ifndef TENSOR_ACCEL_BASE_BB_PRECISION_SWITCH_TEST_SV
`define TENSOR_ACCEL_BASE_BB_PRECISION_SWITCH_TEST_SV

class tensor_base_bb_precision_switch_test extends base_test;
  `uvm_component_utils(tensor_base_bb_precision_switch_test)

  function new(string name = "tensor_base_bb_precision_switch_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_bb_precision_switch_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_bb_precision_switch_vseq::type_id::create("vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
