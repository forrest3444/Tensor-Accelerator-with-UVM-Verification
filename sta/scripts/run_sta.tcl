set TOP $::env(TOP)
set CLK_NS $::env(CLK_NS)
set LIB $::env(LIB)
set NETLIST $::env(NETLIST)
set REPORT_DIR $::env(REPORT_DIR)
set SDC $::env(SDC)
set PATH_COUNT $::env(PATH_COUNT)

read_liberty $LIB
read_verilog $NETLIST
link_design $TOP

read_sdc $SDC

set report_prefix "$REPORT_DIR/${TOP}"

check_setup -verbose -unconstrained_endpoints > "${report_prefix}.check_setup.rpt"
report_wns > "${report_prefix}.wns.rpt"
report_tns > "${report_prefix}.tns.rpt"
report_checks -path_delay max -fields {slew cap input nets fanout} -digits 4 -group_count $PATH_COUNT > "${report_prefix}.max.rpt"
report_checks -path_delay min -fields {slew cap input nets fanout} -digits 4 -group_count $PATH_COUNT > "${report_prefix}.min.rpt"
report_checks -unconstrained -fields {slew cap input nets fanout} -digits 4 -group_count $PATH_COUNT > "${report_prefix}.unconstrained.rpt"

puts "STA complete"
puts "  Top:      $TOP"
puts "  Clock ns: $CLK_NS"
puts "  Library:  $LIB"
puts "  Netlist:  $NETLIST"
puts "  SDC:      $SDC"
puts "  Reports:  $REPORT_DIR"
puts "  Paths:    $PATH_COUNT"
