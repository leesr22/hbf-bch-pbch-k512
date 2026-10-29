set ddc $::env(STA_DDC)
set outdir $::env(STA_OUTDIR)
set target $::env(STA_LIBRARY)
set period $::env(STA_PERIOD)
file mkdir $outdir
set_app_var target_library [list $target]
set_app_var link_library [concat "*" $target_library]
read_ddc $ddc
set top [current_design]
reset_design
create_clock -name clk -period $period [get_ports clk]
set_clock_uncertainty 0.20 [get_clocks clk]
set_input_delay 0.40 -clock clk \
    [remove_from_collection [all_inputs] [get_ports {clk reset_n}]]
set_output_delay 0.40 -clock clk [all_outputs]
set_false_path -from [get_ports reset_n]
redirect "$outdir/timing_max.rpt" \
    {report_timing -delay_type max -max_paths 20 -nworst 5}
redirect "$outdir/timing_min.rpt" \
    {report_timing -delay_type min -max_paths 20 -nworst 5}
redirect "$outdir/area.rpt" {report_area -physical -hierarchy}
set path [get_timing_paths -delay_type max -max_paths 1]
set slack [get_attribute $path slack]
set sh [open "$outdir/status.txt" w]
if {$slack >= 0.15} {
    puts $sh "result=CONSERVATIVE_PASS"
} elseif {$slack >= 0.0} {
    puts $sh "result=NOMINAL_PASS_MARGIN_FAIL"
} else {
    puts $sh "result=TIMING_FAIL"
}
puts $sh "slack_ns=$slack"
puts $sh "clock_period_ns=$period"
puts $sh "clock_mhz=[expr {1000.0/double($period)}]"
puts $sh "scope=mapped_netlist_operating_point"
close $sh
quit
