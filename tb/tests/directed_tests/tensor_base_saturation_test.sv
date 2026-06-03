`ifndef TENSOR_ACCEL_BASE_SATURATION_TEST_SV
`define TENSOR_ACCEL_BASE_SATURATION_TEST_SV

class tensor_base_saturation_test extends tensor_rect_legacy_test_base;
  `uvm_component_utils(tensor_base_saturation_test)

  function new(string name = "tensor_base_saturation_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    sat_mode_e cases[$];

    phase.raise_objection(this);
    wait_for_reset_done();
    cases.push_back(SAT_SATURATE);
    cases.push_back(SAT_WRAP);

    foreach (cases[idx]) begin
      tensor_saturation_vseq vseq;

      vseq = tensor_saturation_vseq::type_id::create($sformatf("vseq_case%0d", idx));
      vseq.sat_mode = cases[idx];
      vseq.check_overflow_status = 1'b0;
      vseq.start(env.axi_system_env.sequencer);
    end

    phase.drop_objection(this);
  endtask
endclass

`endif
