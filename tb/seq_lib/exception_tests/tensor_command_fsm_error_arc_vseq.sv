`ifndef TENSOR_COMMAND_FSM_ERROR_ARC_VSEQ_SV
`define TENSOR_COMMAND_FSM_ERROR_ARC_VSEQ_SV

class tensor_command_fsm_error_arc_vseq extends base_vseq;
  `uvm_object_utils(tensor_command_fsm_error_arc_vseq)

  typedef enum int {
    ARC_FORCE_START,
    ARC_FORCE_READ_ERROR,
    ARC_FORCE_WRITE_ERROR,
    ARC_FORCE_LOAD_DONE
  } arc_inject_e;

  typedef struct {
    string        name;
    logic [14:0] target_state;
    arc_inject_e inject_kind;
    error_code_e exp_error_code;
    bit [31:0]   m_size;
    bit [31:0]   n_size;
    bit [31:0]   k_size;
  } arc_case_t;

  function new(string name = "tensor_command_fsm_error_arc_vseq");
    super.new(name);
  endfunction

  virtual task body();
    arc_case_t cases[$];

    if (cfg == null || cfg.vif == null) begin
      `uvm_fatal(get_type_name(), "DUT virtual interface is not available")
    end

    cases.push_back('{"prepare_busy_start",
                      cfg.vif.CMD_ST_PREPARE_TILE,
                      ARC_FORCE_START,
                      ERR_COMMAND_WHILE_BUSY,
                      32'd8, 32'd8, 32'd4});
    cases.push_back('{"compute_write_error",
                      cfg.vif.CMD_ST_COMPUTE_TILE,
                      ARC_FORCE_WRITE_ERROR,
                      ERR_AXI_WRITE_ERROR,
                      32'd4, 32'd4, 32'd64});
    cases.push_back('{"pipe_load_read_error",
                      cfg.vif.CMD_ST_PIPE_LOAD,
                      ARC_FORCE_READ_ERROR,
                      ERR_AXI_READ_ERROR,
                      32'd8, 32'd8, 32'd4});
    cases.push_back('{"pipe_wait_compute_write_error",
                      cfg.vif.CMD_ST_PIPE_WAIT_COMPUTE,
                      ARC_FORCE_WRITE_ERROR,
                      ERR_AXI_WRITE_ERROR,
                      32'd8, 32'd8, 32'd64});
    cases.push_back('{"post_process_write_error",
                      cfg.vif.CMD_ST_POST_PROCESS_TILE,
                      ARC_FORCE_WRITE_ERROR,
                      ERR_AXI_WRITE_ERROR,
                      32'd8, 32'd8, 32'd4});

    foreach (cases[i]) begin
      run_arc_case(cases[i]);
    end
  endtask

  protected virtual task run_arc_case(arc_case_t arc_case);
    tensor_program_seq program_seq;
    tensor_start_seq start_seq;
    bit state_reached;

    `uvm_info(get_type_name(),
              $sformatf("Running command FSM error arc case %s target=0x%04x",
                        arc_case.name, arc_case.target_state),
              UVM_MEDIUM)

    program_seq = tensor_program_seq::type_id::create(
        $sformatf("program_seq_%s", arc_case.name));
    program_seq.m_size = arc_case.m_size;
    program_seq.n_size = arc_case.n_size;
    program_seq.k_size = arc_case.k_size;
    program_seq.precision = PREC_INT8;
    program_seq.post_op = POST_NONE;
    program_seq.sat_mode = SAT_WRAP;
    program_seq.a_base = 32'h0001_0000;
    program_seq.b_base = 32'h0002_0000;
    program_seq.c_base = 32'h0003_0000;
    program_seq.bias_base = 32'h0004_0000;
    program_seq.burst_len = 8'd16;
    program_seq.start(p_sequencer);

    start_seq = tensor_start_seq::type_id::create(
        $sformatf("start_seq_%s", arc_case.name));
    start_seq.start(p_sequencer);

    if (arc_case.target_state == cfg.vif.CMD_ST_PIPE_WAIT_COMPUTE) begin
      wait_for_command_state(arc_case.name,
                             cfg.vif.CMD_ST_PIPE_LOAD,
                             5000,
                             state_reached);
      if (!state_reached) begin
        reset_dut_state();
        return;
      end
      inject_one_cycle(ARC_FORCE_LOAD_DONE);
      state_reached = 1'b0;
    end

    wait_for_command_state(arc_case.name, arc_case.target_state, 5000, state_reached);
    if (!state_reached) begin
      reset_dut_state();
      return;
    end
    inject_one_cycle(arc_case.inject_kind);
    wait_for_error_code(arc_case.name, arc_case.exp_error_code, 1000);
    reset_dut_state();
  endtask

  protected virtual task wait_for_command_state(string case_name,
                                                logic [14:0] target_state,
                                                int unsigned timeout_cycles,
                                                output bit reached);
    reached = 1'b0;
    for (int unsigned cycle = 0; cycle < timeout_cycles; cycle++) begin
      wait_cfg_clocks(1);
      if (cfg.vif.command_state == target_state) begin
        `uvm_info(get_type_name(),
                  $sformatf("%s reached command state 0x%04x at cycle %0d",
                            case_name, target_state, cycle),
                  UVM_MEDIUM)
        reached = 1'b1;
        return;
      end
    end

    `uvm_error(get_type_name(),
               $sformatf("%s timed out waiting for command state 0x%04x, current=0x%04x",
                         case_name, target_state, cfg.vif.command_state))
    if (cfg != null) cfg.add_seq_check_error();
  endtask

  protected virtual task inject_one_cycle(arc_inject_e inject_kind);
    case (inject_kind)
      ARC_FORCE_START: begin
        cfg.vif.tb_cmd_force_start <= 1'b1;
      end
      ARC_FORCE_READ_ERROR: begin
        cfg.vif.tb_cmd_force_read_error <= 1'b1;
      end
      ARC_FORCE_WRITE_ERROR: begin
        cfg.vif.tb_cmd_force_write_error <= 1'b1;
      end
      ARC_FORCE_LOAD_DONE: begin
        cfg.vif.tb_cmd_force_load_done <= 1'b1;
      end
      default: begin
        `uvm_error(get_type_name(), "Invalid command FSM arc injection kind")
        if (cfg != null) cfg.add_seq_check_error();
        return;
      end
    endcase
    wait_cfg_clocks(1);
    cfg.vif.tb_cmd_force_start <= 1'b0;
    cfg.vif.tb_cmd_force_read_error <= 1'b0;
    cfg.vif.tb_cmd_force_write_error <= 1'b0;
    cfg.vif.tb_cmd_force_load_done <= 1'b0;
    wait_cfg_clocks(1);
  endtask

  protected virtual task wait_for_error_code(string case_name,
                                             error_code_e expected_error_code,
                                             int unsigned timeout_cycles);
    uvm_reg_data_t status_data;
    uvm_reg_data_t error_data;
    error_code_e actual_error_code;

    for (int unsigned cycle = 0; cycle < timeout_cycles; cycle++) begin
      ral_read(reg_model.STATUS, status_data);
      ral_read(reg_model.ERROR_CODE, error_data);
      actual_error_code = error_code_e'(error_data[3:0]);

      if ((status_data[31:0] & STATUS_ERROR) != 0) begin
        if (actual_error_code != expected_error_code) begin
          `uvm_error(get_type_name(),
                     $sformatf("%s ERROR_CODE mismatch exp=%s act=%s raw=0x%08x",
                               case_name,
                               expected_error_code.name(),
                               actual_error_code.name(),
                               error_data[31:0]))
          if (cfg != null) cfg.add_seq_check_error();
        end else if (cfg != null) begin
          cfg.add_seq_check_count();
        end
        return;
      end

      wait_cfg_clocks(1);
    end

    `uvm_error(get_type_name(),
               $sformatf("%s timed out waiting for STATUS.error", case_name))
    if (cfg != null) cfg.add_seq_check_error();
  endtask

  protected virtual task reset_dut_state();
    if (cfg == null || cfg.vif == null) begin
      `uvm_error(get_type_name(), "Cannot reset DUT: cfg.vif is null")
      if (cfg != null) cfg.add_seq_check_error();
      return;
    end

    cfg.vif.apply_reset(8);
    cfg.vif.tb_cmd_force_start <= 1'b0;
    cfg.vif.tb_cmd_force_read_error <= 1'b0;
    cfg.vif.tb_cmd_force_write_error <= 1'b0;
    cfg.vif.tb_cmd_force_load_done <= 1'b0;
    if (reg_model != null) reg_model.reset();
    wait_cfg_clocks(2);
  endtask
endclass

`endif
