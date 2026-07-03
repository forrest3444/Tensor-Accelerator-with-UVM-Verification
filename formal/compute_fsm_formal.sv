module compute_fsm_formal;
  localparam int COMPUTE_PIPE_LATENCY = 2;
  localparam int ARRAY_M = 2;
  localparam int ARRAY_N = 2;
  localparam int DRAIN = ARRAY_M + ARRAY_N - 2;

  (* gclk *) logic clk;
  logic rst_n = 1'b0;
  logic past_valid = 1'b0;
  (* anyseq *) logic clear_i;
  (* anyseq *) logic start_i;
  (* anyseq *) logic [7:0] k_limit_i;
  logic launch_o;
  logic active_o;
  logic valid_o;
  logic done_o;
  logic [7:0] count_o;

  compute_fsm #(
    .COMPUTE_PIPE_LATENCY(COMPUTE_PIPE_LATENCY),
    .ARRAY_M(ARRAY_M),
    .ARRAY_N(ARRAY_N)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(clear_i),
    .start_i(start_i),
    .k_limit_i(k_limit_i),
    .launch_o(launch_o),
    .active_o(active_o),
    .valid_o(valid_o),
    .done_o(done_o),
    .count_o(count_o)
  );

  always_ff @(posedge clk) begin
    past_valid <= 1'b1;
    rst_n <= 1'b1;

    if (!past_valid) begin
      assume(!rst_n);
    end else begin
      assume(rst_n);
      assume(k_limit_i <= 8'd6);
      assume(!(start_i && active_o));
      if (active_o) begin
        assume(k_limit_i == $past(k_limit_i));
      end

      assert(!launch_o || start_i);
      assert(!launch_o || !active_o);
      assert(!valid_o || active_o);

      if (active_o && (k_limit_i != 8'd0) &&
          ({1'b0, count_o} <= ({1'b0, k_limit_i} + 9'(DRAIN) - 9'd1))) begin
        assert(valid_o);
      end

      if (active_o &&
          ({1'b0, count_o} > ({1'b0, k_limit_i} + 9'(DRAIN) - 9'd1))) begin
        assert(!valid_o);
      end

      if ($past(clear_i)) begin
        assert(!done_o);
      end
    end
  end
endmodule
