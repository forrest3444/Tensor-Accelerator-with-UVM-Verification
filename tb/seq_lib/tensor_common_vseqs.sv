`ifndef TENSOR_ACCEL_COMMON_VSEQS_SV
`define TENSOR_ACCEL_COMMON_VSEQS_SV

class tensor_base_reg_rw_seq extends base_vseq;
  `uvm_object_utils(tensor_base_reg_rw_seq)

  function new(string name = "tensor_base_reg_rw_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Checking AXI-Lite register reset defaults", UVM_MEDIUM)
    ral_check(reg_model.M_SIZE, 32'd0);
    ral_check(reg_model.N_SIZE, 32'd0);
    ral_check(reg_model.K_SIZE, 32'd0);
    ral_check(reg_model.PRECISION, 32'd0);
    ral_check(reg_model.POST_OP, 32'd0);
    ral_check(reg_model.SAT_MODE, 32'd0);
    ral_check(reg_model.STATUS, 32'd0,
              STATUS_BUSY | STATUS_DONE | STATUS_ERROR | STATUS_IRQ | STATUS_OVERFLOW_SEEN);
    ral_check(reg_model.ERROR_CODE, {28'd0, ERR_NO_ERROR}, 32'h0000_000f);

    `uvm_info(get_type_name(), "Checking AXI-Lite register write/readback", UVM_MEDIUM)
    ral_write(reg_model.M_SIZE, 32'd13);
    ral_check(reg_model.M_SIZE, 32'd13);

    ral_write(reg_model.N_SIZE, 32'd21);
    ral_check(reg_model.N_SIZE, 32'd21);

    ral_write(reg_model.K_SIZE, 32'd34);
    ral_check(reg_model.K_SIZE, 32'd34);

    ral_write(reg_model.PRECISION, {30'd0, PREC_INT16});
    ral_check(reg_model.PRECISION, {30'd0, PREC_INT16});

    ral_write(reg_model.POST_OP, {30'd0, POST_BIAS_RELU});
    ral_check(reg_model.POST_OP, {30'd0, POST_BIAS_RELU});

    ral_write(reg_model.SAT_MODE, {31'd0, SAT_SATURATE});
    ral_check(reg_model.SAT_MODE, {31'd0, SAT_SATURATE});

    `uvm_info(get_type_name(), "Checking reserved register bits are ignored", UVM_MEDIUM)
    ral_write(reg_model.PRECISION, 32'ha5a5_a5a1);
    ral_check(reg_model.PRECISION, {30'd0, PREC_INT16});

    ral_write(reg_model.POST_OP, 32'h5a5a_5a5a);
    ral_check(reg_model.POST_OP, {30'd0, POST_RELU});

    ral_write(reg_model.SAT_MODE, 32'hffff_fffe);
    ral_check(reg_model.SAT_MODE, {31'd0, SAT_WRAP});

    ral_check(reg_model.STATUS, 32'd0,
              STATUS_BUSY | STATUS_DONE | STATUS_ERROR | STATUS_IRQ | STATUS_OVERFLOW_SEEN);
    ral_check(reg_model.ERROR_CODE, {28'd0, ERR_NO_ERROR}, 32'h0000_000f);
  endtask
endclass

class tensor_program_seq extends base_vseq;
  `uvm_object_utils(tensor_program_seq)

  rand bit [31:0] m_size;
  rand bit [31:0] n_size;
  rand bit [31:0] k_size;
  rand precision_e precision;
  rand post_op_e post_op;
  rand sat_mode_e sat_mode;
  rand bit [31:0] a_base;
  rand bit [31:0] b_base;
  rand bit [31:0] c_base;
  rand bit [31:0] bias_base;
  rand bit [31:0] a_spad_offset;
  rand bit [31:0] a_spad_size;
  rand bit [31:0] b_spad_offset;
  rand bit [31:0] b_spad_size;
  rand bit [31:0] c_spad_offset;
  rand bit [31:0] c_spad_size;
  rand bit [31:0] bias_spad_offset;
  rand bit [31:0] bias_spad_size;
  rand bit [7:0] burst_len;
  bit irq_en;
  bit use_cfg_regions;

  constraint c_typical_dims {
    m_size inside {[1:MAX_DIM]};
    n_size inside {[1:MAX_DIM]};
    k_size inside {[1:MAX_DIM]};
  }

  constraint c_typical_alignment {
    a_base[2:0] == 3'b000;
    b_base[2:0] == 3'b000;
    c_base[2:0] == 3'b000;
    bias_base[2:0] == 3'b000;
    a_spad_offset[1:0] == 2'b00;
    b_spad_offset[1:0] == 2'b00;
    c_spad_offset[1:0] == 2'b00;
    bias_spad_offset[1:0] == 2'b00;
    a_spad_size[1:0] == 2'b00;
    b_spad_size[1:0] == 2'b00;
    c_spad_size[1:0] == 2'b00;
    bias_spad_size[1:0] == 2'b00;
    burst_len inside {[1:16]};
  }

  function new(string name = "tensor_program_seq");
    super.new(name);
    m_size = 32'd4;
    n_size = 32'd4;
    k_size = 32'd4;
    precision = PREC_INT8;
    post_op = POST_NONE;
    sat_mode = SAT_WRAP;
    a_base = 32'h0001_0000;
    b_base = 32'h0002_0000;
    c_base = 32'h0003_0000;
    bias_base = 32'h0004_0000;
    a_spad_offset = 32'h0000_0000;
    a_spad_size = 32'h0000_2000;
    b_spad_offset = 32'h0000_2000;
    b_spad_size = 32'h0000_2000;
    c_spad_offset = 32'h0000_4000;
    c_spad_size = 32'h0000_4000;
    bias_spad_offset = 32'h0000_8000;
    bias_spad_size = 32'h0000_0400;
    burst_len = 8'd16;
    irq_en = 1'b0;
    use_cfg_regions = 1'b1;
  endfunction

  virtual task body();
    if (use_cfg_regions && cfg != null) begin
      a_spad_offset = cfg.a_region.offset;
      a_spad_size = cfg.a_region.size;
      b_spad_offset = cfg.b_region.offset;
      b_spad_size = cfg.b_region.size;
      c_spad_offset = cfg.c_region.offset;
      c_spad_size = cfg.c_region.size;
      bias_spad_offset = cfg.bias_region.offset;
      bias_spad_size = cfg.bias_region.size;
      burst_len = (cfg.vip_cfg.max_burst_len > 255) ? 8'hff : cfg.vip_cfg.max_burst_len[7:0];
    end

    `uvm_info(get_type_name(),
              $sformatf("Programming tensor op m=%0d n=%0d k=%0d precision=%0d post_op=%0d sat=%0d",
                        m_size, n_size, k_size, precision, post_op, sat_mode),
              UVM_MEDIUM)

    ral_write(reg_model.M_SIZE, m_size);
    ral_write(reg_model.N_SIZE, n_size);
    ral_write(reg_model.K_SIZE, k_size);
    ral_write(reg_model.PRECISION, {30'd0, precision});
    ral_write(reg_model.POST_OP, {30'd0, post_op});
    ral_write(reg_model.SAT_MODE, {31'd0, sat_mode});
    ral_write(reg_model.A_BASE, a_base);
    ral_write(reg_model.B_BASE, b_base);
    ral_write(reg_model.C_BASE, c_base);
    ral_write(reg_model.BIAS_BASE, bias_base);
    ral_write(reg_model.A_SPAD_OFFSET, a_spad_offset);
    ral_write(reg_model.A_SPAD_SIZE, a_spad_size);
    ral_write(reg_model.B_SPAD_OFFSET, b_spad_offset);
    ral_write(reg_model.B_SPAD_SIZE, b_spad_size);
    ral_write(reg_model.C_SPAD_OFFSET, c_spad_offset);
    ral_write(reg_model.C_SPAD_SIZE, c_spad_size);
    ral_write(reg_model.BIAS_SPAD_OFFSET, bias_spad_offset);
    ral_write(reg_model.BIAS_SPAD_SIZE, bias_spad_size);
    ral_write(reg_model.DMA_CFG, {24'd0, burst_len});
    ral_write(reg_model.CTRL, irq_en ? CTRL_IRQ_EN : 32'd0);
  endtask
endclass

class tensor_start_seq extends base_vseq;
  `uvm_object_utils(tensor_start_seq)

  bit irq_en;

  function new(string name = "tensor_start_seq");
    super.new(name);
    irq_en = 1'b0;
  endfunction

  virtual task body();
    ral_write(reg_model.CTRL, CTRL_START | (irq_en ? CTRL_IRQ_EN : 32'd0));
  endtask
endclass

class tensor_wait_done_seq extends base_vseq;
  `uvm_object_utils(tensor_wait_done_seq)

  rand int unsigned timeout_cycles;
  rand int unsigned poll_interval_cycles;
  bit expect_error;
  bit check_error_code;
  error_code_e exp_error_code;
  bit [31:0] status_data;
  error_code_e error_code;

  constraint c_wait_knobs {
    timeout_cycles inside {[1:1000000]};
    poll_interval_cycles inside {[1:1000]};
  }

  function new(string name = "tensor_wait_done_seq");
    super.new(name);
    timeout_cycles = 10000;
    poll_interval_cycles = 10;
    expect_error = 1'b0;
    check_error_code = 1'b0;
    exp_error_code = ERR_NO_ERROR;
    status_data = 32'd0;
    error_code = ERR_NO_ERROR;
  endfunction

  virtual task body();
    int unsigned elapsed;
    bit terminal_seen;
    bit error_seen;
    bit done_seen;
    bit [31:0] error_data;

    elapsed = 0;
    terminal_seen = 1'b0;
    while (!terminal_seen && elapsed < timeout_cycles) begin
      uvm_reg_data_t read_data;

      ral_read(reg_model.STATUS, read_data);
      status_data = read_data[31:0];
      done_seen = (status_data & STATUS_DONE) != 0;
      error_seen = (status_data & STATUS_ERROR) != 0;
      terminal_seen = done_seen || error_seen;
      if (!terminal_seen) begin
        wait_cfg_clocks(poll_interval_cycles);
        elapsed += poll_interval_cycles;
      end
    end

    if (!terminal_seen) begin
      `uvm_error(get_type_name(),
                 $sformatf("Timed out waiting for tensor op after %0d cycles; status=0x%08x",
                           timeout_cycles, status_data))
      if (cfg != null) cfg.add_seq_check_error();
      return;
    end

    if (error_seen) begin
      uvm_reg_data_t read_data;

      ral_read(reg_model.ERROR_CODE, read_data);
      error_data = read_data[31:0];
      error_code = error_code_e'(error_data[3:0]);
    end

    if (expect_error) begin
      if (!error_seen) begin
        `uvm_error(get_type_name(),
                   $sformatf("Expected error completion, got status=0x%08x", status_data))
        if (cfg != null) cfg.add_seq_check_error();
      end
      else if (check_error_code && error_code != exp_error_code) begin
        `uvm_error(get_type_name(),
                   $sformatf("Unexpected error code exp=%s act=%s",
                             exp_error_code.name(), error_code.name()))
        if (cfg != null) cfg.add_seq_check_error();
      end
      else if (cfg != null) begin
        cfg.add_seq_check_count();
      end
    end
    else begin
      if (!done_seen || error_seen) begin
        `uvm_error(get_type_name(),
                   $sformatf("Expected done completion, got status=0x%08x error=%s",
                             status_data, error_code.name()))
        if (cfg != null) cfg.add_seq_check_error();
      end
      else if (cfg != null) begin
        cfg.add_seq_check_count();
      end
    end
  endtask
endclass

class tensor_clear_status_seq extends base_vseq;
  `uvm_object_utils(tensor_clear_status_seq)

  bit clear_done;
  bit clear_error;
  bit clear_irq;
  bit irq_en;

  function new(string name = "tensor_clear_status_seq");
    super.new(name);
    clear_done = 1'b1;
    clear_error = 1'b1;
    clear_irq = 1'b1;
    irq_en = 1'b0;
  endfunction

  virtual task body();
    bit [31:0] ctrl_data;

    ctrl_data = 32'd0;
    if (irq_en) ctrl_data |= CTRL_IRQ_EN;
    if (clear_done) ctrl_data |= CTRL_CLEAR_DONE;
    if (clear_error) ctrl_data |= CTRL_CLEAR_ERROR;
    ral_write(reg_model.CTRL, ctrl_data);
    if (clear_irq) begin
      ral_write(reg_model.IRQ_STATUS, 32'd1);
    end
  endtask
endclass

class tensor_soft_reset_seq extends base_vseq;
  `uvm_object_utils(tensor_soft_reset_seq)

  bit check_status;

  function new(string name = "tensor_soft_reset_seq");
    super.new(name);
    check_status = 1'b1;
  endfunction

  virtual task body();
    ral_write(reg_model.CTRL, CTRL_SOFT_RESET);
    wait_cfg_clocks(2);
    if (check_status) begin
      ral_check(reg_model.STATUS, 32'd0,
                STATUS_BUSY | STATUS_DONE | STATUS_ERROR | STATUS_IRQ);
      ral_check(reg_model.ERROR_CODE, {28'd0, ERR_NO_ERROR}, 32'h0000_000f);
    end
  endtask
endclass

class tensor_run_basic_seq extends base_vseq;
  `uvm_object_utils(tensor_run_basic_seq)

  rand bit [31:0] m_size;
  rand bit [31:0] n_size;
  rand bit [31:0] k_size;
  rand precision_e precision;
  rand post_op_e post_op;
  rand sat_mode_e sat_mode;
  bit irq_en;
  int unsigned timeout_cycles;

  constraint c_basic_dims {
    m_size inside {[1:MAX_DIM]};
    n_size inside {[1:MAX_DIM]};
    k_size inside {[1:MAX_DIM]};
  }

  function new(string name = "tensor_run_basic_seq");
    super.new(name);
    m_size = 32'd4;
    n_size = 32'd4;
    k_size = 32'd4;
    precision = PREC_INT8;
    post_op = POST_NONE;
    sat_mode = SAT_WRAP;
    irq_en = 1'b0;
    timeout_cycles = 10000;
  endfunction

  virtual task body();
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    tensor_wait_done_seq wait_seq;
    tensor_clear_status_seq clear_seq;

    program_seq = tensor_program_seq::type_id::create("program_seq");
    program_seq.m_size = m_size;
    program_seq.n_size = n_size;
    program_seq.k_size = k_size;
    program_seq.precision = precision;
    program_seq.post_op = post_op;
    program_seq.sat_mode = sat_mode;
    program_seq.irq_en = irq_en;
    program_seq.start(p_sequencer);

    start_seq = tensor_start_seq::type_id::create("start_seq");
    start_seq.irq_en = irq_en;
    start_seq.start(p_sequencer);

    wait_seq = tensor_wait_done_seq::type_id::create("wait_seq");
    wait_seq.timeout_cycles = timeout_cycles;
    wait_seq.expect_error = 1'b0;
    wait_seq.start(p_sequencer);

    clear_seq = tensor_clear_status_seq::type_id::create("clear_seq");
    clear_seq.irq_en = irq_en;
    clear_seq.start(p_sequencer);
  endtask
endclass

`endif
