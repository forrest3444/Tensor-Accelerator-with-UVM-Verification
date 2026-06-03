module post_process #(
  parameter int ARRAY_M = 4,
  parameter int ARRAY_N = 4,
  parameter int ACC_WIDTH = 40
) (
  input  logic clk,
  input  logic rst_n,
  input  logic [1:0] post_op_i,
  input  logic       sat_mode_i,
  input  logic signed [ARRAY_M*ARRAY_N*ACC_WIDTH-1:0] acc_i,
  input  logic [ARRAY_N*32-1:0] bias_i,
  output logic [ARRAY_M*ARRAY_N*32-1:0] result_o,
  output logic overflow_o
);
  localparam logic [1:0] POST_BIAS      = 2'd1;
  localparam logic [1:0] POST_RELU      = 2'd2;
  localparam logic [1:0] POST_BIAS_RELU = 2'd3;

  logic [ARRAY_M*ARRAY_N-1:0] ovf;
  logic [ARRAY_M*ARRAY_N-1:0] ovf_q;

  genvar r;
  genvar c;
  generate
    for (r = 0; r < ARRAY_M; r++) begin : g_pp_row
      for (c = 0; c < ARRAY_N; c++) begin : g_pp_col
        localparam int CELL = r * ARRAY_N + c;
        (* keep = "true" *) logic [1:0] post_op_q;
        (* keep = "true" *) logic sat_mode_q;
        logic relu_en_q;
        logic relu_en_qq;
        logic sat_mode_qq;
        logic sat_mode_qqq;
        logic signed [ACC_WIDTH-1:0] acc_q;
        logic signed [31:0] bias_q;
        logic signed [39:0] biased;
        logic signed [39:0] biased_q;
        logic signed [39:0] relu_data;
        logic signed [39:0] relu_q;
        logic signed [31:0] sat_data;

        always_comb begin
          biased = acc_q;
          biased = acc_q + {{8{bias_q[31]}}, bias_q};
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
          .overflow_o(ovf[CELL])
        );

        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n) begin
            post_op_q <= 2'd0;
            sat_mode_q <= 1'b0;
            relu_en_q <= 1'b0;
            relu_en_qq <= 1'b0;
            sat_mode_qq <= 1'b0;
            sat_mode_qqq <= 1'b0;
            acc_q <= '0;
            bias_q <= 32'd0;
            biased_q <= 40'sd0;
            relu_q <= 40'sd0;
            result_o[CELL*32 +: 32] <= 32'd0;
            ovf_q[CELL] <= 1'b0;
          end else begin
            post_op_q <= post_op_i;
            sat_mode_q <= sat_mode_i;
            acc_q <= acc_i[CELL*ACC_WIDTH +: ACC_WIDTH];
            if ((post_op_i == POST_BIAS) || (post_op_i == POST_BIAS_RELU)) begin
              bias_q <= bias_i[c*32 +: 32];
            end else begin
              bias_q <= 32'd0;
            end
            relu_en_q <= (post_op_i == POST_RELU) || (post_op_i == POST_BIAS_RELU);
            relu_en_qq <= relu_en_q;
            sat_mode_qq <= sat_mode_q;
            sat_mode_qqq <= sat_mode_qq;
            biased_q <= biased;
            relu_q <= relu_data;
            result_o[CELL*32 +: 32] <= sat_data;
            ovf_q[CELL] <= ovf[CELL];
          end
        end
      end
    end
  endgenerate

  always_comb begin
    overflow_o = 1'b0;
    for (int idx = 0; idx < ARRAY_M * ARRAY_N; idx++) begin
      overflow_o |= ovf_q[idx];
    end
  end
endmodule
