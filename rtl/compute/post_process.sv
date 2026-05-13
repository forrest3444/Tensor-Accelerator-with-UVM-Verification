`timescale 1ns/1ps

import tensor_pkg::*;

module post_process #(
  parameter int ARRAY_M = 4,
  parameter int ARRAY_N = 4
) (
  input  logic [1:0] post_op_i,
  input  logic       sat_mode_i,
  input  logic [ARRAY_M-1:0][ARRAY_N-1:0][31:0] acc_i,
  input  logic [ARRAY_N-1:0][31:0] bias_i,
  output logic [ARRAY_M-1:0][ARRAY_N-1:0][31:0] result_o,
  output logic overflow_o
);
  logic [ARRAY_M-1:0][ARRAY_N-1:0] ovf;

  genvar r;
  genvar c;
  generate
    for (r = 0; r < ARRAY_M; r++) begin : g_pp_row
      for (c = 0; c < ARRAY_N; c++) begin : g_pp_col
        logic signed [39:0] biased;
        logic signed [39:0] relu_data;
        logic signed [31:0] sat_data;

        always_comb begin
          biased = {{8{acc_i[r][c][31]}}, acc_i[r][c]};
          if (post_op_i == POST_BIAS || post_op_i == POST_BIAS_RELU) begin
            biased = biased + {{8{bias_i[c][31]}}, bias_i[c]};
          end
          if ((post_op_i == POST_RELU || post_op_i == POST_BIAS_RELU) && biased[39]) begin
            relu_data = 40'sd0;
          end else begin
            relu_data = biased;
          end
        end

        saturate #(
          .IN_WIDTH(40),
          .OUT_WIDTH(32)
        ) u_saturate (
          .data_i(relu_data),
          .saturate_en_i(sat_mode_i),
          .data_o(sat_data),
          .overflow_o(ovf[r][c])
        );

        assign result_o[r][c] = sat_data;
      end
    end
  endgenerate

  always_comb begin
    overflow_o = 1'b0;
    for (int rr = 0; rr < ARRAY_M; rr++) begin
      for (int cc = 0; cc < ARRAY_N; cc++) begin
        overflow_o |= ovf[rr][cc];
      end
    end
  end
endmodule
