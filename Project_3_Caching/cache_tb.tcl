proc AddWaves {} {
	;#Add waves we're interested in to the Wave window
    add wave -position end sim:/cache_tb/clk
    add wave -position end sim:/cache_tb/reset
    
    ;# Cache slave interface (CPU side)
    add wave -position end -radix binary sim:/cache_tb/s_addr
    add wave -position end sim:/cache_tb/s_read
    add wave -position end sim:/cache_tb/s_write
    add wave -position end -radix hex sim:/cache_tb/s_writedata
    add wave -position end -radix hex sim:/cache_tb/s_readdata
    add wave -position end sim:/cache_tb/s_waitrequest
    
    ;# Cache master interface (Memory side)
    add wave -position end -radix unsigned sim:/cache_tb/m_addr
    add wave -position end sim:/cache_tb/m_read
    add wave -position end sim:/cache_tb/m_write
    add wave -position end -radix hex sim:/cache_tb/m_writedata
    add wave -position end -radix hex sim:/cache_tb/m_readdata
    add wave -position end sim:/cache_tb/m_waitrequest
    
    ;# Cache internal state
    add wave -position end sim:/cache_tb/dut/state
    add wave -position end -radix unsigned sim:/cache_tb/dut/cache_address
    add wave -position end -radix hex sim:/cache_tb/dut/read_data_buffer
    add wave -position end -radix hex sim:/cache_tb/dut/write_data_buffer
    add wave -position end -radix unsigned sim:/cache_tb/dut/read_byte_count
    add wave -position end -radix unsigned sim:/cache_tb/dut/write_byte_count
    add wave -position end -radix unsigned sim:/cache_tb/dut/hit_signal
    add wave -position end -radix unsigned sim:/cache_tb/dut/need_write_back_signal

}

vlib work

;# Compile components
vcom memory.vhd
vcom cache.vhd
vcom cache_tb.vhd

;# Start simulation
vsim cache_tb

;# Generate a clock with 1ns period
force -deposit clk 0 0 ns, 1 0.5 ns -repeat 1 ns

;# Add the waves
AddWaves

;# Run for 2000 ns (enough time for multiple cache operations)
run 2000ns
