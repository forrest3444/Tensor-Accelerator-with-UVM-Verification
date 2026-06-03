`ifndef TENSOR_BASE_RO_REG_PROTECTION_TEST_SV
`define TENSOR_BASE_RO_REG_PROTECTION_TEST_SV

class tensor_base_ro_reg_protection_test extends base_test;
  `uvm_component_utils(tensor_base_ro_reg_protection_test)

  function new(string name = "tensor_base_ro_reg_protection_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_ro_reg_protection_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_ro_reg_protection_vseq::type_id::create("vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
