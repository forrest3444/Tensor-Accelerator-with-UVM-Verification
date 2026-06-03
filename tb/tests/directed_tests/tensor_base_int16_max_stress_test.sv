`ifndef TENSOR_ACCEL_BASE_INT16_MAX_STRESS_TEST_SV
`define TENSOR_ACCEL_BASE_INT16_MAX_STRESS_TEST_SV

class tensor_base_int16_max_stress_test extends base_test;
  `uvm_component_utils(tensor_base_int16_max_stress_test)

  function new(string name = "tensor_base_int16_max_stress_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_int16_max_stress_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_int16_max_stress_vseq::type_id::create("vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
