interface tensor_accel_dut_if(input logic clk);
  logic rst_n;
  logic irq;

  task automatic apply_reset(int unsigned cycles = 8);
    rst_n <= 1'b0;
    repeat (cycles) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);
  endtask
endinterface
