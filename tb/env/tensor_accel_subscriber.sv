`ifndef TENSOR_ACCEL_SUBSCRIBER_SV
`define TENSOR_ACCEL_SUBSCRIBER_SV

virtual class tensor_accel_subscriber extends uvm_subscriber #(tensor_accel_matrix_item);
  tensor_accel_env_cfg cfg;

  function new(string name = "tensor_accel_subscriber", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db #(tensor_accel_env_cfg)::get(this, "", "cfg", cfg));
  endfunction
endclass

`endif
