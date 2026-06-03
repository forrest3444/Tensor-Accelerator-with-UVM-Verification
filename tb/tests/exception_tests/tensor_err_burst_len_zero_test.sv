`ifndef TENSOR_ERR_BURST_LEN_ZERO_TEST_SV
`define TENSOR_ERR_BURST_LEN_ZERO_TEST_SV

class tensor_err_burst_len_zero_test extends base_test;
  `uvm_component_utils(tensor_err_burst_len_zero_test)

  function new(string name = "tensor_err_burst_len_zero_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_burst_len_zero_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_burst_len_zero_vseq::type_id::create("vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
