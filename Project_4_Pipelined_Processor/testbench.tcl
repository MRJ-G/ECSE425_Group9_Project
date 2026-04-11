# ModelSim automation script for testbench.vhd
# Usage examples:
#   vsim -c -do testbench.tcl
#   vsim -do testbench.tcl

# Determine if we are in batch mode. If command is unavailable, assume GUI.
set is_batch 0
if {![catch {set is_batch [batch_mode]}]} {
    # batch_mode command returned successfully.
}

onerror {
    puts "ERROR: testbench.tcl failed."
    if {$is_batch} {
        quit -code 1
    }
}

puts "==> Preparing work library"
if {![file exists work]} {
    vlib work
}
vmap work work

puts "==> Compiling design files"
vcom -2008 pipeline_types.vhd
vcom -2008 alu.vhd
vcom -2008 control.vhd
vcom -2008 imm_gen.vhd
vcom -2008 memory.vhd
vcom -2008 register_file.vhd
vcom -2008 processor.vhd
vcom -2008 testbench.vhd

# Remove stale outputs to avoid confusion.
if {[file exists memory.txt]} {
    file delete -force memory.txt
}
if {[file exists register_file.txt]} {
    file delete -force register_file.txt
}

puts "==> Starting simulation: work.testbench"
vsim -voptargs=+acc work.testbench

# testbench.vhd uses CLK_PERIOD = 1 ns, so 10000 cycles = 10000 ns.
set run_cycles 10000
set run_time_ns $run_cycles

# Optional waves when running in GUI mode; ignored in batch mode.
catch {add wave -position end sim:/testbench/clk}
catch {add wave -position end sim:/testbench/reset}
catch {add wave -position end -radix unsigned sim:/testbench/imem_load_addr}
catch {add wave -position end sim:/testbench/imem_load_en}
catch {add wave -position end -radix binary sim:/testbench/imem_load_data}
catch {add wave -position end -radix unsigned sim:/testbench/dmem_dump_addr}
catch {add wave -position end -radix binary sim:/testbench/dmem_dump_data}

puts "==> Running fixed simulation length: $run_cycles cycles (${run_time_ns} ns)"
run ${run_time_ns} ns

if {![file exists memory.txt]} {
    puts "ERROR: memory.txt was not generated."
    if {$is_batch} {
        quit -code 1
    } else {
        error "memory.txt was not generated"
    }
}
if {![file exists register_file.txt]} {
    puts "ERROR: register_file.txt was not generated."
    if {$is_batch} {
        quit -code 1
    } else {
        error "register_file.txt was not generated"
    }
}

puts "==> PASS: Simulation finished and outputs generated"
puts "    - memory.txt"
puts "    - register_file.txt"

if {$is_batch} {
    quit -code 0
} else {
    puts "INFO: GUI mode detected; simulation kept open."
}
