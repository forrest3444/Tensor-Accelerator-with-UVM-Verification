module pe (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear_i,
  input  logic        valid_i,
  input  logic        precision_i,
  input  logic [15:0] a_i,
  input  logic [15:0] b_i,
  output logic [31:0] acc_o
);
  mac_unit u_mac_unit (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(clear_i),
    .valid_i(valid_i),
    .precision_i(precision_i),
    .a_i(a_i),
    .b_i(b_i),
    .acc_o(acc_o)
  );
endmodule
