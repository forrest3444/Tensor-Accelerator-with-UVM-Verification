module wavefront_feeder #(
  parameter int ARRAY_M = 4,
  parameter int ARRAY_N = 4,
  parameter int MAX_K = 64
) (
  input  logic                     valid_i,
  input  logic [7:0]               count_i,
  input  logic [7:0]               k_limit_i,
  input  logic [ARRAY_M-1:0]       row_valid_i,
  input  logic [ARRAY_N-1:0]       col_valid_i,
  input  logic [ARRAY_M-1:0][MAX_K-1:0][15:0] a_panel_i,
  input  logic [MAX_K-1:0][ARRAY_N-1:0][15:0] b_panel_i,
  output logic [ARRAY_M-1:0][15:0] left_a_o,
  output logic [ARRAY_N-1:0][15:0] top_b_o
);
  always_comb begin
    for (int r = 0; r < ARRAY_M; r++) begin
      left_a_o[r] = 16'd0;
      if (valid_i && row_valid_i[r] &&
          ({1'b0, count_i} >= 9'(r)) &&
          (({1'b0, count_i} - 9'(r)) < {1'b0, k_limit_i})) begin
        left_a_o[r] = a_panel_i[r][count_i - 8'(r)];
      end
    end

    for (int c = 0; c < ARRAY_N; c++) begin
      top_b_o[c] = 16'd0;
      if (valid_i && col_valid_i[c] &&
          ({1'b0, count_i} >= 9'(c)) &&
          (({1'b0, count_i} - 9'(c)) < {1'b0, k_limit_i})) begin
        top_b_o[c] = b_panel_i[count_i - 8'(c)][c];
      end
    end
  end
endmodule
