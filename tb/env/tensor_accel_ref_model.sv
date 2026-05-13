`ifndef TENSOR_ACCEL_REF_MODEL_SV
`define TENSOR_ACCEL_REF_MODEL_SV

class tensor_accel_ref_model extends uvm_component;
  `uvm_component_utils(tensor_accel_ref_model)

  function new(string name = "tensor_accel_ref_model", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void predict(ref tensor_accel_matrix_item item);
    int signed acc;
    item.expected_c = new[item.m * item.n];
    for (int row = 0; row < int'(item.m); row++) begin
      for (int col = 0; col < int'(item.n); col++) begin
        acc = 0;
        for (int kk = 0; kk < int'(item.k); kk++) begin
          acc += item.a_data[row * item.k + kk] *
                 item.b_data[kk * item.n + col];
        end
        if (bias_enabled(item.post_op)) begin
          acc += item.bias_data[col];
        end
        if (relu_enabled(item.post_op) && acc < 0) begin
          acc = 0;
        end
        item.expected_c[row * item.n + col] = acc;
      end
    end
  endfunction
endclass

`endif
