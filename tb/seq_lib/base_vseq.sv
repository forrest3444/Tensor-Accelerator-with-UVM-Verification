`ifndef TENSOR_ACCEL_BASE_VSEQ_SV
`define TENSOR_ACCEL_BASE_VSEQ_SV

class base_vseq extends svt_axi_system_base_sequence;
  `uvm_object_utils(base_vseq)
  `uvm_declare_p_sequencer(svt_axi_system_sequencer)

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
  tensor_accel_reg_block reg_model;
  svt_axi_mem_system_backdoor axi_slave_mem_bkdr;

  function new(string name = "base_vseq");
    super.new(name);
  endfunction

  virtual task pre_body();
    super.pre_body();
    if (!uvm_config_db #(tensor_accel_env_cfg)::get(null, "uvm_test_top", "cfg", cfg)) begin
      void'(uvm_config_db #(tensor_accel_env_cfg)::get(null, "*", "cfg", cfg));
    end
    if (!uvm_config_db #(tensor_accel_reg_block)::get(null, "uvm_test_top.env", "reg_model", reg_model)) begin
      void'(uvm_config_db #(tensor_accel_reg_block)::get(null, "*", "reg_model", reg_model));
    end
    if (cfg != null) begin
      axi_slave_mem_bkdr = cfg.get_axi_slave_mem_bkdr();
    end
  endtask

  virtual function void check_reg_model();
    if (reg_model == null) begin
      `uvm_fatal(get_type_name(), "No tensor_accel_reg_block found in config DB")
    end
  endfunction

  virtual function void check_axi_slave_mem_bkdr();
    if (cfg != null) begin
      axi_slave_mem_bkdr = cfg.get_axi_slave_mem_bkdr();
    end
    if (axi_slave_mem_bkdr == null) begin
      `uvm_fatal(get_type_name(), "No SVT AXI slave memory backdoor handle found in cfg")
    end
  endfunction

  virtual task ral_write(uvm_reg reg_h, uvm_reg_data_t data);
    uvm_status_e status;

    check_reg_model();
    if (reg_h == null) begin
      `uvm_fatal(get_type_name(), "Attempted RAL write through a null register handle")
    end

    `uvm_info(get_type_name(),
              $sformatf("RAL write %s data=0x%08x", reg_h.get_full_name(), data[31:0]),
              UVM_HIGH)
    reg_h.write(status, data, UVM_FRONTDOOR, reg_model.default_map, this);
    if (status != UVM_IS_OK) begin
      `uvm_error(get_type_name(),
                 $sformatf("RAL write failed reg=%s status=%s",
                           reg_h.get_full_name(), status.name()))
    end
  endtask

  virtual task ral_read(uvm_reg reg_h, output uvm_reg_data_t data);
    uvm_status_e status;

    check_reg_model();
    if (reg_h == null) begin
      `uvm_fatal(get_type_name(), "Attempted RAL read through a null register handle")
    end

    reg_h.read(status, data, UVM_FRONTDOOR, reg_model.default_map, this);
    if (status != UVM_IS_OK) begin
      `uvm_error(get_type_name(),
                 $sformatf("RAL read failed reg=%s status=%s",
                           reg_h.get_full_name(), status.name()))
      data = '0;
    end
    else begin
      `uvm_info(get_type_name(),
                $sformatf("RAL read %s data=0x%08x", reg_h.get_full_name(), data[31:0]),
                UVM_HIGH)
    end
  endtask

  virtual task ral_check(uvm_reg reg_h, uvm_reg_data_t exp_data,
                         uvm_reg_data_t mask = '1);
    uvm_reg_data_t act_data;

    ral_read(reg_h, act_data);
    if ((act_data & mask) !== (exp_data & mask)) begin
      `uvm_error(get_type_name(),
                 $sformatf("RAL check failed reg=%s exp=0x%08x act=0x%08x mask=0x%08x",
                           reg_h.get_full_name(), exp_data[31:0], act_data[31:0], mask[31:0]))
      if (cfg != null) cfg.add_seq_check_error();
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
