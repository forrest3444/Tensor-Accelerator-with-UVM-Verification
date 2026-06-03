`ifndef TENSOR_SOFT_RESET_DURING_IDLE_VSEQ_SV
`define TENSOR_SOFT_RESET_DURING_IDLE_VSEQ_SV

class tensor_soft_reset_during_idle_vseq extends tensor_soft_reset_vseq;
  `uvm_object_utils(tensor_soft_reset_during_idle_vseq)

  function new(string name = "tensor_soft_reset_during_idle_vseq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(),
              "Running soft reset during IDLE configuration preservation scenario",
              UVM_MEDIUM)

    find_env();
    program_matmul(32'd4, 32'd4, 32'd4, 8'd4);
    check_programmed_config();
    apply_soft_reset();
    check_reset_status();
    check_programmed_config();
    run_recovery_task();
  endtask

  protected virtual task check_programmed_config();
    check_reg_value(reg_model.M_SIZE, 32'd4, "M_SIZE");
    check_reg_value(reg_model.N_SIZE, 32'd4, "N_SIZE");
    check_reg_value(reg_model.K_SIZE, 32'd4, "K_SIZE");
    check_reg_value(reg_model.PRECISION, {30'd0, PREC_INT8}, "PRECISION");
    check_reg_value(reg_model.POST_OP, {30'd0, POST_NONE}, "POST_OP");
    check_reg_value(reg_model.SAT_MODE, {31'd0, SAT_WRAP}, "SAT_MODE");
    check_reg_value(reg_model.A_BASE, A_BASE, "A_BASE");
    check_reg_value(reg_model.B_BASE, B_BASE, "B_BASE");
    check_reg_value(reg_model.C_BASE, C_BASE, "C_BASE");
    check_reg_value(reg_model.BIAS_BASE, BIAS_BASE, "BIAS_BASE");
    check_reg_value(reg_model.DMA_CFG, 32'd4, "DMA_CFG");
  endtask

  protected virtual task check_reg_value(uvm_reg target_reg,
                                         bit [31:0] expected,
                                         string reg_name);
    uvm_reg_data_t actual;

    ral_read(target_reg, actual);
    if (actual[31:0] != expected) begin
      `uvm_error(get_type_name(),
                 $sformatf("%s changed unexpectedly exp=0x%08x act=0x%08x",
                           reg_name, expected, actual[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask
endclass

`endif
