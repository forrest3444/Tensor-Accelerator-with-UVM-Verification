interface tensor_accel_dut_if(input logic clk);
  logic rst_n;
  logic irq;
  logic load_active;
  logic compute_active;
  logic store_active;
  logic force_axi_rvalid_low;
  logic axi_rvalid_to_dut;

  task automatic apply_reset(int unsigned cycles = 8);
    rst_n <= 1'b0;
    force_axi_rvalid_low <= 1'b0;
    repeat (cycles) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);
  endtask
endinterface
