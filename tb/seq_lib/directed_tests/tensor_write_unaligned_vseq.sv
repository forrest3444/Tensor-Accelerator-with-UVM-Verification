`ifndef TENSOR_ACCEL_WRITE_UNALIGNED_VSEQ_SV
`define TENSOR_ACCEL_WRITE_UNALIGNED_VSEQ_SV

class tensor_write_unaligned_vseq extends tensor_matmul_vseq;
  `uvm_object_utils(tensor_write_unaligned_vseq)

  localparam bit [31:0] ALIGNED_C_BASE = 32'h0003_0000;
  localparam bit [7:0]  POISON_BYTE    = 8'ha5;

  function new(string name = "tensor_write_unaligned_vseq");
    super.new(name);
    m_size = 32'd1;
    n_size = 32'd4;
    k_size = 32'd4;
    precision = PREC_INT8;
    post_op = POST_NONE;
    sat_mode = SAT_WRAP;
    a_base = 32'h0001_0000;
    b_base = 32'h0002_0000;
    c_base = 32'h0003_0004;
    bias_base = 32'h0004_0000;
    burst_len = 8'd16;
    timeout_cycles = 20000;
    poll_interval_cycles = 100;
  endfunction

  virtual task body();
    fork
      monitor_c_write_wstrb();
      super.body();
    join
  endtask

  virtual task poison_c_memory();
    bit [7:0] c_window[];

    c_window = new[24];
    foreach (c_window[idx]) begin
      c_window[idx] = POISON_BYTE;
    end
    env.axi_system_env.slave[0].write_num_byte(ALIGNED_C_BASE,
                                               c_window.size(),
                                               c_window);
  endtask

  virtual task compare_c_memory(const ref int signed golden_c[],
                                const ref int signed actual_c[]);
    super.compare_c_memory(golden_c, actual_c);
    check_guard_bytes();
  endtask

  virtual task monitor_c_write_wstrb();
    bit found_aw;
    int unsigned beat_idx;
    int unsigned wait_cycles;

    if (cfg == null || cfg.vif == null || cfg.axi_slave_vif == null) begin
      `uvm_fatal(get_type_name(), "No AXI slave virtual interface available for WSTRB check")
    end

    found_aw = 1'b0;
    for (wait_cycles = 0; wait_cycles < effective_timeout_cycles(); wait_cycles++) begin
      @(posedge cfg.vif.clk);
      if (cfg.axi_slave_vif.awvalid && cfg.axi_slave_vif.awready &&
          cfg.axi_slave_vif.awaddr[31:0] == ALIGNED_C_BASE) begin
        found_aw = 1'b1;
        `uvm_info(get_type_name(),
                  $sformatf("Observed C write AWADDR=0x%08x AWLEN=%0d AWSIZE=%0d",
                            cfg.axi_slave_vif.awaddr[31:0],
                            cfg.axi_slave_vif.awlen[7:0],
                            cfg.axi_slave_vif.awsize[2:0]),
                  UVM_LOW)
        check_aw_fields(cfg.axi_slave_vif.awaddr[31:0],
                        cfg.axi_slave_vif.awlen[7:0],
                        cfg.axi_slave_vif.awsize[2:0]);
        break;
      end
    end

    if (!found_aw) begin
      `uvm_error(get_type_name(), "Did not observe C write AW handshake")
      if (cfg != null) cfg.add_seq_check_error();
      return;
    end

    beat_idx = 0;
    while (beat_idx < 3) begin
      @(posedge cfg.vif.clk);
      if (cfg.axi_slave_vif.wvalid && cfg.axi_slave_vif.wready) begin
        check_w_beat(beat_idx,
                     cfg.axi_slave_vif.wstrb[7:0],
                     cfg.axi_slave_vif.wlast);
        beat_idx++;
      end
    end
  endtask

  virtual function void check_aw_fields(bit [31:0] awaddr,
                                        bit [7:0] awlen,
                                        bit [2:0] awsize);
    if (awaddr !== ALIGNED_C_BASE) begin
      `uvm_error(get_type_name(),
                 $sformatf("Unexpected AWADDR exp=0x%08x act=0x%08x",
                           ALIGNED_C_BASE, awaddr))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (awlen !== 8'd2) begin
      `uvm_error(get_type_name(),
                 $sformatf("Unexpected AWLEN exp=2 act=%0d", awlen))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (awsize !== 3'd3) begin
      `uvm_error(get_type_name(),
                 $sformatf("Unexpected AWSIZE exp=3 act=%0d", awsize))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endfunction

  virtual function void check_w_beat(int unsigned beat_idx,
                                     bit [7:0] wstrb,
                                     bit wlast);
    bit [7:0] exp_wstrb;
    bit exp_wlast;

    exp_wstrb = expected_wstrb(beat_idx);
    exp_wlast = (beat_idx == 2);

    `uvm_info(get_type_name(),
              $sformatf("Observed C write beat %0d WSTRB=0x%02x WLAST=%0b",
                        beat_idx, wstrb, wlast),
              UVM_LOW)

    if (wstrb !== exp_wstrb) begin
      `uvm_error(get_type_name(),
                 $sformatf("Beat %0d WSTRB mismatch exp=0x%02x act=0x%02x",
                           beat_idx, exp_wstrb, wstrb))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end

    if (wlast !== exp_wlast) begin
      `uvm_error(get_type_name(),
                 $sformatf("Beat %0d WLAST mismatch exp=%0b act=%0b",
                           beat_idx, exp_wlast, wlast))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endfunction

  virtual function bit [7:0] expected_wstrb(int unsigned beat_idx);
    case (beat_idx)
      0: return 8'hf0;
      1: return 8'hff;
      2: return 8'h0f;
      default: return 8'h00;
    endcase
  endfunction

  virtual task check_guard_bytes();
    bit [7:0] c_window[];

    c_window = new[24];
    env.axi_system_env.slave[0].read_num_byte(ALIGNED_C_BASE,
                                              c_window.size(),
                                              c_window);

    for (int idx = 0; idx < 4; idx++) begin
      check_guard_byte(idx, c_window[idx]);
    end
    for (int idx = 20; idx < 24; idx++) begin
      check_guard_byte(idx, c_window[idx]);
    end
  endtask

  virtual function void check_guard_byte(int unsigned byte_idx, bit [7:0] data);
    if (data !== POISON_BYTE) begin
      `uvm_error(get_type_name(),
                 $sformatf("C guard byte offset %0d changed exp=0x%02x act=0x%02x",
                           byte_idx, POISON_BYTE, data))
      if (cfg != null) cfg.add_seq_check_error();
    end else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endfunction
endclass

`endif
