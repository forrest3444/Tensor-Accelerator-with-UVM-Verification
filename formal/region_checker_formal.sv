import tensor_pkg::*;

module region_checker_formal;
  (* gclk *) logic clk;
  logic rst_n = 1'b0;
  logic past_valid = 1'b0;
  logic past_valid2 = 1'b0;
  logic past_valid3 = 1'b0;
  (* anyseq *) logic [31:0] m_size_i;
  (* anyseq *) logic [31:0] n_size_i;
  (* anyseq *) logic [31:0] k_size_i;
  (* anyseq *) logic [1:0]  precision_i;
  (* anyseq *) logic [1:0]  post_op_i;
  (* anyseq *) logic [31:0] a_base_i;
  (* anyseq *) logic [31:0] b_base_i;
  (* anyseq *) logic [31:0] c_base_i;
  (* anyseq *) logic [31:0] bias_base_i;
  logic valid_o;
  logic [3:0] error_code_o;
  logic matrix_ok_now;
  logic precision_ok_now;
  logic align_ok_now;

  region_checker dut (
    .clk(clk),
    .rst_n(rst_n),
    .m_size_i(m_size_i),
    .n_size_i(n_size_i),
    .k_size_i(k_size_i),
    .precision_i(precision_i),
    .post_op_i(post_op_i),
    .a_base_i(a_base_i),
    .b_base_i(b_base_i),
    .c_base_i(c_base_i),
    .bias_base_i(bias_base_i),
    .valid_o(valid_o),
    .error_code_o(error_code_o)
  );

  always_comb begin
    matrix_ok_now = (m_size_i >= 32'd1 && m_size_i <= 32'd64 &&
                     n_size_i >= 32'd1 && n_size_i <= 32'd64 &&
                     k_size_i >= 32'd1 && k_size_i <= 32'd64);
    precision_ok_now = (precision_i == PREC_INT8) ||
                       (precision_i == PREC_INT16) ||
                       (precision_i == PREC_INT4);
    align_ok_now = ((a_base_i % 32'd8) == 32'd0) &&
                   ((b_base_i % 32'd8) == 32'd0) &&
                   (c_base_i[1:0] == 2'b00) &&
                   (!((post_op_i == POST_BIAS) || (post_op_i == POST_BIAS_RELU)) ||
                    ((bias_base_i % 32'd8) == 32'd0));
  end

  always_ff @(posedge clk) begin
    past_valid <= 1'b1;
    past_valid2 <= past_valid;
    past_valid3 <= past_valid2;
    rst_n <= 1'b1;

    if (!past_valid) begin
      assume(!rst_n);
    end else if (past_valid3) begin
      assume(rst_n);

      if ($past(matrix_ok_now && precision_ok_now && align_ok_now, 2)) begin
        assert(valid_o);
        assert(error_code_o == ERR_NO_ERROR);
      end

      if ($past(!matrix_ok_now, 2)) begin
        assert(!valid_o);
        assert(error_code_o == ERR_ILLEGAL_MATRIX_SIZE);
      end

      if ($past(matrix_ok_now && !precision_ok_now, 2)) begin
        assert(!valid_o);
        assert(error_code_o == ERR_ILLEGAL_PRECISION);
      end

      if ($past(matrix_ok_now && precision_ok_now && !align_ok_now, 2)) begin
        assert(!valid_o);
        assert(error_code_o == ERR_UNALIGNED_BASE_ADDR);
      end
    end
  end
endmodule
