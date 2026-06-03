`ifndef TENSOR_ERR_ILLEGAL_MATRIX_SIZE_TEST_SV
`define TENSOR_ERR_ILLEGAL_MATRIX_SIZE_TEST_SV

class tensor_err_illegal_matrix_size_test extends base_test;
  `uvm_component_utils(tensor_err_illegal_matrix_size_test)

  function new(string name = "tensor_err_illegal_matrix_size_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_illegal_matrix_size_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_illegal_matrix_size_vseq::type_id::create("vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
