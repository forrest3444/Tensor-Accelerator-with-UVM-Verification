`ifndef TENSOR_RO_REG_PROTECTION_VSEQ_SV
`define TENSOR_RO_REG_PROTECTION_VSEQ_SV

class tensor_ro_reg_protection_vseq extends base_vseq;
  `uvm_object_utils(tensor_ro_reg_protection_vseq)

  function new(string name = "tensor_ro_reg_protection_vseq");
    super.new(name);
  endfunction

  virtual task body();
    tensor_matmul_vseq matmul_seq;
    tensor_clear_status_seq clear_seq;
    uvm_reg_data_t status_before;
    uvm_reg_data_t status_after;
    uvm_reg_data_t error_before;
    uvm_reg_data_t error_after;
    uvm_reg_data_t ovf_before;
    uvm_reg_data_t ovf_after;

    `uvm_info(get_type_name(), "Running read-only register protection scenario", UVM_MEDIUM)

    matmul_seq = tensor_matmul_vseq::type_id::create("matmul_seq");
    matmul_seq.m_size = 32'd4;
    matmul_seq.n_size = 32'd4;
    matmul_seq.k_size = 32'd4;
    matmul_seq.precision = PREC_INT8;
    matmul_seq.post_op = POST_NONE;
    matmul_seq.sat_mode = SAT_WRAP;
    matmul_seq.burst_len = 8'd4;
    matmul_seq.timeout_cycles = 10000;
    matmul_seq.poll_interval_cycles = 100;
    matmul_seq.auto_clear_status = 1'b0;
    matmul_seq.start(p_sequencer);

    ral_read(reg_model.STATUS, status_before);
    ral_read(reg_model.ERROR_CODE, error_before);
    ral_read(reg_model.OVF_COUNT, ovf_before);

    if (((status_before[31:0] & STATUS_DONE) == 0) ||
        ((status_before[31:0] & STATUS_ERROR) != 0)) begin
      `uvm_error(get_type_name(),
                 $sformatf("Expected DONE without ERROR before RO write checks, STATUS=0x%08x",
                           status_before[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end

    ral_write(reg_model.STATUS, 32'h0000_0000);
    ral_read(reg_model.STATUS, status_after);
    check_ro_value("STATUS", status_before[31:0], status_after[31:0],
                   STATUS_BUSY | STATUS_DONE | STATUS_ERROR |
                   STATUS_IRQ | STATUS_OVERFLOW_SEEN);

    ral_write(reg_model.ERROR_CODE, 32'hffff_ffff);
    ral_read(reg_model.ERROR_CODE, error_after);
    check_ro_value("ERROR_CODE", error_before[31:0], error_after[31:0],
                   32'h0000_000f);

    ral_write(reg_model.OVF_COUNT, 32'hffff_ffff);
    ral_read(reg_model.OVF_COUNT, ovf_after);
    check_ro_value("OVF_COUNT", ovf_before[31:0], ovf_after[31:0],
                   32'hffff_ffff);

    ral_read(reg_model.STATUS, status_after);
    if (((status_after[31:0] & STATUS_DONE) == 0) ||
        ((status_after[31:0] & STATUS_ERROR) != 0)) begin
      `uvm_error(get_type_name(),
                 $sformatf("RO register writes corrupted terminal STATUS=0x%08x",
                           status_after[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
    end

    clear_seq = tensor_clear_status_seq::type_id::create("clear_seq");
    clear_seq.start(p_sequencer);
  endtask

  protected virtual function void check_ro_value(string reg_name,
                                                 bit [31:0] before_data,
                                                 bit [31:0] after_data,
                                                 bit [31:0] mask);
    if ((after_data & mask) !== (before_data & mask)) begin
      `uvm_error(get_type_name(),
                 $sformatf("%s changed after RO write: before=0x%08x after=0x%08x mask=0x%08x",
                           reg_name, before_data, after_data, mask))
      if (cfg != null) cfg.add_seq_check_error();
    end
    else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endfunction
endclass

`endif
