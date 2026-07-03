import tensor_pkg::*;

module systolic_array_formal;
  localparam int ARRAY_M = 2;
  localparam int ARRAY_N = 2;

  (* gclk *) logic clk;
  logic rst_n = 1'b0;
  logic past_valid = 1'b0;
  (* anyseq *) logic clear_i;
  (* anyseq *) logic valid_i;
  (* anyseq *) logic [1:0] precision_i;
  (* anyseq *) logic [ARRAY_M-1:0] row_valid_i;
  (* anyseq *) logic [ARRAY_N-1:0] col_valid_i;
  (* anyseq *) logic [ARRAY_M-1:0][15:0] a_vec_i;
  (* anyseq *) logic [ARRAY_N-1:0][15:0] b_vec_i;
  logic [(ARRAY_M*ARRAY_N*40)-1:0] acc_o;
  logic overflow_o;

  systolic_array #(
    .ARRAY_M(ARRAY_M),
    .ARRAY_N(ARRAY_N)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(clear_i),
    .valid_i(valid_i),
    .precision_i(precision_i),
    .row_valid_i(row_valid_i),
    .col_valid_i(col_valid_i),
    .a_vec_i(a_vec_i),
    .b_vec_i(b_vec_i),
    .acc_o(acc_o),
    .overflow_o(overflow_o)
  );

  always_ff @(posedge clk) begin
    past_valid <= 1'b1;
    rst_n <= 1'b1;

    if (!past_valid) begin
      assume(!rst_n);
    end else begin
      assume(rst_n);

      if ($past(clear_i)) begin
        assert(acc_o[0 +: 40] == 40'sd0);
        assert(acc_o[40 +: 40] == 40'sd0);
        assert(acc_o[80 +: 40] == 40'sd0);
        assert(acc_o[120 +: 40] == 40'sd0);
        assert(!overflow_o);
      end

    end
  end
endmodule
