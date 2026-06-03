`ifndef TENSOR_ACCEL_BASE_AXI_READY_DELAY_TEST_SV
`define TENSOR_ACCEL_BASE_AXI_READY_DELAY_TEST_SV

class tensor_base_axi_ready_delay_test extends base_test;
  `uvm_component_utils(tensor_base_axi_ready_delay_test)

  function new(string name = "tensor_base_axi_ready_delay_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    svt_axi_slave_memory_sequence::type_id::set_type_override(
      tensor_axi_ready_delay_slave_seq::get_type());
    super.build_phase(phase);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_matmul_vseq vseq;

    phase.raise_objection(this);

    vseq = tensor_matmul_vseq::type_id::create("axi_ready_delay_vseq");
    vseq.m_size = 16;
    vseq.n_size = 16;
    vseq.k_size = 16;
    vseq.precision = PREC_INT8;
    vseq.burst_len = 8'd8;
    vseq.timeout_cycles = 500000;
    vseq.poll_interval_cycles = 1000;
    vseq.start(env.axi_system_env.sequencer);

    phase.drop_objection(this);
  endtask
endclass

`endif
