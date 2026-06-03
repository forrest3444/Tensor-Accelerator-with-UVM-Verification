`ifndef TENSOR_ACCEL_IRQ_VSEQ_SV
`define TENSOR_ACCEL_IRQ_VSEQ_SV

class tensor_irq_vseq extends tensor_matmul_vseq;
  `uvm_object_utils(tensor_irq_vseq)

  function new(string name = "tensor_irq_vseq");
    super.new(name);
    m_size = 8;
    n_size = 8;
    k_size = 8;
    precision = PREC_INT8;
    post_op = POST_NONE;
    sat_mode = SAT_WRAP;
    burst_len = 8'd4;
    irq_en = 1'b1;
    auto_clear_status = 1'b0;
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Running legal IRQ completion scenario", UVM_MEDIUM)
    run_one_irq_matmul("clear_irq_check");
    clear_irq_status();
    check_irq_clear("IRQ_STATUS W1C clear");
    clear_done_status();
    run_one_irq_matmul("clear_done_check");
    clear_done_status();
    check_irq_clear("CTRL.clear_done");
  endtask

  protected virtual task run_one_irq_matmul(string label);
    `uvm_info(get_type_name(), $sformatf("Starting IRQ matmul subcase %s", label), UVM_MEDIUM)
    super.body();
    check_irq_set(label);
  endtask

  protected virtual task check_irq_set(string label);
    uvm_reg_data_t status_data;
    uvm_reg_data_t irq_status_data;

    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.IRQ_STATUS, irq_status_data);

    if ((status_data[31:0] & STATUS_IRQ) == 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("%s: STATUS.irq was not set, STATUS=0x%08x",
                           label, status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (irq_status_data[0] !== 1'b1) begin
      `uvm_error(get_type_name(),
                 $sformatf("%s: IRQ_STATUS[0] was not set, IRQ_STATUS=0x%08x",
                           label, irq_status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (cfg == null || cfg.vif == null || cfg.vif.irq !== 1'b1) begin
      `uvm_error(get_type_name(), $sformatf("%s: external irq pin was not asserted", label))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  protected virtual task check_irq_clear(string label);
    uvm_reg_data_t status_data;
    uvm_reg_data_t irq_status_data;

    wait_cfg_clocks(2);
    ral_read(reg_model.STATUS, status_data);
    ral_read(reg_model.IRQ_STATUS, irq_status_data);

    if ((status_data[31:0] & STATUS_IRQ) != 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("%s: STATUS.irq was not cleared, STATUS=0x%08x",
                           label, status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (irq_status_data[0] !== 1'b0) begin
      `uvm_error(get_type_name(),
                 $sformatf("%s: IRQ_STATUS[0] was not cleared, IRQ_STATUS=0x%08x",
                           label, irq_status_data[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (cfg == null || cfg.vif == null || cfg.vif.irq !== 1'b0) begin
      `uvm_error(get_type_name(), $sformatf("%s: external irq pin was not deasserted", label))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  protected virtual task clear_irq_status();
    ral_write(reg_model.IRQ_STATUS, 32'd1);
  endtask

  protected virtual task clear_done_status();
    ral_write(reg_model.CTRL, CTRL_IRQ_EN | CTRL_CLEAR_DONE);
    wait_cfg_clocks(2);
  endtask
endclass

`endif
