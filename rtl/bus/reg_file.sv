`timescale 1ns/1ps

import tensor_pkg::*;

module reg_file (
  input  logic clk,
  input  logic rst_n,
  input  logic wr_en_i,
  input  logic [15:0] wr_addr_i,
  input  logic [31:0] wr_data_i,
  input  logic rd_en_i,
  input  logic [15:0] rd_addr_i,
  output logic [31:0] rd_data_o,

  input  accel_status_t status_i,
  input  error_code_e error_code_i,
  input  logic [31:0] ovf_count_i,
  output accel_cfg_t cfg_o,
  output logic start_pulse_o,
  output logic soft_reset_pulse_o,
  output logic irq_en_o,
  output logic clear_done_pulse_o,
  output logic clear_error_pulse_o,
  output logic clear_irq_pulse_o
);
  localparam logic [15:0] CTRL             = 16'h0000;
  localparam logic [15:0] STATUS           = 16'h0004;
  localparam logic [15:0] M_SIZE           = 16'h0008;
  localparam logic [15:0] N_SIZE           = 16'h000c;
  localparam logic [15:0] K_SIZE           = 16'h0010;
  localparam logic [15:0] PRECISION        = 16'h0014;
  localparam logic [15:0] POST_OP          = 16'h0018;
  localparam logic [15:0] SAT_MODE         = 16'h001c;
  localparam logic [15:0] A_BASE           = 16'h0020;
  localparam logic [15:0] B_BASE           = 16'h0024;
  localparam logic [15:0] C_BASE           = 16'h0028;
  localparam logic [15:0] BIAS_BASE        = 16'h002c;
  localparam logic [15:0] A_SPAD_OFFSET    = 16'h0030;
  localparam logic [15:0] A_SPAD_SIZE      = 16'h0034;
  localparam logic [15:0] B_SPAD_OFFSET    = 16'h0038;
  localparam logic [15:0] B_SPAD_SIZE      = 16'h003c;
  localparam logic [15:0] C_SPAD_OFFSET    = 16'h0040;
  localparam logic [15:0] C_SPAD_SIZE      = 16'h0044;
  localparam logic [15:0] BIAS_SPAD_OFFSET = 16'h0048;
  localparam logic [15:0] BIAS_SPAD_SIZE   = 16'h004c;
  localparam logic [15:0] DMA_CFG          = 16'h0050;
  localparam logic [15:0] IRQ_STATUS       = 16'h0054;
  localparam logic [15:0] OVF_COUNT        = 16'h0058;
  localparam logic [15:0] ERROR_CODE       = 16'h005c;

  accel_cfg_t cfg_q;

  assign cfg_o = cfg_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cfg_q <= '0;
      cfg_q.burst_len <= 8'd16;
      irq_en_o <= 1'b0;
      start_pulse_o <= 1'b0;
      soft_reset_pulse_o <= 1'b0;
      clear_done_pulse_o <= 1'b0;
      clear_error_pulse_o <= 1'b0;
      clear_irq_pulse_o <= 1'b0;
    end else begin
      start_pulse_o <= 1'b0;
      soft_reset_pulse_o <= 1'b0;
      clear_done_pulse_o <= 1'b0;
      clear_error_pulse_o <= 1'b0;
      clear_irq_pulse_o <= 1'b0;
      if (wr_en_i) begin
        unique case (wr_addr_i)
          CTRL: begin
            start_pulse_o <= wr_data_i[0];
            soft_reset_pulse_o <= wr_data_i[1];
            irq_en_o <= wr_data_i[2];
            clear_done_pulse_o <= wr_data_i[3];
            clear_error_pulse_o <= wr_data_i[4];
          end
          M_SIZE: cfg_q.m_size <= wr_data_i;
          N_SIZE: cfg_q.n_size <= wr_data_i;
          K_SIZE: cfg_q.k_size <= wr_data_i;
          PRECISION: cfg_q.precision <= precision_e'(wr_data_i[1:0]);
          POST_OP: cfg_q.post_op <= post_op_e'(wr_data_i[1:0]);
          SAT_MODE: cfg_q.sat_mode <= sat_mode_e'(wr_data_i[0]);
          A_BASE: cfg_q.a_base <= wr_data_i;
          B_BASE: cfg_q.b_base <= wr_data_i;
          C_BASE: cfg_q.c_base <= wr_data_i;
          BIAS_BASE: cfg_q.bias_base <= wr_data_i;
          A_SPAD_OFFSET: cfg_q.a_spad_offset <= wr_data_i;
          A_SPAD_SIZE: cfg_q.a_spad_size <= wr_data_i;
          B_SPAD_OFFSET: cfg_q.b_spad_offset <= wr_data_i;
          B_SPAD_SIZE: cfg_q.b_spad_size <= wr_data_i;
          C_SPAD_OFFSET: cfg_q.c_spad_offset <= wr_data_i;
          C_SPAD_SIZE: cfg_q.c_spad_size <= wr_data_i;
          BIAS_SPAD_OFFSET: cfg_q.bias_spad_offset <= wr_data_i;
          BIAS_SPAD_SIZE: cfg_q.bias_spad_size <= wr_data_i;
          DMA_CFG: cfg_q.burst_len <= wr_data_i[7:0];
          IRQ_STATUS: clear_irq_pulse_o <= wr_data_i[0];
          default: ;
        endcase
      end
    end
  end

  always_comb begin
    rd_data_o = 32'd0;
    if (rd_en_i) begin
      unique case (rd_addr_i)
        CTRL: rd_data_o = {29'd0, irq_en_o, 2'd0};
        STATUS: rd_data_o = {27'd0, status_i.overflow_seen, status_i.irq,
                             status_i.error, status_i.done, status_i.busy};
        M_SIZE: rd_data_o = cfg_q.m_size;
        N_SIZE: rd_data_o = cfg_q.n_size;
        K_SIZE: rd_data_o = cfg_q.k_size;
        PRECISION: rd_data_o = {30'd0, cfg_q.precision};
        POST_OP: rd_data_o = {30'd0, cfg_q.post_op};
        SAT_MODE: rd_data_o = {31'd0, cfg_q.sat_mode};
        A_BASE: rd_data_o = cfg_q.a_base;
        B_BASE: rd_data_o = cfg_q.b_base;
        C_BASE: rd_data_o = cfg_q.c_base;
        BIAS_BASE: rd_data_o = cfg_q.bias_base;
        A_SPAD_OFFSET: rd_data_o = cfg_q.a_spad_offset;
        A_SPAD_SIZE: rd_data_o = cfg_q.a_spad_size;
        B_SPAD_OFFSET: rd_data_o = cfg_q.b_spad_offset;
        B_SPAD_SIZE: rd_data_o = cfg_q.b_spad_size;
        C_SPAD_OFFSET: rd_data_o = cfg_q.c_spad_offset;
        C_SPAD_SIZE: rd_data_o = cfg_q.c_spad_size;
        BIAS_SPAD_OFFSET: rd_data_o = cfg_q.bias_spad_offset;
        BIAS_SPAD_SIZE: rd_data_o = cfg_q.bias_spad_size;
        DMA_CFG: rd_data_o = {24'd0, cfg_q.burst_len};
        IRQ_STATUS: rd_data_o = {31'd0, status_i.irq};
        OVF_COUNT: rd_data_o = ovf_count_i;
        ERROR_CODE: rd_data_o = {28'd0, error_code_i};
        default: rd_data_o = 32'd0;
      endcase
    end
  end
endmodule
