library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity testbench is
end entity testbench;

architecture sim of testbench is
    constant CLK_PERIOD : time := 1 ns;
    constant RUN_CYCLES : natural := 200;

    signal clk : std_logic := '0';
    signal reset : std_logic := '1';

    signal imem_load_addr : integer range 0 to 1023 := 0;
    signal imem_load_data : std_logic_vector(31 downto 0) := (others => '0');
    signal imem_load_en   : std_logic := '0';

    signal dmem_dump_addr : integer range 0 to 8191 := 0;
    signal dmem_dump_data : std_logic_vector(32*32-1 downto 0);
    signal reg_dump       : std_logic_vector(32*32-1 downto 0);

    function is_valid_instr(s : string) return boolean is
        variable bit_count : natural := 0;
    begin
        for i in s'range loop
            if (s(i) = '0') or (s(i) = '1') then
                bit_count := bit_count + 1;
            elsif (s(i) = ' ') or (s(i) = character'val(9)) or
                  (s(i) = character'val(13)) then
                null;
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
                if s(i) = '1' then v(j) := '1'; else v(j) := '0'; end if;
                j := j - 1;
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
                when '0'    => s(k) := '0';
                when '1'    => s(k) := '1';
                when others => s(k) := 'X';
            end case;
            k := k + 1;
        end loop;
        return s;
    end function;

    function get_reg_word(
        regs : std_logic_vector(32*32-1 downto 0);
        idx  : natural
    ) return std_logic_vector is
    begin
        return regs(32*(idx+1)-1 downto 32*idx);
    end function;

    function get_mem_dump_word(
        mem_dump : std_logic_vector(32*32-1 downto 0);
        idx      : natural
    ) return std_logic_vector is
    begin
        return mem_dump(32*(idx+1)-1 downto 32*idx);
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
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
    end process;

    stim_process: process
        file prog_file : text;
        file mem_file  : text;
        file reg_file  : text;

        variable ln          : line;
        variable out_ln      : line;
        variable instr_count : integer := 0;
        variable reg_word    : std_logic_vector(31 downto 0);
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- ==============================================================
        -- TEST 1: hazard_simple
        --   x1=5  x2=8  x3=12  x4=17  x5=18   mem all zero
        -- ==============================================================
        report "Test 1 started: hazard_simple" severity note;
        instr_count := 0;
        file_open(prog_file, "hazard_simple.txt", read_mode);
        while not endfile(prog_file) loop
            readline(prog_file, ln);
            if ln'length = 0 then next; end if;
            assert is_valid_instr(ln.all)
                report "hazard_simple: invalid instruction at index " &
                       integer'image(instr_count) severity failure;
            imem_load_addr <= instr_count;
            imem_load_data <= bin_string_to_slv32(ln.all);
            imem_load_en   <= '1';
            wait until rising_edge(clk);
            instr_count := instr_count + 1;
        end loop;
        file_close(prog_file);
        imem_load_en <= '0'; imem_load_addr <= 0; imem_load_data <= (others => '0');
        wait until rising_edge(clk);
        reset <= '0';
        for i in 1 to RUN_CYCLES loop wait until rising_edge(clk); end loop;
        dmem_dump_addr <= 0;
        wait until rising_edge(clk);

        assert get_reg_word(reg_dump,  0) = std_logic_vector(to_unsigned( 0, 32))
            report "hazard_simple: expected x0=0" severity error;
        assert get_reg_word(reg_dump,  1) = std_logic_vector(to_unsigned( 5, 32))
            report "hazard_simple: expected x1=5" severity error;
        assert get_reg_word(reg_dump,  2) = std_logic_vector(to_unsigned( 8, 32))
            report "hazard_simple: expected x2=8 (x1+3)" severity error;
        assert get_reg_word(reg_dump,  3) = std_logic_vector(to_unsigned(12, 32))
            report "hazard_simple: expected x3=12 (x2+4)" severity error;
        assert get_reg_word(reg_dump,  4) = std_logic_vector(to_unsigned(17, 32))
            report "hazard_simple: expected x4=17 (x3+x1)" severity error;
        assert get_reg_word(reg_dump,  5) = std_logic_vector(to_unsigned(18, 32))
            report "hazard_simple: expected x5=18 (x4+1)" severity error;
        for i in 6 to 31 loop
            assert get_reg_word(reg_dump, i) = std_logic_vector(to_unsigned(0, 32))
                report "hazard_simple: expected x" & integer'image(i) & "=0" severity error;
        end loop;
        assert get_mem_dump_word(dmem_dump_data, 0) = std_logic_vector(to_unsigned(0, 32))
            report "hazard_simple: expected memory[0]=0" severity error;

        report "Assertions done for: hazard_simple" severity note;
        reset <= '1';
        wait until rising_edge(clk); wait until rising_edge(clk);

        -- ==============================================================
        -- TEST 2: branch_no_hazard
        --   x1=3  x2=3  x5=0 (beq taken, skip addi x5)  x6=42
        --   mem all zero
        -- ==============================================================
        report "Test 2 started: branch_no_hazard" severity note;
        instr_count := 0;
        file_open(prog_file, "branch_no_hazard.txt", read_mode);
        while not endfile(prog_file) loop
            readline(prog_file, ln);
            if ln'length = 0 then next; end if;
            assert is_valid_instr(ln.all)
                report "branch_no_hazard: invalid instruction at index " &
                       integer'image(instr_count) severity failure;
            imem_load_addr <= instr_count;
            imem_load_data <= bin_string_to_slv32(ln.all);
            imem_load_en   <= '1';
            wait until rising_edge(clk);
            instr_count := instr_count + 1;
        end loop;
        file_close(prog_file);
        imem_load_en <= '0'; imem_load_addr <= 0; imem_load_data <= (others => '0');
        wait until rising_edge(clk);
        reset <= '0';
        for i in 1 to RUN_CYCLES loop wait until rising_edge(clk); end loop;
        dmem_dump_addr <= 0;
        wait until rising_edge(clk);

        assert get_reg_word(reg_dump,  0) = std_logic_vector(to_unsigned( 0, 32))
            report "branch_no_hazard: expected x0=0" severity error;
        assert get_reg_word(reg_dump,  1) = std_logic_vector(to_unsigned( 3, 32))
            report "branch_no_hazard: expected x1=3" severity error;
        assert get_reg_word(reg_dump,  2) = std_logic_vector(to_unsigned( 3, 32))
            report "branch_no_hazard: expected x2=3" severity error;
        assert get_reg_word(reg_dump,  5) = std_logic_vector(to_unsigned( 0, 32))
            report "branch_no_hazard: expected x5=0 (instruction after beq should be skipped)"
            severity error;
        assert get_reg_word(reg_dump,  6) = std_logic_vector(to_unsigned(42, 32))
            report "branch_no_hazard: expected x6=42 at branch target" severity error;
        for i in 3 to 4 loop
            assert get_reg_word(reg_dump, i) = std_logic_vector(to_unsigned(0, 32))
                report "branch_no_hazard: expected x" & integer'image(i) & "=0" severity error;
        end loop;
        for i in 7 to 31 loop
            assert get_reg_word(reg_dump, i) = std_logic_vector(to_unsigned(0, 32))
                report "branch_no_hazard: expected x" & integer'image(i) & "=0" severity error;
        end loop;
        assert get_mem_dump_word(dmem_dump_data, 0) = std_logic_vector(to_unsigned(0, 32))
            report "branch_no_hazard: expected memory[0]=0" severity error;

        report "Assertions done for: branch_no_hazard" severity note;
        reset <= '1';
        wait until rising_edge(clk); wait until rising_edge(clk);

        -- ==============================================================
        -- TEST 3: mul_no_hazard
        --   x1=6  x2=7  x3=42 (6*7)  x4=43 (x3+1)   mem all zero
        -- ==============================================================
        report "Test 3 started: mul_no_hazard" severity note;
        instr_count := 0;
        file_open(prog_file, "mul_no_hazard.txt", read_mode);
        while not endfile(prog_file) loop
            readline(prog_file, ln);
            if ln'length = 0 then next; end if;
            assert is_valid_instr(ln.all)
                report "mul_no_hazard: invalid instruction at index " &
                       integer'image(instr_count) severity failure;
            imem_load_addr <= instr_count;
            imem_load_data <= bin_string_to_slv32(ln.all);
            imem_load_en   <= '1';
            wait until rising_edge(clk);
            instr_count := instr_count + 1;
        end loop;
        file_close(prog_file);
        imem_load_en <= '0'; imem_load_addr <= 0; imem_load_data <= (others => '0');
        wait until rising_edge(clk);
        reset <= '0';
        for i in 1 to RUN_CYCLES loop wait until rising_edge(clk); end loop;
        dmem_dump_addr <= 0;
        wait until rising_edge(clk);

        assert get_reg_word(reg_dump,  0) = std_logic_vector(to_unsigned( 0, 32))
            report "mul_no_hazard: expected x0=0" severity error;
        assert get_reg_word(reg_dump,  1) = std_logic_vector(to_unsigned( 6, 32))
            report "mul_no_hazard: expected x1=6" severity error;
        assert get_reg_word(reg_dump,  2) = std_logic_vector(to_unsigned( 7, 32))
            report "mul_no_hazard: expected x2=7" severity error;
        assert get_reg_word(reg_dump,  3) = std_logic_vector(to_unsigned(42, 32))
            report "mul_no_hazard: expected x3=42 (6*7)" severity error;
        assert get_reg_word(reg_dump,  4) = std_logic_vector(to_unsigned(43, 32))
            report "mul_no_hazard: expected x4=43 (x3+1)" severity error;
        for i in 5 to 31 loop
            assert get_reg_word(reg_dump, i) = std_logic_vector(to_unsigned(0, 32))
                report "mul_no_hazard: expected x" & integer'image(i) & "=0" severity error;
        end loop;
        assert get_mem_dump_word(dmem_dump_data, 0) = std_logic_vector(to_unsigned(0, 32))
            report "mul_no_hazard: expected memory[0]=0" severity error;

        report "Assertions done for: mul_no_hazard" severity note;
        reset <= '1';
        wait until rising_edge(clk); wait until rising_edge(clk);

        -- ==============================================================
        -- TEST 4: arith_mem_no_hazard
        --   x1=5  x2=7  x3=12 (x1+x2)  x4=12 (lw from mem[0])
        --   sw x3,0(x0) -> memory[0]=12
        -- ==============================================================
        report "Test 4 started: arith_mem_no_hazard" severity note;
        instr_count := 0;
        file_open(prog_file, "arith_mem_no_hazard.txt", read_mode);
        while not endfile(prog_file) loop
            readline(prog_file, ln);
            if ln'length = 0 then next; end if;
            assert is_valid_instr(ln.all)
                report "arith_mem_no_hazard: invalid instruction at index " &
                       integer'image(instr_count) severity failure;
            imem_load_addr <= instr_count;
            imem_load_data <= bin_string_to_slv32(ln.all);
            imem_load_en   <= '1';
            wait until rising_edge(clk);
            instr_count := instr_count + 1;
        end loop;
        file_close(prog_file);
        imem_load_en <= '0'; imem_load_addr <= 0; imem_load_data <= (others => '0');
        wait until rising_edge(clk);
        reset <= '0';
        for i in 1 to RUN_CYCLES loop wait until rising_edge(clk); end loop;
        dmem_dump_addr <= 0;
        wait until rising_edge(clk);

        assert get_reg_word(reg_dump,  0) = std_logic_vector(to_unsigned( 0, 32))
            report "arith_mem_no_hazard: expected x0=0" severity error;
        assert get_reg_word(reg_dump,  1) = std_logic_vector(to_unsigned( 5, 32))
            report "arith_mem_no_hazard: expected x1=5" severity error;
        assert get_reg_word(reg_dump,  2) = std_logic_vector(to_unsigned( 7, 32))
            report "arith_mem_no_hazard: expected x2=7" severity error;
        assert get_reg_word(reg_dump,  3) = std_logic_vector(to_unsigned(12, 32))
            report "arith_mem_no_hazard: expected x3=12 (x1+x2)" severity error;
        assert get_reg_word(reg_dump,  4) = std_logic_vector(to_unsigned(12, 32))
            report "arith_mem_no_hazard: expected x4=12 (loaded from mem[0])" severity error;
        for i in 5 to 31 loop
            assert get_reg_word(reg_dump, i) = std_logic_vector(to_unsigned(0, 32))
                report "arith_mem_no_hazard: expected x" & integer'image(i) & "=0" severity error;
        end loop;
        assert get_mem_dump_word(dmem_dump_data, 0) = std_logic_vector(to_unsigned(12, 32))
            report "arith_mem_no_hazard: expected memory[0]=12 (stored by sw)" severity error;
        assert get_mem_dump_word(dmem_dump_data, 1) = std_logic_vector(to_unsigned( 0, 32))
            report "arith_mem_no_hazard: expected memory[1]=0" severity error;

        report "Assertions done for: arith_mem_no_hazard" severity note;
        reset <= '1';
        wait until rising_edge(clk); wait until rising_edge(clk);

        -- ==============================================================
        -- Dump final architectural state (reflects arith_mem_no_hazard)
        -- ==============================================================
        file_open(mem_file, "memory.txt", write_mode);
        for blk in 0 to 255 loop
            dmem_dump_addr <= blk * 32;
            wait until rising_edge(clk);
            for j in 0 to 31 loop
                write(out_ln, slv_to_bin_string(get_mem_dump_word(dmem_dump_data, j)));
                writeline(mem_file, out_ln);
            end loop;
        end loop;
        file_close(mem_file);

        file_open(reg_file, "register_file.txt", write_mode);
        for i in 0 to 31 loop
            reg_word := reg_dump(32*(i+1)-1 downto 32*i);
            write(out_ln, slv_to_bin_string(reg_word));
            writeline(reg_file, out_ln);
        end loop;
        file_close(reg_file);

        report "All 4 tests complete." severity note;
        wait;
    end process;

end architecture sim;
