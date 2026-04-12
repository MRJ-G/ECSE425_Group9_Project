-- Modified from provided memory.vhd
-- Changes: 32-bit wide, no waitrequest, no byteenable, init to zeros
-- ram_size = number of 32-bit words

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY memory IS
    GENERIC(
        ram_size : INTEGER := 8192  -- 8192 words = 32768 bytes
    );
    PORT (
        clock     : IN  STD_LOGIC;
        reset     : IN  STD_LOGIC;
        writedata : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        address   : IN  INTEGER RANGE 0 TO ram_size-1;
        memwrite  : IN  STD_LOGIC;
        readdata  : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- testbench dump port: read 32 consecutive words at once
        dump_base_addr : IN  INTEGER RANGE 0 TO ram_size-1;
        dump_out       : OUT STD_LOGIC_VECTOR(32*32-1 DOWNTO 0)
    );
END memory;

ARCHITECTURE rtl OF memory IS
    TYPE MEM IS ARRAY(ram_size-1 downto 0) OF STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL ram_block : MEM := (others => (others => '0'));
BEGIN
    mem_process: PROCESS (clock)
    BEGIN
        IF (clock'event AND clock = '1') THEN
            IF reset = '1' THEN
                FOR i IN 0 TO ram_size-1 LOOP
                    ram_block(i) <= (others => '0');
                END LOOP;
            ELSIF (memwrite = '1') THEN
                ram_block(address) <= writedata;
            END IF;
        END IF;
    END PROCESS;

    -- Combinatorial read: readdata reflects current address immediately
    readdata <= ram_block(address);

    -- Flatten 32-word dump window for testbench.
    process(ram_block, dump_base_addr)
        variable flat : std_logic_vector(32*32-1 downto 0);
        variable addr_idx : integer;
    begin
        flat := (others => '0');
        for i in 0 to 31 loop
            addr_idx := dump_base_addr + i;
            if addr_idx <= ram_size-1 then
                flat(32*(i+1)-1 downto 32*i) := ram_block(addr_idx);
            end if;
        end loop;
        dump_out <= flat;
    end process;
END rtl;
