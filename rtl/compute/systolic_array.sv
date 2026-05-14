module systolic_array #(
  parameter int ARRAY_M = 4,
  parameter int ARRAY_N = 4
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       clear_i,
  input  logic                       valid_i,
  input  logic                       precision_i,
  input  logic [ARRAY_M-1:0]         row_valid_i,
  input  logic [ARRAY_N-1:0]         col_valid_i,
  input  logic [ARRAY_M-1:0][15:0]   a_vec_i,
  input  logic [ARRAY_N-1:0][15:0]   b_vec_i,
  output logic [ARRAY_M-1:0][ARRAY_N-1:0][31:0] acc_o
);
  genvar r;
  genvar c;

  generate
    for (r = 0; r < ARRAY_M; r++) begin : g_row
      for (c = 0; c < ARRAY_N; c++) begin : g_col
        pe u_pe (
          .clk(clk),
          .rst_n(rst_n),
          .clear_i(clear_i),
          .valid_i(valid_i && row_valid_i[r] && col_valid_i[c]),
          .precision_i(precision_i),
          .a_i(a_vec_i[r]),
          .b_i(b_vec_i[c]),
          .acc_o(acc_o[r][c])
        );
      end
    end
  endgenerate
endmodule
