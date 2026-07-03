interface tensor_accel_dut_if(input logic clk);
  logic rst_n;
  logic irq;
  logic load_active;
  logic compute_active;
  logic store_active;
  logic [14:0] command_state;
  logic tb_cmd_force_start;
  logic tb_cmd_force_read_error;
  logic tb_cmd_force_write_error;
  logic tb_cmd_force_load_done;
  logic force_axi_rvalid_low;
  logic axi_rvalid_to_dut;

  localparam logic [14:0] CMD_ST_IDLE              = 15'b000_0000_0000_0001;
  localparam logic [14:0] CMD_ST_CHECK_CONFIG      = 15'b000_0000_0000_0010;
  localparam logic [14:0] CMD_ST_PREPARE_TILE      = 15'b000_0000_0000_0100;
  localparam logic [14:0] CMD_ST_LOAD_TILE         = 15'b000_0000_0000_1000;
  localparam logic [14:0] CMD_ST_COMPUTE_TILE      = 15'b000_0000_0001_0000;
  localparam logic [14:0] CMD_ST_PIPE_ADVANCE      = 15'b000_0000_0010_0000;
  localparam logic [14:0] CMD_ST_PIPE_LOAD         = 15'b000_0000_0100_0000;
  localparam logic [14:0] CMD_ST_PIPE_WAIT_LOAD    = 15'b000_0000_1000_0000;
  localparam logic [14:0] CMD_ST_PIPE_WAIT_COMPUTE = 15'b000_0001_0000_0000;
  localparam logic [14:0] CMD_ST_POST_PROCESS_TILE = 15'b000_0010_0000_0000;
  localparam logic [14:0] CMD_ST_WAIT_STORE_SLOT   = 15'b000_0100_0000_0000;
  localparam logic [14:0] CMD_ST_STORE_TILE        = 15'b000_1000_0000_0000;
  localparam logic [14:0] CMD_ST_WAIT_FINAL_STORE  = 15'b001_0000_0000_0000;
  localparam logic [14:0] CMD_ST_DONE              = 15'b010_0000_0000_0000;
  localparam logic [14:0] CMD_ST_ERROR             = 15'b100_0000_0000_0000;

  task automatic apply_reset(int unsigned cycles = 8);
    rst_n <= 1'b0;
    tb_cmd_force_start <= 1'b0;
    tb_cmd_force_read_error <= 1'b0;
    tb_cmd_force_write_error <= 1'b0;
    tb_cmd_force_load_done <= 1'b0;
    force_axi_rvalid_low <= 1'b0;
    repeat (cycles) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);
  endtask
endinterface
