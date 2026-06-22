`ifndef TENSOR_BASE_PARTIAL_K_POSTOP_ISOLATION_TEST_SV
`define TENSOR_BASE_PARTIAL_K_POSTOP_ISOLATION_TEST_SV

class tensor_base_partial_k_postop_isolation_test extends base_test;
  `uvm_component_utils(tensor_base_partial_k_postop_isolation_test)

  function new(string name = "tensor_base_partial_k_postop_isolation_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    run_case("single_partial_none",      4, 2, POST_NONE,      SAT_WRAP);
    run_case("single_partial_bias",      4, 2, POST_BIAS,      SAT_WRAP);
    run_case("single_partial_relu",      4, 2, POST_RELU,      SAT_WRAP);
    run_case("single_partial_bias_relu", 4, 2, POST_BIAS_RELU, SAT_WRAP);

    run_case("multi2_partial_bias_relu", 8, 2, POST_BIAS_RELU, SAT_SATURATE);
    run_case("multi5_partial_none",     20, 2, POST_NONE,      SAT_SATURATE);
    run_case("multi5_partial_bias",     20, 2, POST_BIAS,      SAT_SATURATE);
    run_case("multi5_partial_relu",     20, 2, POST_RELU,      SAT_SATURATE);
    run_case("multi5_partial_bias_relu",20, 2, POST_BIAS_RELU, SAT_SATURATE);
    run_case("multi5_full_bias_relu",   20, 4, POST_BIAS_RELU, SAT_SATURATE);

    phase.drop_objection(this);
  endtask

  protected virtual task run_case(string case_name,
                                  int unsigned m_size,
                                  int unsigned k_size,
                                  post_op_e post_op,
                                  sat_mode_e sat_mode);
    tensor_partial_k_postop_vseq vseq;

    `uvm_info(get_type_name(),
              $sformatf("ISOLATION case=%s M=%0d N=2 K=%0d post_op=%0d sat=%0d",
                        case_name, m_size, k_size, post_op, sat_mode),
              UVM_MEDIUM)
    vseq = tensor_partial_k_postop_vseq::type_id::create(case_name);
    vseq.m_size = m_size;
    vseq.n_size = 2;
    vseq.k_size = k_size;
    vseq.post_op = post_op;
    vseq.sat_mode = sat_mode;
    vseq.start(env.axi_system_env.sequencer);
  endtask
endclass

`endif
