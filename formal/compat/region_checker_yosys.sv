import tensor_pkg::*;

module region_checker #(
  parameter int SPAD_BYTES = tensor_pkg::SPAD_BYTES,
  parameter int AXI_DATA_WIDTH = tensor_pkg::AXI_DATA_WIDTH,
  parameter int TILE_M = tensor_pkg::ARRAY_M,
  parameter int TILE_N = tensor_pkg::ARRAY_N,
  parameter int OUT_BYTES = 4,
  parameter int BIAS_BYTES = 4,
  parameter int SPAD_BUFFER_BYTES = 1024,
  parameter int SPAD_FIXED_BYTES = 4 * 1024
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [31:0] m_size_i,
  input  logic [31:0] n_size_i,
  input  logic [31:0] k_size_i,
  input  logic [1:0]  precision_i,
  input  logic [1:0]  post_op_i,
  input  logic [31:0] a_base_i,
  input  logic [31:0] b_base_i,
  input  logic [31:0] c_base_i,
  input  logic [31:0] bias_base_i,
  output logic        valid_o,
  output logic [3:0]  error_code_o
);
  logic valid_d;
  logic [3:0] error_code_d;
  logic [31:0] beat_bytes;
  logic matrix_ok;
  logic precision_ok;
  logic align_ok;
  logic [31:0] m_size_q;
  logic [31:0] n_size_q;
  logic [31:0] k_size_q;
  logic [1:0]  precision_q;
  logic [1:0]  post_op_q;
  logic [31:0] a_base_q;
  logic [31:0] b_base_q;
  logic [31:0] c_base_q;
  logic [31:0] bias_base_q;

  always_comb begin
    beat_bytes = AXI_DATA_WIDTH / 8;
    matrix_ok = (m_size_q >= 1 && m_size_q <= MAX_DIM &&
                 n_size_q >= 1 && n_size_q <= MAX_DIM &&
                 k_size_q >= 1 && k_size_q <= MAX_DIM);
    precision_ok = (precision_q == PREC_INT8) ||
                   (precision_q == PREC_INT16) ||
                   (precision_q == PREC_INT4);
    align_ok = ((a_base_q % beat_bytes) == 0) &&
               ((b_base_q % beat_bytes) == 0) &&
               (c_base_q[1:0] == 2'b00) &&
               (!((post_op_q == POST_BIAS) || (post_op_q == POST_BIAS_RELU)) ||
                ((bias_base_q % beat_bytes) == 0));

    valid_d = 1'b0;
    error_code_d = ERR_NO_ERROR;
    if (!matrix_ok) begin
      error_code_d = ERR_ILLEGAL_MATRIX_SIZE;
    end else if (!precision_ok) begin
      error_code_d = ERR_ILLEGAL_PRECISION;
    end else if (!align_ok) begin
      error_code_d = ERR_UNALIGNED_BASE_ADDR;
    end else begin
      valid_d = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_size_q <= 32'd0;
      n_size_q <= 32'd0;
      k_size_q <= 32'd0;
      precision_q <= 2'd0;
      post_op_q <= 2'd0;
      a_base_q <= 32'd0;
      b_base_q <= 32'd0;
      c_base_q <= 32'd0;
      bias_base_q <= 32'd0;
      valid_o <= 1'b0;
      error_code_o <= ERR_NO_ERROR;
    end else begin
      m_size_q <= m_size_i;
      n_size_q <= n_size_i;
      k_size_q <= k_size_i;
      precision_q <= precision_i;
      post_op_q <= post_op_i;
      a_base_q <= a_base_i;
      b_base_q <= b_base_i;
      c_base_q <= c_base_i;
      bias_base_q <= bias_base_i;
      valid_o <= valid_d;
      error_code_o <= error_code_d;
    end
  end
endmodule
