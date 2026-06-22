module post_process_fsm #(
  parameter int TILE_M = 4,
  parameter int TILE_N = 4,
  parameter int ROW_INDEX_WIDTH = (TILE_M <= 2) ? 1 : $clog2(TILE_M),
  parameter int COL_INDEX_WIDTH = (TILE_N <= 2) ? 1 : $clog2(TILE_N),
  parameter int TILE_ELEMS_WIDTH = $clog2((TILE_M * TILE_N) + 1)
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,
  input  logic start_i,
  input  logic [31:0] c_write_bytes_i,
  input  logic [31:0] tile_cols_i,
  input  logic spad_ready_i,
  output logic [ROW_INDEX_WIDTH-1:0] wb_row_o,
  output logic [COL_INDEX_WIDTH-1:0] wb_col_o,
  output logic row_done_valid_o,
  output logic [ROW_INDEX_WIDTH-1:0] row_done_index_o,
  output logic active_o,
  output logic done_o
);
  logic active_q;
  logic [7:0] start_pipe_q;
  logic [TILE_ELEMS_WIDTH-1:0] count_q;
  logic [TILE_ELEMS_WIDTH:0] elems;
  logic last;

  assign elems = TILE_ELEMS_WIDTH'(c_write_bytes_i >> 2);
  assign wb_row_o = (tile_cols_i == 32'd0) ? '0 : ROW_INDEX_WIDTH'(32'(count_q) / tile_cols_i);
  assign wb_col_o = (tile_cols_i == 32'd0) ? '0 : COL_INDEX_WIDTH'(32'(count_q) % tile_cols_i);
  assign last = (elems == '0) || ({1'b0, count_q} == (elems - 1'b1));
  assign row_done_valid_o = active_q && spad_ready_i &&
                             (last || (tile_cols_i != 32'd0 &&
                                       (32'(wb_col_o) == (tile_cols_i - 1'b1))));
  assign row_done_index_o = wb_row_o;
  assign active_o = start_i || (start_pipe_q != 8'd0) || active_q;
  assign done_o = active_q && last && spad_ready_i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_q <= 1'b0;
      start_pipe_q <= 8'd0;
      count_q <= '0;
    end else if (clear_i) begin
      active_q <= 1'b0;
      start_pipe_q <= 8'd0;
      count_q <= '0;
    end else begin
      start_pipe_q <= {start_pipe_q[6:0], start_i && !active_q};
      if (start_pipe_q[7] && !active_q) begin
        active_q <= 1'b1;
        count_q <= '0;
      end else if (active_q && spad_ready_i) begin
        if (last) begin
          active_q <= 1'b0;
          count_q <= '0;
        end else begin
          count_q <= count_q + 1'b1;
        end
      end
    end
  end
endmodule
