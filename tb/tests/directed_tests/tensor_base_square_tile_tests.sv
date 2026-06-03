`ifndef TENSOR_ACCEL_BASE_SQUARE_TILE_TESTS_SV
`define TENSOR_ACCEL_BASE_SQUARE_TILE_TESTS_SV

class tensor_base_8x8_test extends base_test;
  `uvm_component_utils(tensor_base_8x8_test)

  function new(string name = "tensor_base_8x8_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_matmul_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_matmul_vseq::type_id::create("vseq");
    vseq.m_size = 8;
    vseq.n_size = 8;
    vseq.k_size = 8;
    vseq.precision = PREC_INT8;
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

class tensor_base_16x16_test extends base_test;
  `uvm_component_utils(tensor_base_16x16_test)

  function new(string name = "tensor_base_16x16_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_matmul_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_matmul_vseq::type_id::create("vseq");
    vseq.m_size = 16;
    vseq.n_size = 16;
    vseq.k_size = 16;
    vseq.precision = PREC_INT8;
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

class tensor_base_32x32_test extends base_test;
  `uvm_component_utils(tensor_base_32x32_test)

  function new(string name = "tensor_base_32x32_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_matmul_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_matmul_vseq::type_id::create("vseq");
    vseq.m_size = 32;
    vseq.n_size = 32;
    vseq.k_size = 32;
    vseq.precision = PREC_INT8;
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

class tensor_base_64x64_test extends base_test;
  `uvm_component_utils(tensor_base_64x64_test)

  function new(string name = "tensor_base_64x64_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_matmul_vseq vseq;

    phase.raise_objection(this);
    vseq = tensor_matmul_vseq::type_id::create("vseq");
    vseq.m_size = 64;
    vseq.n_size = 64;
    vseq.k_size = 64;
    vseq.precision = PREC_INT8;
    vseq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask
endclass

`endif
