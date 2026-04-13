library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity testbench is
end entity testbench;

architecture sim of testbench is
    constant CLK_PERIOD : time := 1 ns; -- 1 GHz
    constant RUN_CYCLES : natural := 10000;  -- assignment requirement: 10 000 cycles

    signal clk : std_logic := '0';
    signal reset : std_logic := '1';

    signal imem_load_addr : integer range 0 to 1023 := 0;
    signal imem_load_data : std_logic_vector(31 downto 0) := (others => '0');
    signal imem_load_en   : std_logic := '0';

    signal dmem_dump_addr : integer range 0 to 8191 := 0;
    signal dmem_dump_data : std_logic_vector(32*32-1 downto 0);

    signal reg_dump : std_logic_vector(32*32-1 downto 0);

    function is_valid_instr(s : string) return boolean is
        variable bit_count : natural := 0;
    begin
        -- Accept both raw 32-bit lines and nibble-mode lines (with spaces/tabs).
        for i in s'range loop
            if (s(i) = '0') or (s(i) = '1') then
                bit_count := bit_count + 1;
            elsif (s(i) = ' ') or (s(i) = character'val(9)) or (s(i) = character'val(13)) then
                null; -- separators are allowed
            else
                return false;
            end if;
        end loop;

        return bit_count = 32;
    end function;

    function bin_string_to_slv32(s : string) return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
        variable j : integer := 31;
    begin
        for i in s'range loop
            if (s(i) = '0') or (s(i) = '1') then
                if s(i) = '1' then
                    v(j) := '1';
                else
                    v(j) := '0';
                end if;
                j := j - 1;
            elsif (s(i) = ' ') or (s(i) = character'val(9)) or (s(i) = character'val(13)) then
                null; -- ignore separators
            end if;
        end loop;
        return v;
    end function;

    function slv_to_bin_string(v : std_logic_vector) return string is
        variable s : string(1 to v'length);
        variable k : integer := 1;
    begin
        for i in v'high downto v'low loop
            case v(i) is
                when '0' => s(k) := '0';
                when '1' => s(k) := '1';
                when others => s(k) := 'X';
            end case;
            k := k + 1;
        end loop;
        return s;
    end function;

    function get_reg_word( -- unflatten 32 registers from reg_dump vector
        regs : std_logic_vector(32*32-1 downto 0);
        idx  : natural
    ) return std_logic_vector is
        variable w : std_logic_vector(31 downto 0);
    begin
        w := regs(32*(idx+1)-1 downto 32*idx);
        return w;
    end function;

    function get_mem_dump_word(
        mem_dump : std_logic_vector(32*32-1 downto 0);
        idx      : natural
    ) return std_logic_vector is
        variable w : std_logic_vector(31 downto 0);
    begin
        w := mem_dump(32*(idx+1)-1 downto 32*idx);
        return w;
    end function;

begin
    uut: entity work.processor
        port map(
            clk            => clk,
            reset          => reset,
            imem_load_addr => imem_load_addr,
            imem_load_data => imem_load_data,
            imem_load_en   => imem_load_en,
            dmem_dump_addr => dmem_dump_addr,
            dmem_dump_data => dmem_dump_data,
            reg_dump       => reg_dump
        );

    clk_process: process
    begin
        while true loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
    end process;

    stim_process: process
        file program_file : text;
        file mem_file : text;
        file reg_file : text;

        variable in_line : line;
        variable out_line : line;
        variable instr_count : integer := 0;
        variable reg_word : std_logic_vector(31 downto 0);
    begin
        wait until rising_edge(clk); -- stabilize signals before starting stimulus
        wait until rising_edge(clk);

        file_open(program_file, "program.txt", read_mode);

        -- load one instruction per cycle into instruction memory using imem_load interface
        while not endfile(program_file) loop
            -- read a line (instruction) from the file into in_line
            readline(program_file, in_line);

            if in_line'length = 0 then
                next;
            end if;

            assert instr_count <= 1023
                report "Program too large: more than 1024 instructions"
                severity failure;

            assert is_valid_instr(in_line.all)
                report "Invalid instruction in program.txt at index " & integer'image(instr_count)
                severity failure;

            imem_load_addr <= instr_count;
            imem_load_data <= bin_string_to_slv32(in_line.all);
            imem_load_en <= '1';
            wait until rising_edge(clk);
            instr_count := instr_count + 1;
        end loop;

        file_close(program_file);

        imem_load_en <= '0';
        imem_load_addr <= 0;
        imem_load_data <= (others => '0');

        wait until rising_edge(clk);
        reset <= '0';

        for i in 1 to RUN_CYCLES loop
            wait until rising_edge(clk);
        end loop;

        -- Dump register file FIRST while reset is still '0'.
        -- register_file has an asynchronous reset: asserting reset before the
        -- dump would immediately clear all registers, giving all-zero output.
        file_open(reg_file, "register_file.txt", write_mode);
        for i in 0 to 31 loop
            reg_word := reg_dump(32*(i+1)-1 downto 32*i);
            write(out_line, slv_to_bin_string(reg_word));
            writeline(reg_file, out_line);
        end loop;
        file_close(reg_file);

        report "Simulation complete - 10000 cycles executed."
            severity note;

        -- Dump data memory.  The dump port (dump_base_addr / dmem_dump_data)
        -- is a combinatorial window into memory; it does not depend on the
        -- processor being in reset.  We do NOT assert reset here because the
        -- memory has a synchronous reset: the first clock edge after reset='1'
        -- would erase all stored data before we finish scanning.
        dmem_dump_addr <= 0;
        wait until rising_edge(clk);

        file_open(mem_file, "memory.txt", write_mode);
        for blk in 0 to 255 loop
            dmem_dump_addr <= blk * 32;
            wait until rising_edge(clk);
            for j in 0 to 31 loop
                write(out_line, slv_to_bin_string(get_mem_dump_word(dmem_dump_data, j)));
                writeline(mem_file, out_line);
            end loop;
        end loop;
        file_close(mem_file);

        report "Simulation complete. Loaded instructions: " & integer'image(instr_count)
            severity note;

        wait;
    end process;

end architecture sim;
