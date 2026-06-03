`ifndef TENSOR_ACCEL_BASE_OVERFLOW_STATUS_TEST_SV
`define TENSOR_ACCEL_BASE_OVERFLOW_STATUS_TEST_SV

class tensor_base_overflow_status_test extends tensor_rect_legacy_test_base;
  `uvm_component_utils(tensor_base_overflow_status_test)

  function new(string name = "tensor_base_overflow_status_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_saturation_vseq vseq;

    phase.raise_objection(this);
    wait_for_reset_done();

    vseq = tensor_saturation_vseq::type_id::create("vseq");
    vseq.sat_mode = SAT_SATURATE;
    vseq.check_overflow_status = 1'b1;
    vseq.start(env.axi_system_env.sequencer);

    phase.drop_objection(this);
  endtask
endclass

`endif
