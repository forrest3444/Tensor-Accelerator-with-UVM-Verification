module region_checker
  import tensor_pkg::*;
#(
  parameter int SPAD_BYTES = tensor_pkg::SPAD_BYTES,
  parameter int AXI_DATA_WIDTH = tensor_pkg::AXI_DATA_WIDTH
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
  logic [31:0] a_need;
  logic [31:0] b_need;
  logic [31:0] c_need;
  logic [31:0] bias_need;
  logic [31:0] beat_bytes;
  logic        matrix_ok;
  logic        precision_ok;
  logic        align_ok;
  logic        range_ok;
  logic        size_ok;
  logic        overlap;

  function automatic logic region_active(input logic [31:0] size);
    return size != 32'd0;
  endfunction

  function automatic logic in_range(input logic [31:0] offset, input logic [31:0] size);
    logic [32:0] end_addr;
    begin
      end_addr = {1'b0, offset} + {1'b0, size};
      return (size != 32'd0) && (end_addr <= {1'b0, 32'(SPAD_BYTES)});
    end
  endfunction

  function automatic logic overlaps(
    input logic [31:0] off0,
    input logic [31:0] size0,
    input logic [31:0] off1,
    input logic [31:0] size1
  );
    logic [32:0] end0;
    logic [32:0] end1;
    begin
      end0 = {1'b0, off0} + {1'b0, size0};
      end1 = {1'b0, off1} + {1'b0, size1};
      return region_active(size0) && region_active(size1) &&
             ({1'b0, off0} < end1) && ({1'b0, off1} < end0);
    end
  endfunction

  always_comb begin
    elem_b = elem_bytes(cfg_q.precision);
    beat_bytes = AXI_DATA_WIDTH / 8;
    a_need = cfg_q.m_size * cfg_q.k_size * elem_b;
    b_need = cfg_q.k_size * cfg_q.n_size * elem_b;
    c_need = cfg_q.m_size * cfg_q.n_size * 32'd4;
    bias_need = bias_enabled(cfg_q.post_op) ? (cfg_q.n_size * 32'd4) : 32'd0;

    matrix_ok = (cfg_q.m_size >= 1 && cfg_q.m_size <= MAX_DIM &&
                 cfg_q.n_size >= 1 && cfg_q.n_size <= MAX_DIM &&
                 cfg_q.k_size >= 1 && cfg_q.k_size <= MAX_DIM);
    precision_ok = (cfg_q.precision == PREC_INT8) || (cfg_q.precision == PREC_INT16);
    align_ok = ((cfg_q.a_base % beat_bytes) == 0) &&
               ((cfg_q.b_base % beat_bytes) == 0) &&
               (cfg_q.c_base[1:0] == 2'b00) &&
               (!bias_enabled(cfg_q.post_op) || ((cfg_q.bias_base % beat_bytes) == 0)) &&
               ((cfg_q.a_spad_offset[1:0] == 2'b00) &&
                (cfg_q.b_spad_offset[1:0] == 2'b00) &&
                (cfg_q.c_spad_offset[1:0] == 2'b00) &&
                (!bias_enabled(cfg_q.post_op) || cfg_q.bias_spad_offset[1:0] == 2'b00));

    range_ok = in_range(cfg_q.a_spad_offset, cfg_q.a_spad_size) &&
               in_range(cfg_q.b_spad_offset, cfg_q.b_spad_size) &&
               in_range(cfg_q.c_spad_offset, cfg_q.c_spad_size) &&
               (!bias_enabled(cfg_q.post_op) || in_range(cfg_q.bias_spad_offset, cfg_q.bias_spad_size));

    size_ok = cfg_q.a_spad_size >= a_need &&
              cfg_q.b_spad_size >= b_need &&
              cfg_q.c_spad_size >= c_need &&
              (!bias_enabled(cfg_q.post_op) || cfg_q.bias_spad_size >= bias_need);

    overlap = overlaps(cfg_q.a_spad_offset, cfg_q.a_spad_size, cfg_q.b_spad_offset, cfg_q.b_spad_size) ||
              overlaps(cfg_q.a_spad_offset, cfg_q.a_spad_size, cfg_q.c_spad_offset, cfg_q.c_spad_size) ||
              overlaps(cfg_q.b_spad_offset, cfg_q.b_spad_size, cfg_q.c_spad_offset, cfg_q.c_spad_size) ||
              (bias_enabled(cfg_q.post_op) &&
               (overlaps(cfg_q.bias_spad_offset, cfg_q.bias_spad_size, cfg_q.a_spad_offset, cfg_q.a_spad_size) ||
                overlaps(cfg_q.bias_spad_offset, cfg_q.bias_spad_size, cfg_q.b_spad_offset, cfg_q.b_spad_size) ||
                overlaps(cfg_q.bias_spad_offset, cfg_q.bias_spad_size, cfg_q.c_spad_offset, cfg_q.c_spad_size)));

    valid_d = 1'b0;
    error_code_d = ERR_NO_ERROR;
    if (!matrix_ok) begin
      error_code_d = ERR_ILLEGAL_MATRIX_SIZE;
    end else if (!precision_ok) begin
      error_code_d = ERR_ILLEGAL_PRECISION;
    end else if (!align_ok) begin
      error_code_d = ERR_UNALIGNED_BASE_ADDR;
    end else if (!range_ok) begin
      error_code_d = ERR_SPAD_OUT_OF_RANGE;
    end else if (overlap) begin
      error_code_d = ERR_REGION_OVERLAP;
    end else if (!size_ok) begin
      error_code_d = ERR_REGION_TOO_SMALL;
    end else begin
      valid_d = 1'b1;
    end
  end

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
