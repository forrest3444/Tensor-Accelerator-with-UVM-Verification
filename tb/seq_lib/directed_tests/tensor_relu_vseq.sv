`ifndef TENSOR_ACCEL_RELU_VSEQ_SV
`define TENSOR_ACCEL_RELU_VSEQ_SV

class tensor_relu_vseq extends tensor_matmul_vseq;
  `uvm_object_utils(tensor_relu_vseq)

  function new(string name = "tensor_relu_vseq");
    super.new(name);
    post_op = POST_RELU;
  endfunction

  virtual function void compute_reference(const ref int signed a_data[],
                                          const ref int signed b_data[],
                                          ref int signed golden_c[]);
    super.compute_reference(a_data, b_data, golden_c);
    foreach (golden_c[idx]) begin
      if (golden_c[idx] < 0) begin
        golden_c[idx] = 0;
      end
    end
  endfunction
endclass

`endif
