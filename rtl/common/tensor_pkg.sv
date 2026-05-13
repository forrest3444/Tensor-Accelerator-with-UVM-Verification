`timescale 1ns/1ps

package tensor_pkg;
  parameter int AXIL_ADDR_WIDTH = 16;
  parameter int AXIL_DATA_WIDTH = 32;
  parameter int AXI_ADDR_WIDTH  = 32;
  parameter int AXI_DATA_WIDTH  = 64;
  parameter int AXI_STRB_WIDTH  = AXI_DATA_WIDTH / 8;
  parameter int SPAD_ADDR_WIDTH = 16;
  parameter int SPAD_DATA_WIDTH = 32;
  parameter int SPAD_BYTES      = 64 * 1024;
  parameter int ARRAY_M         = 4;
  parameter int ARRAY_N         = 4;
  parameter int MAX_DIM         = 64;

  typedef enum logic [1:0] {
    PREC_INT8  = 2'd0,
    PREC_INT16 = 2'd1
  } precision_e;

  typedef enum logic [1:0] {
    POST_NONE      = 2'd0,
    POST_BIAS      = 2'd1,
    POST_RELU      = 2'd2,
    POST_BIAS_RELU = 2'd3
  } post_op_e;

  typedef enum logic {
    SAT_WRAP     = 1'b0,
    SAT_SATURATE = 1'b1
  } sat_mode_e;

  typedef enum logic [3:0] {
    ERR_NO_ERROR            = 4'h0,
    ERR_ILLEGAL_MATRIX_SIZE = 4'h1,
    ERR_ILLEGAL_PRECISION   = 4'h2,
    ERR_UNALIGNED_BASE_ADDR = 4'h3,
    ERR_AXI_READ_ERROR      = 4'h4,
    ERR_AXI_WRITE_ERROR     = 4'h5,
    ERR_COMMAND_WHILE_BUSY  = 4'h6,
    ERR_INTERNAL_TIMEOUT    = 4'h7,
    ERR_REGION_OVERLAP      = 4'h8,
    ERR_SPAD_OUT_OF_RANGE   = 4'h9,
    ERR_REGION_TOO_SMALL    = 4'ha,
    ERR_BURST_CROSS_4KB     = 4'hb
  } error_code_e;

  typedef enum logic [2:0] {
    TENSOR_A    = 3'd0,
    TENSOR_B    = 3'd1,
    TENSOR_C    = 3'd2,
    TENSOR_BIAS = 3'd3
  } tensor_type_e;

  typedef struct packed {
    logic [31:0] m_size;
    logic [31:0] n_size;
    logic [31:0] k_size;
    precision_e precision;
    post_op_e   post_op;
    sat_mode_e  sat_mode;
    logic [31:0] a_base;
    logic [31:0] b_base;
    logic [31:0] c_base;
    logic [31:0] bias_base;
    logic [31:0] a_spad_offset;
    logic [31:0] a_spad_size;
    logic [31:0] b_spad_offset;
    logic [31:0] b_spad_size;
    logic [31:0] c_spad_offset;
    logic [31:0] c_spad_size;
    logic [31:0] bias_spad_offset;
    logic [31:0] bias_spad_size;
    logic [7:0]  burst_len;
  } accel_cfg_t;

  typedef struct packed {
    logic busy;
    logic done;
    logic error;
    logic irq;
    logic overflow_seen;
  } accel_status_t;

  typedef struct packed {
    logic [31:0] addr;
    logic [31:0] byte_len;
    tensor_type_e tensor_type;
    logic [15:0] tile_index;
    logic [31:0] spad_offset;
    logic is_last;
  } dma_desc_t;

  function automatic logic bias_enabled(input post_op_e op);
    return (op == POST_BIAS) || (op == POST_BIAS_RELU);
  endfunction

  function automatic logic relu_enabled(input post_op_e op);
    return (op == POST_RELU) || (op == POST_BIAS_RELU);
  endfunction

  function automatic logic [31:0] elem_bytes(input precision_e precision);
    return (precision == PREC_INT16) ? 32'd2 : 32'd1;
  endfunction

  function automatic logic [31:0] ceil_div4(input logic [31:0] value);
    return (value + 32'd3) >> 2;
  endfunction
endpackage
