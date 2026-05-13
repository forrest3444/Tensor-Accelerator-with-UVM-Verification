`ifndef TENSOR_ACCEL_BASE_VSEQ_SV
`define TENSOR_ACCEL_BASE_VSEQ_SV

class base_vseq extends svt_axi_system_base_sequence;
  `uvm_object_utils(base_vseq)
  `uvm_declare_p_sequencer(svt_axi_system_sequencer)

  localparam int unsigned AXIL_MASTER_ID = 0;

  localparam bit [31:0] REG_CTRL             = 32'h0000_0000;
  localparam bit [31:0] REG_STATUS           = 32'h0000_0004;
  localparam bit [31:0] REG_M_SIZE           = 32'h0000_0008;
  localparam bit [31:0] REG_N_SIZE           = 32'h0000_000c;
  localparam bit [31:0] REG_K_SIZE           = 32'h0000_0010;
  localparam bit [31:0] REG_PRECISION        = 32'h0000_0014;
  localparam bit [31:0] REG_POST_OP          = 32'h0000_0018;
  localparam bit [31:0] REG_SAT_MODE         = 32'h0000_001c;
  localparam bit [31:0] REG_A_BASE           = 32'h0000_0020;
  localparam bit [31:0] REG_B_BASE           = 32'h0000_0024;
  localparam bit [31:0] REG_C_BASE           = 32'h0000_0028;
  localparam bit [31:0] REG_BIAS_BASE        = 32'h0000_002c;
  localparam bit [31:0] REG_A_SPAD_OFFSET    = 32'h0000_0030;
  localparam bit [31:0] REG_A_SPAD_SIZE      = 32'h0000_0034;
  localparam bit [31:0] REG_B_SPAD_OFFSET    = 32'h0000_0038;
  localparam bit [31:0] REG_B_SPAD_SIZE      = 32'h0000_003c;
  localparam bit [31:0] REG_C_SPAD_OFFSET    = 32'h0000_0040;
  localparam bit [31:0] REG_C_SPAD_SIZE      = 32'h0000_0044;
  localparam bit [31:0] REG_BIAS_SPAD_OFFSET = 32'h0000_0048;
  localparam bit [31:0] REG_BIAS_SPAD_SIZE   = 32'h0000_004c;
  localparam bit [31:0] REG_DMA_CFG          = 32'h0000_0050;
  localparam bit [31:0] REG_IRQ_STATUS       = 32'h0000_0054;
  localparam bit [31:0] REG_OVF_COUNT        = 32'h0000_0058;
  localparam bit [31:0] REG_ERROR_CODE       = 32'h0000_005c;

  localparam bit [31:0] CTRL_START           = 32'h0000_0001;
  localparam bit [31:0] CTRL_SOFT_RESET      = 32'h0000_0002;
  localparam bit [31:0] CTRL_IRQ_EN          = 32'h0000_0004;
  localparam bit [31:0] CTRL_CLEAR_DONE      = 32'h0000_0008;
  localparam bit [31:0] CTRL_CLEAR_ERROR     = 32'h0000_0010;

  localparam bit [31:0] STATUS_BUSY          = 32'h0000_0001;
  localparam bit [31:0] STATUS_DONE          = 32'h0000_0002;
  localparam bit [31:0] STATUS_ERROR         = 32'h0000_0004;
  localparam bit [31:0] STATUS_IRQ           = 32'h0000_0008;
  localparam bit [31:0] STATUS_OVERFLOW_SEEN = 32'h0000_0010;

  tensor_accel_env_cfg cfg;

  function new(string name = "base_vseq");
    super.new(name);
  endfunction

  virtual task pre_body();
    super.pre_body();
    if (!uvm_config_db #(tensor_accel_env_cfg)::get(null, "uvm_test_top", "cfg", cfg)) begin
      void'(uvm_config_db #(tensor_accel_env_cfg)::get(null, "*", "cfg", cfg));
    end
  endtask

  virtual task axil_write_reg(bit [31:0] addr, bit [31:0] data);
    svt_axi_master_transaction wr_tr;

    `uvm_info(get_type_name(),
              $sformatf("AXI-Lite write addr=0x%08x data=0x%08x", addr, data),
              UVM_HIGH)

    `uvm_do_on_with(wr_tr, p_sequencer.master_sequencer[AXIL_MASTER_ID], {
      xact_type        == svt_axi_transaction::WRITE;
      atomic_type      == svt_axi_transaction::NORMAL;
      addr             == local::addr;
      burst_length     == 1;
      burst_size       == svt_axi_transaction::BURST_SIZE_32BIT;
      burst_type       == svt_axi_transaction::INCR;
      data_before_addr == 0;
      data.size()      == 1;
      data[0]          == local::data;
      wstrb.size()     == 1;
      wstrb[0]         == 4'hf;
    })

    wait (wr_tr.write_resp_status == svt_axi_transaction::ACCEPT ||
          wr_tr.write_resp_status == svt_axi_transaction::ABORTED);

    if (wr_tr.write_resp_status != svt_axi_transaction::ACCEPT ||
        wr_tr.bresp != svt_axi_transaction::OKAY) begin
      `uvm_error(get_type_name(),
                 $sformatf("AXI-Lite write failed addr=0x%08x bresp=%s status=%s",
                           addr, wr_tr.bresp.name(), wr_tr.write_resp_status.name()))
    end
  endtask

  virtual task axil_read_reg(bit [31:0] addr, output bit [31:0] data);
    svt_axi_master_transaction rd_tr;

    `uvm_do_on_with(rd_tr, p_sequencer.master_sequencer[AXIL_MASTER_ID], {
      xact_type    == svt_axi_transaction::READ;
      atomic_type  == svt_axi_transaction::NORMAL;
      addr         == local::addr;
      burst_length == 1;
      burst_size   == svt_axi_transaction::BURST_SIZE_32BIT;
      burst_type   == svt_axi_transaction::INCR;
    })

    wait (rd_tr.data_status == svt_axi_transaction::ACCEPT ||
          rd_tr.data_status == svt_axi_transaction::ABORTED);

    if (rd_tr.data_status != svt_axi_transaction::ACCEPT ||
        rd_tr.rresp.size() == 0 ||
        rd_tr.rresp[0] != svt_axi_transaction::OKAY) begin
      `uvm_error(get_type_name(),
                 $sformatf("AXI-Lite read failed addr=0x%08x status=%s",
                           addr, rd_tr.data_status.name()))
      data = '0;
    end
    else begin
      data = rd_tr.data[0][31:0];
      `uvm_info(get_type_name(),
                $sformatf("AXI-Lite read addr=0x%08x data=0x%08x", addr, data),
                UVM_HIGH)
    end
  endtask

  virtual task axil_check_reg(bit [31:0] addr, bit [31:0] exp_data,
                              bit [31:0] mask = 32'hffff_ffff);
    bit [31:0] act_data;

    axil_read_reg(addr, act_data);
    if ((act_data & mask) !== (exp_data & mask)) begin
      `uvm_error(get_type_name(),
                 $sformatf("AXI-Lite check failed addr=0x%08x exp=0x%08x act=0x%08x mask=0x%08x",
                           addr, exp_data, act_data, mask))
    end
    else if (cfg != null) begin
      cfg.add_seq_check_count();
    end
  endtask

  virtual task wait_cfg_clocks(int unsigned cycles);
    if (cfg != null && cfg.vif != null) begin
      repeat (cycles) @(posedge cfg.vif.clk);
    end
    else begin
      #(10ns * cycles);
    end
  endtask
endclass

`endif
