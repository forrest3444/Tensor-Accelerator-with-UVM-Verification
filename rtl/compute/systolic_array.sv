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
  output logic signed [39:0] acc_o [ARRAY_M-1:0][ARRAY_N-1:0],
  output logic                       overflow_o
);
  logic [ARRAY_M-1:0][ARRAY_N-1:0] pe_overflow;

  genvar r;
  genvar c;

  generate
    for (r = 0; r < ARRAY_M; r++) begin : g_row
      for (c = 0; c < ARRAY_N; c++) begin : g_col
        (* keep = "true" *) logic clear_q;
        (* keep = "true" *) logic valid_q;
        (* keep = "true" *) logic precision_q;
        logic [15:0] a_q;
        logic [15:0] b_q;

        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            clear_q <= 1'b0;
            valid_q <= 1'b0;
            precision_q <= 1'b0;
            a_q <= 16'd0;
            b_q <= 16'd0;
          end else begin
            clear_q <= clear_i && row_valid_i[r] && col_valid_i[c];
            valid_q <= valid_i && row_valid_i[r] && col_valid_i[c];
            precision_q <= precision_i && row_valid_i[r] && col_valid_i[c];
            a_q <= a_vec_i[r];
            b_q <= b_vec_i[c];
          end
        end

        pe u_pe (
          .clk(clk),
          .rst_n(rst_n),
          .clear_i(clear_q),
          .valid_i(valid_q),
          .precision_i(precision_q),
          .a_i(a_q),
          .b_i(b_q),
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
