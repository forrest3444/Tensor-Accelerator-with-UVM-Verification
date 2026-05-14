`ifndef TENSOR_ACCEL_SCOREBOARD_SV
`define TENSOR_ACCEL_SCOREBOARD_SV

class tensor_accel_scoreboard extends tensor_accel_subscriber;
  `uvm_component_utils(tensor_accel_scoreboard)

  int unsigned compare_count;
  int unsigned mismatch_count;

  function new(string name = "tensor_accel_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void write(tensor_accel_matrix_item t);
    if (t.expected_c.size() != t.actual_c.size()) begin
      `uvm_error("SCB_SIZE", $sformatf("expected size %0d actual size %0d",
                 t.expected_c.size(), t.actual_c.size()))
      mismatch_count++;
      if (cfg != null) begin
        cfg.add_scb_check_error();
      end
      return;
    end

    foreach (t.expected_c[idx]) begin
      compare_count++;
      if (cfg != null) begin
        cfg.add_scb_check_count();
      end
      if (t.expected_c[idx] !== t.actual_c[idx]) begin
        mismatch_count++;
        if (cfg != null) begin
          cfg.add_scb_check_error();
        end
        `uvm_error("SCB_MISMATCH",
                   $sformatf("C[%0d] expected=%0d actual=%0d",
                             idx, t.expected_c[idx], t.actual_c[idx]))
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB_REPORT",
              $sformatf("compare_count=%0d mismatch_count=%0d",
                        compare_count, mismatch_count),
              UVM_LOW)
  endfunction
endclass

`endif
