`ifndef TENSOR_ACCEL_BASE_RANDOM_CORNER_DATA_TEST_SV
`define TENSOR_ACCEL_BASE_RANDOM_CORNER_DATA_TEST_SV

class tensor_base_random_corner_data_test extends base_test;
  `uvm_component_utils(tensor_base_random_corner_data_test)

  int unsigned num_iterations;

  function new(string name = "tensor_base_random_corner_data_test",
               uvm_component parent = null);
    super.new(name, parent);
    num_iterations = 3;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    svt_axi_slave_memory_sequence::type_id::set_type_override(
      tensor_axi_ready_delay_slave_seq::get_type());
    super.build_phase(phase);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_random_corner_data_vseq vseq;

    void'($value$plusargs("RAND_ITERS=%0d", num_iterations));
    phase.raise_objection(this);
    for (int unsigned iter = 0; iter < num_iterations; iter++) begin
      vseq = tensor_random_corner_data_vseq::type_id::create($sformatf("vseq_%0d", iter));
      vseq.set_item_context(null, env.axi_system_env.sequencer);
      if (!vseq.randomize()) begin
        `uvm_fatal(get_type_name(), "Failed to randomize tensor_random_corner_data_vseq")
      end
      vseq.start(env.axi_system_env.sequencer);
    end
    phase.drop_objection(this);
  endtask
endclass

`endif
