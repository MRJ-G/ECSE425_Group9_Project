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
        writedata : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
        address   : IN  INTEGER RANGE 0 TO ram_size-1;
        memwrite  : IN  STD_LOGIC;
        memread   : IN  STD_LOGIC;
        readdata  : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END memory;

ARCHITECTURE rtl OF memory IS
    TYPE MEM IS ARRAY(ram_size-1 downto 0) OF STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL ram_block : MEM := (others => (others => '0'));
    SIGNAL read_address_reg : INTEGER RANGE 0 TO ram_size-1;
BEGIN
    mem_process: PROCESS (clock)
    BEGIN
        IF (clock'event AND clock = '1') THEN
            IF (memwrite = '1') THEN
                ram_block(address) <= writedata;
            END IF;
            read_address_reg <= address;
        END IF;
    END PROCESS;

    readdata <= ram_block(read_address_reg);
END rtl;
