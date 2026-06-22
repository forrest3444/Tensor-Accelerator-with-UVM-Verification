`ifndef TENSOR_PERF_MONITOR_SV
`define TENSOR_PERF_MONITOR_SV

class tensor_perf_monitor extends uvm_component;
  `uvm_component_utils(tensor_perf_monitor)

  function new(string name = "tensor_perf_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

`endif
