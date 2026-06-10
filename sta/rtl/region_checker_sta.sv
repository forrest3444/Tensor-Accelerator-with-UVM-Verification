module region_checker #(
  parameter int SPAD_BYTES = 65536,
  parameter int AXI_DATA_WIDTH = 64
) (
  input  logic         clk,
  input  logic         rst_n,
  input  logic [492:0] cfg_i,
  output logic         valid_o,
  output logic [3:0]   error_code_o
);
  localparam int MAX_DIM = 64;

  localparam logic [1:0] PREC_INT8  = 2'd0;
  localparam logic [1:0] PREC_INT16 = 2'd1;

  localparam logic [1:0] POST_BIAS      = 2'd1;
  localparam logic [1:0] POST_RELU      = 2'd2;
  localparam logic [1:0] POST_BIAS_RELU = 2'd3;

  localparam logic [3:0] ERR_NO_ERROR            = 4'h0;
  localparam logic [3:0] ERR_ILLEGAL_MATRIX_SIZE = 4'h1;
  localparam logic [3:0] ERR_ILLEGAL_PRECISION   = 4'h2;
  localparam logic [3:0] ERR_UNALIGNED_BASE_ADDR = 4'h3;
  localparam logic [3:0] ERR_REGION_OVERLAP      = 4'h8;
  localparam logic [3:0] ERR_SPAD_OUT_OF_RANGE   = 4'h9;
  localparam logic [3:0] ERR_REGION_TOO_SMALL    = 4'ha;

  logic [31:0] cfg_m_size;
  logic [31:0] cfg_n_size;
  logic [31:0] cfg_k_size;
  logic [1:0]  cfg_precision;
  logic [1:0]  cfg_post_op;
  logic [31:0] cfg_a_base;
  logic [31:0] cfg_b_base;
  logic [31:0] cfg_c_base;
  logic [31:0] cfg_bias_base;
  logic [31:0] cfg_a_spad_offset;
  logic [31:0] cfg_a_spad_size;
  logic [31:0] cfg_b_spad_offset;
  logic [31:0] cfg_b_spad_size;
  logic [31:0] cfg_c_spad_offset;
  logic [31:0] cfg_c_spad_size;
  logic [31:0] cfg_bias_spad_offset;
  logic [31:0] cfg_bias_spad_size;
  logic [492:0] cfg_q;

  logic [31:0] elem_b;
  logic [31:0] a_need;
  logic [31:0] b_need;
  logic [31:0] c_need;
  logic [31:0] bias_need;
  logic [31:0] beat_bytes;
  logic        valid_d;
  logic [3:0]  error_code_d;
  logic        matrix_ok;
  logic        precision_ok;
  logic        align_ok;
  logic        range_ok;
  logic        size_ok;
  logic        overlap;

  assign cfg_m_size           = cfg_q[492:461];
  assign cfg_n_size           = cfg_q[460:429];
  assign cfg_k_size           = cfg_q[428:397];
  assign cfg_precision        = cfg_q[396:395];
  assign cfg_post_op          = cfg_q[394:393];
  assign cfg_a_base           = cfg_q[391:360];
  assign cfg_b_base           = cfg_q[359:328];
  assign cfg_c_base           = cfg_q[327:296];
  assign cfg_bias_base        = cfg_q[295:264];
  assign cfg_a_spad_offset    = cfg_q[263:232];
  assign cfg_a_spad_size      = cfg_q[231:200];
  assign cfg_b_spad_offset    = cfg_q[199:168];
  assign cfg_b_spad_size      = cfg_q[167:136];
  assign cfg_c_spad_offset    = cfg_q[135:104];
  assign cfg_c_spad_size      = cfg_q[103:72];
  assign cfg_bias_spad_offset = cfg_q[71:40];
  assign cfg_bias_spad_size   = cfg_q[39:8];

  function automatic logic bias_enabled(input logic [1:0] op);
    begin
      bias_enabled = (op == POST_BIAS) || (op == POST_BIAS_RELU);
    end
  endfunction

  function automatic logic region_active(input logic [31:0] size);
    begin
      region_active = size != 32'd0;
    end
  endfunction

  function automatic logic in_range(input logic [31:0] offset, input logic [31:0] size);
    logic [32:0] end_addr;
    begin
      end_addr = {1'b0, offset} + {1'b0, size};
      in_range = (size != 32'd0) && (end_addr <= {1'b0, 32'(SPAD_BYTES)});
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
      overlaps = region_active(size0) && region_active(size1) &&
                 ({1'b0, off0} < end1) && ({1'b0, off1} < end0);
    end
  endfunction

  always_comb begin
    elem_b = (cfg_precision == PREC_INT16) ? 32'd2 : 32'd1;
    beat_bytes = AXI_DATA_WIDTH / 8;
    a_need = cfg_m_size * cfg_k_size * elem_b;
    b_need = cfg_k_size * cfg_n_size * elem_b;
    c_need = cfg_m_size * cfg_n_size * 32'd4;
    bias_need = bias_enabled(cfg_post_op) ? (cfg_n_size * 32'd4) : 32'd0;

    matrix_ok = (cfg_m_size >= 1 && cfg_m_size <= MAX_DIM &&
                 cfg_n_size >= 1 && cfg_n_size <= MAX_DIM &&
                 cfg_k_size >= 1 && cfg_k_size <= MAX_DIM);
    precision_ok = (cfg_precision == PREC_INT8) || (cfg_precision == PREC_INT16);
    align_ok = ((cfg_a_base % beat_bytes) == 0) &&
               ((cfg_b_base % beat_bytes) == 0) &&
               (cfg_c_base[1:0] == 2'b00) &&
               (!bias_enabled(cfg_post_op) || ((cfg_bias_base % beat_bytes) == 0)) &&
               ((cfg_a_spad_offset[1:0] == 2'b00) &&
                (cfg_b_spad_offset[1:0] == 2'b00) &&
                (cfg_c_spad_offset[1:0] == 2'b00) &&
                (!bias_enabled(cfg_post_op) || cfg_bias_spad_offset[1:0] == 2'b00));

    range_ok = in_range(cfg_a_spad_offset, cfg_a_spad_size) &&
               in_range(cfg_b_spad_offset, cfg_b_spad_size) &&
               in_range(cfg_c_spad_offset, cfg_c_spad_size) &&
               (!bias_enabled(cfg_post_op) || in_range(cfg_bias_spad_offset, cfg_bias_spad_size));

    size_ok = cfg_a_spad_size >= a_need &&
              cfg_b_spad_size >= b_need &&
              cfg_c_spad_size >= c_need &&
              (!bias_enabled(cfg_post_op) || cfg_bias_spad_size >= bias_need);

    overlap = overlaps(cfg_a_spad_offset, cfg_a_spad_size, cfg_b_spad_offset, cfg_b_spad_size) ||
              overlaps(cfg_a_spad_offset, cfg_a_spad_size, cfg_c_spad_offset, cfg_c_spad_size) ||
              overlaps(cfg_b_spad_offset, cfg_b_spad_size, cfg_c_spad_offset, cfg_c_spad_size) ||
              (bias_enabled(cfg_post_op) &&
               (overlaps(cfg_bias_spad_offset, cfg_bias_spad_size, cfg_a_spad_offset, cfg_a_spad_size) ||
                overlaps(cfg_bias_spad_offset, cfg_bias_spad_size, cfg_b_spad_offset, cfg_b_spad_size) ||
                overlaps(cfg_bias_spad_offset, cfg_bias_spad_size, cfg_c_spad_offset, cfg_c_spad_size)));

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
