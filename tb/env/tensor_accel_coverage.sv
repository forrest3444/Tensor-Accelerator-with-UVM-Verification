`ifndef TENSOR_ACCEL_COVERAGE_SV
`define TENSOR_ACCEL_COVERAGE_SV

class tensor_accel_coverage extends tensor_accel_subscriber;
  `uvm_component_utils(tensor_accel_coverage)

  int unsigned sampled_m;
  int unsigned sampled_n;
  int unsigned sampled_k;
  int unsigned sampled_precision;
  int unsigned sampled_post_op;
  int unsigned sampled_sat_mode;
  int unsigned sampled_burst_len;
  bit sampled_overflow;
  bit sampled_error;

  covergroup tensor_cg;
    option.per_instance = 1;
    cp_m: coverpoint sampled_m {
      bins min = {1};
      bins small_dim[] = {[2:15]};
      bins medium_dim[] = {[16:32]};
      bins max = {64};
    }
    cp_n: coverpoint sampled_n {
      bins min = {1};
      bins small_dim[] = {[2:15]};
      bins medium_dim[] = {[16:32]};
      bins max = {64};
    }
    cp_k: coverpoint sampled_k {
      bins min = {1};
      bins small_dim[] = {[2:15]};
      bins medium_dim[] = {[16:32]};
      bins max = {64};
    }
    cp_precision: coverpoint sampled_precision {
      bins int4  = {PREC_INT4};
      bins int8  = {PREC_INT8};
      bins int16 = {PREC_INT16};
    }
    cp_post_op: coverpoint sampled_post_op {
      bins none      = {POST_NONE};
      bins bias      = {POST_BIAS};
      bins relu      = {POST_RELU};
      bins bias_relu = {POST_BIAS_RELU};
    }
    cp_sat_mode: coverpoint sampled_sat_mode {
      bins wrap     = {SAT_WRAP};
      bins saturate = {SAT_SATURATE};
    }
    cp_burst_len: coverpoint sampled_burst_len {
      bins base_legal[] = {1, 4, 8, 16};
      bins perf = {[17:256]};
    }
    cp_overflow: coverpoint sampled_overflow;
    cp_error: coverpoint sampled_error;
    x_precision_post_op: cross cp_precision, cp_post_op;
  endgroup

  function new(string name = "tensor_accel_coverage", uvm_component parent = null);
    super.new(name, parent);
    tensor_cg = new();
  endfunction

  function void write(tensor_accel_matrix_item t);
    sample_item(t, 1'b0, 1'b0);
  endfunction

  function void sample_item(tensor_accel_matrix_item item,
                            bit overflow_seen,
                            bit error_seen);
    sampled_m = item.m;
    sampled_n = item.n;
    sampled_k = item.k;
    sampled_precision = item.precision;
    sampled_post_op = item.post_op;
    sampled_sat_mode = item.sat_mode;
    sampled_burst_len = (cfg == null) ? 0 : cfg.vip_cfg.max_burst_len;
    sampled_overflow = overflow_seen;
    sampled_error = error_seen;
    tensor_cg.sample();
  endfunction

  function void sample_cfg(accel_cfg_t cfg, bit overflow_seen, bit error_seen);
    sampled_m = cfg.m_size;
    sampled_n = cfg.n_size;
    sampled_k = cfg.k_size;
    sampled_precision = cfg.precision;
    sampled_post_op = cfg.post_op;
    sampled_sat_mode = cfg.sat_mode;
    sampled_burst_len = cfg.burst_len;
    sampled_overflow = overflow_seen;
    sampled_error = error_seen;
    tensor_cg.sample();
  endfunction
endclass

`endif
