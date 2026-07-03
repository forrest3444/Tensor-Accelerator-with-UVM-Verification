import tensor_pkg::*;

module pe (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear_i,
  input  logic        valid_i,
  input  logic [1:0]  precision_i,
  input  logic [15:0] a_i,
  input  logic [15:0] b_i,
  output logic [15:0] a_o,
  output logic [15:0] b_o,
  output logic signed [39:0] acc_o,
  output logic        overflow_o
);
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_o <= 16'd0;
      b_o <= 16'd0;
    end else if (clear_i) begin
      a_o <= 16'd0;
      b_o <= 16'd0;
    end else begin
      a_o <= a_i;
      b_o <= b_i;
    end
  end

  mac_unit u_mac_unit (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(clear_i),
    .valid_i(valid_i),
    .precision_i(precision_i),
    .a_i(a_i),
    .b_i(b_i),
    .acc_o(acc_o),
    .overflow_o(overflow_o)
  );
endmodule
