`ifndef TENSOR_ACCEL_ENV_SV
`define TENSOR_ACCEL_ENV_SV

class tensor_accel_env extends uvm_env;
  `uvm_component_utils(tensor_accel_env)

  tensor_accel_env_cfg cfg;
  tensor_accel_ref_model ref_model;
  tensor_accel_scoreboard scoreboard;
  tensor_accel_coverage coverage;
  tensor_perf_monitor perf_monitor;
  svt_axi_system_env axi_system_env;
  tensor_accel_reg_block reg_model;
  tensor_accel_reg_adapter reg_adapter;
  uvm_reg_predictor #(svt_axi_transaction) reg_predictor;

  function new(string name = "tensor_accel_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(tensor_accel_env_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = tensor_accel_env_cfg::type_id::create("cfg");
      `uvm_info("ENV_CFG", "No env cfg found; using default Base Profile cfg", UVM_LOW)
    end

    ref_model = tensor_accel_ref_model::type_id::create("ref_model", this);
    perf_monitor = tensor_perf_monitor::type_id::create("perf_monitor", this);
    if (cfg.has_scoreboard) begin
      uvm_config_db #(tensor_accel_env_cfg)::set(this, "scoreboard", "cfg", cfg);
      scoreboard = tensor_accel_scoreboard::type_id::create("scoreboard", this);
    end
    if (cfg.has_coverage) begin
      uvm_config_db #(tensor_accel_env_cfg)::set(this, "coverage", "cfg", cfg);
      coverage = tensor_accel_coverage::type_id::create("coverage", this);
    end

    reg_model = tensor_accel_reg_block::type_id::create("reg_model");
    reg_model.build();
    reg_model.lock_model();
    reg_model.reset();
    reg_adapter = tensor_accel_reg_adapter::type_id::create("reg_adapter");
    reg_adapter.p_cfg = cfg.vip_cfg.axi_sys_cfg.master_cfg[0];
    reg_predictor = uvm_reg_predictor #(svt_axi_transaction)::type_id::create("reg_predictor", this);
    uvm_config_db #(tensor_accel_reg_block)::set(null, "*", "reg_model", reg_model);

    if (cfg.enable_svt_vip) begin
      uvm_config_db #(uvm_object_wrapper)::set(this,
                                               "axi_system_env.slave[0].sequencer.run_phase",
                                               "default_sequence",
                                               svt_axi_slave_memory_sequence::type_id::get());
      uvm_config_db #(int unsigned)::set(this,
                                         "axi_system_env.slave[0].sequencer.svt_axi_slave_memory_sequence",
                                         "OKAY_wt",
                                         100);
      uvm_config_db #(int unsigned)::set(this,
                                         "axi_system_env.slave[0].sequencer.svt_axi_slave_memory_sequence",
                                         "EXOKAY_wt",
                                         0);
      uvm_config_db #(int unsigned)::set(this,
                                         "axi_system_env.slave[0].sequencer.svt_axi_slave_memory_sequence",
                                         "SLVERR_wt",
                                         0);
      uvm_config_db #(int unsigned)::set(this,
                                         "axi_system_env.slave[0].sequencer.svt_axi_slave_memory_sequence",
                                         "DECERR_wt",
                                         0);
      uvm_config_db #(svt_axi_system_configuration)::set(this,
                                                         "axi_system_env",
                                                         "cfg",
                                                         cfg.vip_cfg.axi_sys_cfg);
      axi_system_env = svt_axi_system_env::type_id::create("axi_system_env", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.enable_svt_vip && axi_system_env != null) begin
      reg_model.default_map.set_sequencer(axi_system_env.master[0].sequencer, reg_adapter);
      reg_model.default_map.set_auto_predict(1);
      reg_predictor.map = reg_model.default_map;
      reg_predictor.adapter = reg_adapter;
      axi_system_env.master[0].monitor.item_started_port.connect(reg_predictor.bus_in);
    end
  endfunction

endclass

`endif
