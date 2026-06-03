`ifndef TENSOR_ACCEL_BASE_IRQ_TEST_SV
`define TENSOR_ACCEL_BASE_IRQ_TEST_SV

class tensor_base_irq_test extends base_test;
  `uvm_component_utils(tensor_base_irq_test)

  function new(string name = "tensor_base_irq_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_irq_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_irq_vseq::type_id::create("vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
