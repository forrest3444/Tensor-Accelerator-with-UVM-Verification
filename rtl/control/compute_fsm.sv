module compute_fsm #(
  parameter int COMPUTE_PIPE_LATENCY = 4,
  parameter int ARRAY_M = 4,
  parameter int ARRAY_N = 4
)
(
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,
  input  logic start_i,
  input  logic [7:0] k_limit_i,
  output logic launch_o,
  output logic active_o,
  output logic valid_o,
  output logic done_o,
  output logic [7:0] count_o
);
  logic active_q;
  logic [7:0] count_q;
  logic array_done;
  logic array_done_q;
  logic [8:0] valid_last_count;
  logic [8:0] done_count;

  localparam int SYSTOLIC_DRAIN_CYCLES = ARRAY_M + ARRAY_N - 2;

  assign launch_o = start_i && !active_q && !done_o;
  assign active_o = active_q;
  assign count_o = count_q;
  assign valid_last_count = {1'b0, k_limit_i} + 9'(SYSTOLIC_DRAIN_CYCLES) - 9'd1;
  assign done_count = {1'b0, k_limit_i} + 9'(SYSTOLIC_DRAIN_CYCLES) +
                      9'(COMPUTE_PIPE_LATENCY);
  assign valid_o = active_q && (k_limit_i != 8'd0) && ({1'b0, count_q} <= valid_last_count);
  assign array_done = active_q && ({1'b0, count_q} == done_count);
  assign done_o = array_done_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_q <= 1'b0;
      count_q <= 8'd0;
    end else if (clear_i) begin
      active_q <= 1'b0;
      count_q <= 8'd0;
    end else if (launch_o) begin
      active_q <= 1'b1;
      count_q <= 8'd0;
    end else if (active_q) begin
      count_q <= count_q + 1'b1;
      if (array_done) begin
        active_q <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      array_done_q <= 1'b0;
    end else if (clear_i) begin
      array_done_q <= 1'b0;
    end else begin
      array_done_q <= array_done;
    end
  end
endmodule
