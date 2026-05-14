module mac_unit (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear_i,
  input  logic        valid_i,
  input  logic        precision_i,
  input  logic [15:0] a_i,
  input  logic [15:0] b_i,
  output logic [31:0] acc_o
);
  logic signed [31:0] a_ext;
  logic signed [31:0] b_ext;
  logic signed [31:0] product;

  always_comb begin
    if (precision_i) begin
      a_ext = {{16{a_i[15]}}, a_i};
      b_ext = {{16{b_i[15]}}, b_i};
    end else begin
      a_ext = {{24{a_i[7]}}, a_i[7:0]};
      b_ext = {{24{b_i[7]}}, b_i[7:0]};
    end
    product = a_ext * b_ext;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_o <= 32'd0;
    end else if (clear_i) begin
      acc_o <= 32'd0;
    end else if (valid_i) begin
      acc_o <= $signed(acc_o) + product;
    end
  end
endmodule
