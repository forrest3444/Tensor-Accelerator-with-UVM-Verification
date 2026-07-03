module wavefront_feeder_formal;
  localparam int ARRAY_M = 3;
  localparam int ARRAY_N = 3;
  localparam int MAX_K = 5;

  (* anyseq *) logic valid_i;
  (* anyseq *) logic [7:0] count_i;
  (* anyseq *) logic [7:0] k_limit_i;
  (* anyseq *) logic [ARRAY_M-1:0] row_valid_i;
  (* anyseq *) logic [ARRAY_N-1:0] col_valid_i;
  (* anyseq *) logic [ARRAY_M-1:0][MAX_K-1:0][15:0] a_panel_i;
  (* anyseq *) logic [MAX_K-1:0][ARRAY_N-1:0][15:0] b_panel_i;

  logic [ARRAY_M-1:0][15:0] left_a_o;
  logic [ARRAY_N-1:0][15:0] top_b_o;

  wavefront_feeder #(
    .ARRAY_M(ARRAY_M),
    .ARRAY_N(ARRAY_N),
    .MAX_K(MAX_K)
  ) dut (
    .valid_i(valid_i),
    .count_i(count_i),
    .k_limit_i(k_limit_i),
    .row_valid_i(row_valid_i),
    .col_valid_i(col_valid_i),
    .a_panel_i(a_panel_i),
    .b_panel_i(b_panel_i),
    .left_a_o(left_a_o),
    .top_b_o(top_b_o)
  );

  always_comb begin
    assume(k_limit_i <= 8'(MAX_K));
    assume(count_i <= 8'(MAX_K + ARRAY_M + ARRAY_N));

    for (int r = 0; r < ARRAY_M; r++) begin
      if (valid_i && row_valid_i[r] &&
          ({1'b0, count_i} >= 9'(r)) &&
          (({1'b0, count_i} - 9'(r)) < {1'b0, k_limit_i})) begin
        assert(left_a_o[r] == a_panel_i[r][count_i - 8'(r)]);
      end else begin
        assert(left_a_o[r] == 16'd0);
      end
    end

    for (int c = 0; c < ARRAY_N; c++) begin
      if (valid_i && col_valid_i[c] &&
          ({1'b0, count_i} >= 9'(c)) &&
          (({1'b0, count_i} - 9'(c)) < {1'b0, k_limit_i})) begin
        assert(top_b_o[c] == b_panel_i[count_i - 8'(c)][c]);
      end else begin
        assert(top_b_o[c] == 16'd0);
      end
    end
  end
endmodule
