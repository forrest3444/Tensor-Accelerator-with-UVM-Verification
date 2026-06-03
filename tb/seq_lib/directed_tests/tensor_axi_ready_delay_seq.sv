`ifndef TENSOR_ACCEL_AXI_READY_DELAY_SEQ_SV
`define TENSOR_ACCEL_AXI_READY_DELAY_SEQ_SV

class tensor_axi_ready_delay_slave_seq extends svt_axi_slave_memory_sequence;
  `uvm_object_utils(tensor_axi_ready_delay_slave_seq)

  rand int unsigned min_delay;
  rand int unsigned max_delay;
  bit reported_delay_cfg;

  constraint c_delay_range {
    min_delay <= max_delay;
    max_delay <= 8;
  }

  function new(string name = "tensor_axi_ready_delay_slave_seq");
    super.new(name);
    OKAY_wt = 100;
    EXOKAY_wt = 0;
    SLVERR_wt = 0;
    DECERR_wt = 0;
    min_delay = 0;
    max_delay = 8;
    reported_delay_cfg = 1'b0;
  endfunction

  virtual task randomize_slave_xact(`SVT_AXI_SLAVE_TRANSACTION_TYPE slave_xact,
                                    bit is_slv_decerr,
                                    bit enable_perf_mode = 0);
    bit status;

    if (!this.randomize() with {
          min_delay == 0;
          max_delay inside {[2:8]};
        }) begin
      `uvm_fatal(get_type_name(), "Failed to randomize AXI slave delay range")
    end

    if (!reported_delay_cfg) begin
      `uvm_info(get_type_name(),
                $sformatf("Injecting AXI slave ready/valid delays in [%0d:%0d] cycles",
                          min_delay, max_delay),
                UVM_LOW)
      reported_delay_cfg = 1'b1;
    end

    status = slave_xact.randomize() with {
      if (is_slv_decerr) {
        foreach (rresp[index]) rresp[index] == svt_axi_slave_transaction::DECERR;
        bresp == svt_axi_slave_transaction::DECERR;
      } else {
        foreach (rresp[index]) rresp[index] == svt_axi_slave_transaction::OKAY;
        bresp == svt_axi_slave_transaction::OKAY;
      }

      if (enable_perf_mode) {
        addr_ready_delay == 0;
        foreach (wready_delay[idx]) wready_delay[idx] == 0;
        bvalid_delay == 0;
        foreach (rvalid_delay[idx]) rvalid_delay[idx] == 0;
      } else {
        addr_ready_delay inside {[local::min_delay:local::max_delay]};
        if (xact_type == svt_axi_transaction::READ) {
          foreach (rvalid_delay[idx]) {
            rvalid_delay[idx] inside {[local::min_delay:local::max_delay]};
          }
        }
        if (xact_type == svt_axi_transaction::WRITE) {
          foreach (wready_delay[idx]) {
            wready_delay[idx] inside {[local::min_delay:local::max_delay]};
          }
          bvalid_delay inside {[local::min_delay:local::max_delay]};
        }
      }
    };

    if (!status) begin
      `uvm_fatal(get_type_name(), "Randomization of delayed AXI slave response failed")
    end
  endtask
endclass

`endif
