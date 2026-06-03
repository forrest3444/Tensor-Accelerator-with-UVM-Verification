`ifndef TENSOR_ACCEL_BASE_DEGENERATE_DIMS_TEST_SV
`define TENSOR_ACCEL_BASE_DEGENERATE_DIMS_TEST_SV

class tensor_base_degenerate_dims_test extends base_test;
  `uvm_component_utils(tensor_base_degenerate_dims_test)

  function new(string name = "tensor_base_degenerate_dims_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    svt_axi_slave_memory_sequence::type_id::set_type_override(
      tensor_axi_ready_delay_slave_seq::get_type());
    super.build_phase(phase);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_degenerate_dims_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_degenerate_dims_vseq::type_id::create("vseq");
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
