module systolic_array
  import tensor_pkg::*;
#(
  parameter int ARRAY_M = 4,
  parameter int ARRAY_N = 4
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       clear_i,
  input  logic                       valid_i,
  input  precision_e                 precision_i,
  input  logic [ARRAY_M-1:0]         row_valid_i,
  input  logic [ARRAY_N-1:0]         col_valid_i,
  input  logic [ARRAY_M-1:0][15:0]   a_vec_i,
  input  logic [ARRAY_N-1:0][15:0]   b_vec_i,
  output logic signed [39:0] acc_o [ARRAY_M-1:0][ARRAY_N-1:0],
  output logic                       overflow_o
);
  logic [ARRAY_M-1:0][ARRAY_N-1:0] pe_overflow;
  logic [ARRAY_M-1:0][ARRAY_N:0][15:0] a_link;
  logic [ARRAY_M:0][ARRAY_N-1:0][15:0] b_link;

  genvar r;
  genvar c;

  generate
    for (r = 0; r < ARRAY_M; r++) begin : g_a_boundary
      assign a_link[r][0] = a_vec_i[r];
    end
    for (c = 0; c < ARRAY_N; c++) begin : g_b_boundary
      assign b_link[0][c] = b_vec_i[c];
    end
  endgenerate

  generate
    for (r = 0; r < ARRAY_M; r++) begin : g_row
      for (c = 0; c < ARRAY_N; c++) begin : g_col
        logic clear_pe;
        logic valid_pe;

        assign clear_pe = clear_i;
        assign valid_pe = valid_i && row_valid_i[r] && col_valid_i[c];

        pe u_pe (
          .clk(clk),
          .rst_n(rst_n),
          .clear_i(clear_pe),
          .valid_i(valid_pe),
          .precision_i(precision_i),
          .a_i(a_link[r][c]),
          .b_i(b_link[r][c]),
          .a_o(a_link[r][c+1]),
          .b_o(b_link[r+1][c]),
          .acc_o(acc_o[r][c]),
          .overflow_o(pe_overflow[r][c])
        );
      end
    end
  endgenerate

  always_comb begin
    overflow_o = 1'b0;
    for (int rr = 0; rr < ARRAY_M; rr++) begin
      for (int cc = 0; cc < ARRAY_N; cc++) begin
      overflow_o |= pe_overflow[rr][cc];
      end
    end
  end
endmodule
