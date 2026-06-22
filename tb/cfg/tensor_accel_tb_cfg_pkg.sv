package tensor_accel_tb_cfg_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import svt_uvm_pkg::*;
  import svt_axi_uvm_pkg::*;
  import tensor_pkg::*;

  typedef enum int unsigned {
    TB_PROFILE_BASE,
    TB_PROFILE_PERFORMANCE
  } tensor_accel_profile_e;

  class tensor_accel_vip_cfg extends uvm_object;
    `uvm_object_utils(tensor_accel_vip_cfg)

    localparam int unsigned AXIL_MASTER_ID = 0;
    localparam int unsigned AXI_SLAVE_ID   = 0;

    int unsigned axil_addr_width = AXIL_ADDR_WIDTH;
    int unsigned axil_data_width = AXIL_DATA_WIDTH;
    int unsigned axi_addr_width  = AXI_ADDR_WIDTH;
    int unsigned axi_data_width  = AXI_DATA_WIDTH;
    int unsigned axi_id_width    = 1;
    bit          fixed_axi_id    = 1'b1;
    int unsigned max_burst_len   = 16;
    int unsigned rd_outstanding  = 1;
    int unsigned wr_outstanding  = 1;
    longint unsigned axi_slave_addr_bytes = 64'h0000_0000_0010_0000;

    svt_axi_system_configuration axi_sys_cfg;

    function new(string name = "tensor_accel_vip_cfg");
      super.new(name);
      build_axi_system_cfg();
    endfunction

    virtual function void build_axi_system_cfg();
      axi_sys_cfg = svt_axi_system_configuration::type_id::create("axi_sys_cfg");

      axi_sys_cfg.num_masters = 1;
      axi_sys_cfg.num_slaves = 1;
      axi_sys_cfg.system_monitor_enable = 0;
      axi_sys_cfg.create_sub_cfgs(axi_sys_cfg.num_masters, axi_sys_cfg.num_slaves);

      configure_axil_master(axi_sys_cfg.master_cfg[AXIL_MASTER_ID]);
      configure_axi_slave(axi_sys_cfg.slave_cfg[AXI_SLAVE_ID]);
      axi_sys_cfg.set_addr_range(AXI_SLAVE_ID, '0, axi_slave_addr_bytes - 1);
    endfunction

    virtual function void configure_common_port(svt_axi_port_configuration port_cfg);
      port_cfg.protocol_checks_enable = 0;
      port_cfg.protocol_checks_coverage_enable = 0;
      port_cfg.protocol_check_stats_enable = 0;
      port_cfg.transaction_coverage_enable = 0;
      port_cfg.toggle_coverage_enable = 0;
      port_cfg.state_coverage_enable = 0;
      port_cfg.meta_coverage_enable = 0;
      port_cfg.valid_ready_dependency_coverage_enable = 0;
      port_cfg.enable_xml_gen = 0;
      port_cfg.enable_memcore_xml_gen = 0;
      port_cfg.pa_format_type = svt_xml_writer::FSDB;
      port_cfg.silent_mode = 1;
    endfunction

    virtual function void configure_axil_master(svt_axi_port_configuration master_cfg);
      configure_common_port(master_cfg);
      master_cfg.axi_interface_type = svt_axi_port_configuration::AXI4_LITE;
      master_cfg.addr_width = axil_addr_width;
      master_cfg.data_width = axil_data_width;
      master_cfg.id_width = 1;
      master_cfg.num_outstanding_xact = -1;
      master_cfg.num_read_outstanding_xact = rd_outstanding;
      master_cfg.num_write_outstanding_xact = wr_outstanding;
      master_cfg.awlen_enable = 0;
      master_cfg.arlen_enable = 0;
      master_cfg.awsize_enable = 0;
      master_cfg.arsize_enable = 0;
      master_cfg.awburst_enable = 0;
      master_cfg.arburst_enable = 0;
      master_cfg.awlock_enable = 0;
      master_cfg.arlock_enable = 0;
      master_cfg.awcache_enable = 0;
      master_cfg.arcache_enable = 0;
      master_cfg.wlast_enable = 0;
      master_cfg.rlast_enable = 0;
    endfunction

    virtual function void configure_axi_slave(svt_axi_port_configuration slave_cfg);
      configure_common_port(slave_cfg);
      slave_cfg.is_active = 1'b1;
      slave_cfg.axi_interface_type = svt_axi_port_configuration::AXI4;
      slave_cfg.addr_width = axi_addr_width;
      slave_cfg.data_width = axi_data_width;
      slave_cfg.id_width = axi_id_width;
      slave_cfg.exclusive_access_enable = 0;
      slave_cfg.locked_access_enable = 0;
      slave_cfg.mem_type = svt_axi_port_configuration::SV_BASED_SVT_MEM;
      slave_cfg.enable_mem = 1'b1;
      slave_cfg.num_outstanding_xact = -1;
      slave_cfg.num_read_outstanding_xact = rd_outstanding;
      slave_cfg.num_write_outstanding_xact = wr_outstanding;
    endfunction
  endclass

  class tensor_accel_env_cfg extends uvm_object;
    `uvm_object_utils(tensor_accel_env_cfg)

    virtual tensor_accel_dut_if vif;
    virtual svt_axi_master_if   axil_master_vif;
    virtual svt_axi_slave_if    axi_slave_vif;
    svt_axi_mem_system_backdoor axi_slave_mem_bkdr;

    int unsigned seq_check_count;
    int unsigned seq_check_error;
    int unsigned seq_desired_check_count;

    int unsigned scb_check_count;
    int unsigned scb_check_error;
    int unsigned scb_desired_check_count;

    tensor_accel_profile_e profile = TB_PROFILE_BASE;

    tensor_accel_vip_cfg vip_cfg;

    bit has_scoreboard = 1'b1;
    bit has_coverage   = 1'b0;
    bit enable_irq_check = 1'b1;
    bit enable_error_check = 1'b1;
    bit enable_reset_during_task = 1'b1;
    bit enable_svt_vip = 1'b1;

    int unsigned spad_bytes = SPAD_BYTES;
    int unsigned max_m = MAX_DIM;
    int unsigned max_n = MAX_DIM;
    int unsigned max_k = MAX_DIM;

    function new(string name = "tensor_accel_env_cfg");
      super.new(name);
      vip_cfg = tensor_accel_vip_cfg::type_id::create("vip_cfg");
      set_base_profile();
    endfunction

    function void set_base_profile();
      profile = TB_PROFILE_BASE;
      vip_cfg.max_burst_len  = 16;
      vip_cfg.rd_outstanding = 1;
      vip_cfg.wr_outstanding = 1;
      vip_cfg.build_axi_system_cfg();
    endfunction

    function void set_performance_profile();
      profile = TB_PROFILE_PERFORMANCE;
      vip_cfg.max_burst_len  = 256;
      vip_cfg.rd_outstanding = 2;
      vip_cfg.wr_outstanding = 2;
      vip_cfg.build_axi_system_cfg();
    endfunction

    virtual function void add_seq_check_count(int unsigned val = 1);
      seq_check_count += val;
    endfunction

    virtual function void add_seq_check_error(int unsigned val = 1);
      seq_check_error += val;
      add_seq_check_count(val);
    endfunction

    virtual function void add_scb_check_count(int unsigned val = 1);
      scb_check_count += val;
    endfunction

    virtual function void add_scb_check_error(int unsigned val = 1);
      scb_check_error += val;
    endfunction

    virtual function void set_axi_slave_mem_bkdr(svt_axi_mem_system_backdoor bkdr);
      axi_slave_mem_bkdr = bkdr;
    endfunction

    virtual function svt_axi_mem_system_backdoor get_axi_slave_mem_bkdr();
      return axi_slave_mem_bkdr;
    endfunction

    virtual function bit has_axi_slave_mem_bkdr();
      return axi_slave_mem_bkdr != null;
    endfunction
  endclass
endpackage
