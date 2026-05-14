`ifndef TENSOR_ACCEL_BASE_REG_RW_TEST_SV
`define TENSOR_ACCEL_BASE_REG_RW_TEST_SV

class tensor_base_reg_rw_test extends base_test;
  `uvm_component_utils(tensor_base_reg_rw_test)

  function new(string name = "tensor_base_reg_rw_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tensor_base_reg_rw_seq reg_rw_seq;

    phase.raise_objection(this);
    if (cfg != null && cfg.vif != null) begin
      @(posedge cfg.vif.rst_n);
      repeat (2) @(posedge cfg.vif.clk);
    end

    reg_rw_seq = tensor_base_reg_rw_seq::type_id::create("reg_rw_seq");
    reg_rw_seq.start(env.axi_system_env.sequencer);
    phase.drop_objection(this);
  endtask

  virtual function void final_phase(uvm_phase phase);
    uvm_report_server svr;
    super.final_phase(phase);
    svr = uvm_report_server::get_server();

    if ((svr.get_severity_count(UVM_FATAL) +
         svr.get_severity_count(UVM_ERROR)) == 0) begin
      `uvm_info("TEST_RESULT", "tensor_base_reg_rw_test PASSED", UVM_LOW)
    end
    else begin
      `uvm_info("TEST_RESULT", "tensor_base_reg_rw_test FAILED", UVM_LOW)
    end
  endfunction
endclass

`endif
