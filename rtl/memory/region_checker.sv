module region_checker
  import tensor_pkg::*;
#(
  parameter int SPAD_BYTES = tensor_pkg::SPAD_BYTES,
  parameter int AXI_DATA_WIDTH = tensor_pkg::AXI_DATA_WIDTH,
  parameter int TILE_M = tensor_pkg::ARRAY_M,
  parameter int TILE_N = tensor_pkg::ARRAY_N,
  parameter int OUT_BYTES = 4,
  parameter int BIAS_BYTES = 4,
  parameter int SPAD_BUFFER_BYTES = 4096,
  parameter int SPAD_FIXED_BYTES = 4 * 4096
) (
  input  logic       clk,
  input  logic       rst_n,
  input  accel_cfg_t cfg_i,
  output logic       valid_o,
  output error_code_e error_code_o
);
  accel_cfg_t cfg_q;
  logic       valid_d;
  error_code_e error_code_d;
  logic [31:0] elem_b;
  logic [31:0] beat_bytes;
  logic        matrix_ok;
  logic        precision_ok;
  logic        align_ok;

  localparam int MAX_ELEM_BYTES = 2;
  localparam int MAX_ROW_BYTES  = (((MAX_DIM * MAX_ELEM_BYTES) + 7) / 8) * 8;
  localparam int MAX_A_BYTES    = TILE_M * MAX_ROW_BYTES;
  localparam int MAX_B_BYTES    = TILE_N * MAX_ROW_BYTES;
  localparam int MAX_BIAS_BYTES = TILE_N * BIAS_BYTES;

  always_comb begin
    elem_b = elem_bytes(cfg_q.precision);
    beat_bytes = AXI_DATA_WIDTH / 8;

    matrix_ok = (cfg_q.m_size >= 1 && cfg_q.m_size <= MAX_DIM &&
                 cfg_q.n_size >= 1 && cfg_q.n_size <= MAX_DIM &&
                 cfg_q.k_size >= 1 && cfg_q.k_size <= MAX_DIM);
    precision_ok = (cfg_q.precision == PREC_INT8) || (cfg_q.precision == PREC_INT16);
    align_ok = ((cfg_q.a_base % beat_bytes) == 0) &&
               ((cfg_q.b_base % beat_bytes) == 0) &&
               (cfg_q.c_base[1:0] == 2'b00) &&
               (!bias_enabled(cfg_q.post_op) || ((cfg_q.bias_base % beat_bytes) == 0));

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

`ifdef ASSERT_ON
  initial begin
    assert (SPAD_FIXED_BYTES <= SPAD_BYTES)
      else $fatal(1, "Fixed scratchpad layout exceeds implemented SPAD capacity");
    assert (MAX_A_BYTES <= SPAD_BUFFER_BYTES)
      else $fatal(1, "A fixed scratchpad buffer is too small for the maximum tile");
    assert (MAX_B_BYTES <= SPAD_BUFFER_BYTES)
      else $fatal(1, "B fixed scratchpad buffer is too small for the maximum tile");
    assert (MAX_BIAS_BYTES <= SPAD_BUFFER_BYTES)
      else $fatal(1, "Bias fixed scratchpad buffer is too small for the maximum tile");
  end
`endif

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cfg_q <= '0;
      valid_o <= 1'b0;
      error_code_o <= ERR_NO_ERROR;
    end else begin
      cfg_q <= cfg_i;
      valid_o <= valid_d;
      error_code_o <= error_code_d;
    end
  end
endmodule
