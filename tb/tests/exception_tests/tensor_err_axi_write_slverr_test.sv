`ifndef TENSOR_ERR_AXI_WRITE_SLVERR_TEST_SV
`define TENSOR_ERR_AXI_WRITE_SLVERR_TEST_SV

class tensor_err_axi_write_slverr_test extends base_test;
  `uvm_component_utils(tensor_err_axi_write_slverr_test)

  function new(string name = "tensor_err_axi_write_slverr_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    svt_axi_slave_memory_sequence::type_id::set_type_override(
      tensor_axi_write_error_slave_seq::get_type());
    super.build_phase(phase);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_axi_write_error_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_axi_write_error_vseq::type_id::create("vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
