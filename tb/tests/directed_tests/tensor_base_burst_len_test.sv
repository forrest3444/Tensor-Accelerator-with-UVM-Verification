`ifndef TENSOR_ACCEL_BASE_BURST_LEN_TEST_SV
`define TENSOR_ACCEL_BASE_BURST_LEN_TEST_SV

class tensor_base_burst_len_test extends base_test;
  `uvm_component_utils(tensor_base_burst_len_test)

  function new(string name = "tensor_base_burst_len_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit [7:0] burst_lens[$];

    phase.raise_objection(this);
    burst_lens.push_back(8'd1);
    burst_lens.push_back(8'd4);
    burst_lens.push_back(8'd8);
    burst_lens.push_back(8'd16);

    foreach (burst_lens[idx]) begin
      tensor_matmul_vseq vseq;

      vseq = tensor_matmul_vseq::type_id::create($sformatf("vseq_burst%0d",
                                                           burst_lens[idx]));
      vseq.m_size = 16;
      vseq.n_size = 16;
      vseq.k_size = 16;
      vseq.precision = PREC_INT8;
      vseq.burst_len = burst_lens[idx];
      vseq.start(env.axi_system_env.sequencer);
    end

    phase.drop_objection(this);
  endtask
endclass

`endif
