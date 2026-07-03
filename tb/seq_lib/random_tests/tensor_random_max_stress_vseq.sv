`ifndef TENSOR_ACCEL_RANDOM_MAX_STRESS_VSEQ_SV
`define TENSOR_ACCEL_RANDOM_MAX_STRESS_VSEQ_SV

class tensor_random_max_stress_vseq extends tensor_random_legal_vseq;
  `uvm_object_utils(tensor_random_max_stress_vseq)

  constraint c_random_legal_modes {
    precision inside {PREC_INT4, PREC_INT8, PREC_INT16};
    post_op inside {POST_NONE, POST_BIAS, POST_RELU, POST_BIAS_RELU};
    sat_mode inside {SAT_WRAP, SAT_SATURATE};
    burst_len inside {[1:16]};
  }

  function new(string name = "tensor_random_max_stress_vseq");
    super.new(name);
  endfunction

  virtual task body();
    if (cfg != null && cfg.profile != TB_PROFILE_PERFORMANCE) begin
      `uvm_warning(get_type_name(),
                   "tensor_random_max_stress_vseq expected Performance Profile cfg")
    end

    `uvm_info(get_type_name(), "Running random max-stress scenario", UVM_LOW)
    super.body();
  endtask
endclass

`endif
