module post_process
  import tensor_pkg::*;
#(
  parameter int ARRAY_M = 4,
  parameter int ARRAY_N = 4,
  parameter int ACC_WIDTH = 40
) (
  input  logic clk,
  input  logic rst_n,
  input  logic [1:0] post_op_i,
  input  logic       sat_mode_i,
  input  logic signed [ACC_WIDTH-1:0] acc_i [ARRAY_M-1:0][ARRAY_N-1:0],
  input  logic [ARRAY_N-1:0][31:0] bias_i,
  output logic [ARRAY_M-1:0][ARRAY_N-1:0][31:0] result_o,
  output logic overflow_o
);
  logic [ARRAY_M-1:0][ARRAY_N-1:0] ovf;
  logic [ARRAY_M-1:0][ARRAY_N-1:0] ovf_q;

  genvar r;
  genvar c;
  generate
    for (r = 0; r < ARRAY_M; r++) begin : g_pp_row
      for (c = 0; c < ARRAY_N; c++) begin : g_pp_col
        (* keep = "true" *) logic [1:0] post_op_q;
        (* keep = "true" *) logic sat_mode_q;
        logic relu_en_q;
        logic relu_en_qq;
        logic sat_mode_qq;
        logic sat_mode_qqq;
        logic signed [ACC_WIDTH-1:0] acc_q;
        logic [31:0] bias_q;
        logic signed [39:0] biased;
        logic signed [39:0] biased_q;
        logic signed [39:0] relu_data;
        logic signed [39:0] relu_q;
        logic signed [31:0] sat_data;

        always_comb begin
          biased = acc_q;
          biased = biased + {{8{bias_q[31]}}, bias_q};
          if (relu_en_qq && biased_q[39]) begin
            relu_data = 40'sd0;
          end else begin
            relu_data = biased_q;
          end
        end

        saturate #(
          .IN_WIDTH(40),
          .OUT_WIDTH(32)
        ) u_saturate (
          .data_i(relu_q),
          .saturate_en_i(sat_mode_qqq),
          .data_o(sat_data),
          .overflow_o(ovf[r][c])
        );

        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            post_op_q <= POST_NONE;
            sat_mode_q <= 1'b0;
            relu_en_q <= 1'b0;
            relu_en_qq <= 1'b0;
            sat_mode_qq <= 1'b0;
            sat_mode_qqq <= 1'b0;
            acc_q <= '0;
            bias_q <= 32'd0;
            biased_q <= 40'sd0;
            relu_q <= 40'sd0;
            result_o[r][c] <= 32'd0;
            ovf_q[r][c] <= 1'b0;
          end else begin
            post_op_q <= post_op_i;
            sat_mode_q <= sat_mode_i;
            acc_q <= acc_i[r][c];
            if ((post_op_i == POST_BIAS) || (post_op_i == POST_BIAS_RELU)) begin
              bias_q <= bias_i[c];
            end else begin
              bias_q <= 32'd0;
            end
            relu_en_q <= (post_op_i == POST_RELU) || (post_op_i == POST_BIAS_RELU);
            relu_en_qq <= relu_en_q;
            sat_mode_qq <= sat_mode_q;
            sat_mode_qqq <= sat_mode_qq;
            biased_q <= biased;
            relu_q <= relu_data;
            result_o[r][c] <= sat_data;
            ovf_q[r][c] <= ovf[r][c];
          end
        end
      end
    end
  endgenerate

  always_comb begin
    overflow_o = 1'b0;
    for (int rr = 0; rr < ARRAY_M; rr++) begin
      for (int cc = 0; cc < ARRAY_N; cc++) begin
        overflow_o |= ovf_q[rr][cc];
      end
    end
  end
endmodule
