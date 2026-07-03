`ifndef TENSOR_ERR_IRQ_ON_ERROR_TEST_SV
`define TENSOR_ERR_IRQ_ON_ERROR_TEST_SV

class tensor_err_irq_on_error_test extends base_test;
  `uvm_component_utils(tensor_err_irq_on_error_test)

  function new(string name = "tensor_err_irq_on_error_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_irq_on_error_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_irq_on_error_vseq::type_id::create("vseq");
    vseq.illegal_precision = 2'd3;
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
