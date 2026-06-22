module store_fsm #(
  parameter int TILE_M = 4,
  parameter int ROW_INDEX_WIDTH = (TILE_M <= 2) ? 1 : $clog2(TILE_M),
  parameter int ROW_COUNT_WIDTH = $clog2(TILE_M + 1)
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear_i,
  input  logic start_i,
  input  logic row_ready_i,
  input  logic [ROW_INDEX_WIDTH-1:0] row_ready_index_i,
  input  logic pp_tile_done_i,
  input  logic desc_ready_i,
  input  logic writer_done_i,
  input  logic store_buffer_i,
  input  logic [31:0] c_ext_offset_i,
  input  logic [31:0] tile_rows_i,
  input  logic [31:0] c_row_bytes_i,
  output logic desc_push_o,
  output logic active_o,
  output logic busy_o,
  output logic done_o,
  output logic [31:0] active_c_ext_offset_o,
  output logic [31:0] active_c_row_bytes_o,
  output logic [ROW_COUNT_WIDTH-1:0] active_row_count_o,
  output logic [TILE_M-1:0] active_row_ready_o,
  output logic active_buffer_o
);
  logic active_q;
  logic desc_pushed_q;
  logic store_buffer_q;
  logic [31:0] c_ext_offset_q;
  logic [31:0] tile_rows_q;
  logic [31:0] c_row_bytes_q;
  logic [31:0] active_tile_rows;
  logic [TILE_M-1:0] row_ready_q;
  logic pp_tile_done_q;

  assign active_c_ext_offset_o = start_i ? c_ext_offset_i : c_ext_offset_q;
  assign active_tile_rows = start_i ? tile_rows_i : tile_rows_q;
  assign active_c_row_bytes_o = start_i ? c_row_bytes_i : c_row_bytes_q;
  assign active_row_count_o = ROW_COUNT_WIDTH'(active_tile_rows);
  assign active_row_ready_o = row_ready_q;
  assign active_buffer_o = start_i ? store_buffer_i : store_buffer_q;
  assign desc_push_o = active_q && !desc_pushed_q && row_ready_q[0] && desc_ready_i;
  assign active_o = active_q;
  assign done_o = active_q && writer_done_i;
  assign busy_o = active_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_q <= 1'b0;
      desc_pushed_q <= 1'b0;
      store_buffer_q <= 1'b0;
      c_ext_offset_q <= 32'd0;
      tile_rows_q <= 32'd0;
      c_row_bytes_q <= 32'd0;
      row_ready_q <= '0;
      pp_tile_done_q <= 1'b0;
    end else if (clear_i) begin
      active_q <= 1'b0;
      desc_pushed_q <= 1'b0;
      store_buffer_q <= 1'b0;
      c_ext_offset_q <= 32'd0;
      tile_rows_q <= 32'd0;
      c_row_bytes_q <= 32'd0;
      row_ready_q <= '0;
      pp_tile_done_q <= 1'b0;
    end else begin
      if (start_i && !active_q) begin
        active_q <= 1'b1;
        desc_pushed_q <= 1'b0;
        store_buffer_q <= store_buffer_i;
        c_ext_offset_q <= c_ext_offset_i;
        tile_rows_q <= tile_rows_i;
        c_row_bytes_q <= c_row_bytes_i;
        row_ready_q <= '0;
        pp_tile_done_q <= 1'b0;
      end else if (desc_push_o) begin
        desc_pushed_q <= 1'b1;
      end else if (active_q && writer_done_i) begin
        active_q <= 1'b0;
        desc_pushed_q <= 1'b0;
        row_ready_q <= '0;
        pp_tile_done_q <= 1'b0;
      end
      if (active_q && row_ready_i) begin
        row_ready_q[row_ready_index_i] <= 1'b1;
      end
      if (active_q && pp_tile_done_i) begin
        pp_tile_done_q <= 1'b1;
      end
    end
  end

`ifdef ASSERT_ON
  always_ff @(posedge clk) begin
    if (rst_n && !clear_i) begin
      assert (!(start_i && active_q))
        else $fatal(1, "Store FSM received overlapping store start");
      assert (!(desc_push_o && desc_pushed_q))
        else $fatal(1, "Store FSM pushed duplicate descriptor");
      assert (!(desc_push_o && !row_ready_q[0]))
        else $fatal(1, "Store FSM pushed descriptor before row0 ready");
    end
  end
`endif
endmodule
