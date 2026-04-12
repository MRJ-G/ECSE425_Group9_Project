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

proc safe_delete_output {path} {
    if {![file exists $path]} {
        return
    }

    # Try to ensure the file is writable before deleting.
    catch {file attributes $path -permissions u+w}

    if {[catch {file delete -force $path} err]} {
        puts "WARNING: Could not delete $path ($err)."
        puts "         The simulation will continue and may overwrite this file."
    }
}

puts "==> Preparing work library"
# Always delete and recreate to guarantee a clean compile

vdel -lib work -all
vlib work
vmap work work

puts "==> Compiling design files"
vcom -2008 pipeline_types.vhd
vcom -2008 alu.vhd
vcom -2008 control.vhd
vcom -2008 imm_gen.vhd
vcom -2008 memory.vhd
vcom -2008 register_file.vhd
vcom -2008 hazard_detection.vhd
vcom -2008 processor.vhd
vcom -2008 testbench.vhd

# The VHDL testbench reads program.txt from the simulation working directory.
# Keep that file in sync with the currently selected sample program so the
# processor is not accidentally driven by a stale image from a previous run.
set script_dir [file dirname [file normalize [info script]]]
set program_source [file join $script_dir no_hazard_examples hazard_simple.txt]
set program_target [file join $script_dir program.txt]
file copy -force $program_source $program_target
puts "==> Program image: $program_source -> $program_target"

# Force the simulator working directory to the project directory so the VHDL
# file_open("program.txt") call resolves to the expected file.
cd $script_dir

# Remove stale outputs to avoid confusion.
safe_delete_output memory.txt
safe_delete_output register_file.txt

puts "==> Starting simulation: work.testbench"
vsim -voptargs=+acc work.testbench

# testbench.vhd uses CLK_PERIOD = 1 ns.
# Need enough cycles for: program load + RUN_CYCLES (2500) + memory dump blocks (256) + register dump.
# Keep a safe margin for longer programs.
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

# Branch debug waves (decode -> execute -> redirect).
catch {add wave -position end -radix hex sim:/testbench/uut/pc}
catch {add wave -position end -radix hex sim:/testbench/uut/pc_next}
catch {add wave -position end sim:/testbench/uut/branch_taken}
catch {add wave -position end -radix hex sim:/testbench/uut/br_target}
catch {add wave -position end sim:/testbench/uut/br_cond}

catch {add wave -position end -radix hex sim:/testbench/uut/if_id}
catch {add wave -position end -radix hex sim:/testbench/uut/id_ex}
catch {add wave -position end -radix hex sim:/testbench/uut/ex_mem}

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

