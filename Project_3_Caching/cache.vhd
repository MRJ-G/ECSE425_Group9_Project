library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache is
generic(
	ram_size : INTEGER := 32768;
);
port(
	clock : in std_logic;
	reset : in std_logic;
	
	-- Avalon interface --
	s_addr : in std_logic_vector (31 downto 0);
	s_read : in std_logic;
	s_readdata : out std_logic_vector (31 downto 0);
	s_write : in std_logic;
	s_writedata : in std_logic_vector (31 downto 0);
	s_waitrequest : out std_logic; 
    
	m_addr : out integer range 0 to ram_size-1;
	m_read : out std_logic;
	m_readdata : in std_logic_vector (7 downto 0);
	m_write : out std_logic;
	m_writedata : out std_logic_vector (7 downto 0);
	m_waitrequest : in std_logic
);
end cache;

architecture arch of cache is

-- declare signals here

component memory
PORT (
		clock: IN STD_LOGIC;
		writedata: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		address: IN INTEGER RANGE 0 TO ram_size-1;
		memwrite: IN STD_LOGIC;
		memread: IN STD_LOGIC;
		readdata: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
		waitrequest: OUT STD_LOGIC
	);
	TYPE MEM IS ARRAY(cache_size-1 downto 0) OF STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL cache_block: MEM;
	TYPE FLAG IS ARRAY(cache_size-1 downto 0) OF STD_LOGIC := '0';					-- I want to initialize them to 0
	SIGNAL cache_dirty_bit : FLAG;
	TYPE FLAG IS ARRAY(cache_size-1 downto 0) OF STD_LOGIC := '0';					-- I want to initialize them to 0
	SIGNAL cache_valid_bit : FLAG;
	TYPE TAG IS ARRAY(cache_size-1 downto 0) OF STD_LOGIC_VECTOR(10 DOWNTO 0); -- total 2048 tag combinations
	SIGNAL	cache_tags : TAG;
	
SIGNAL read_address_reg: INTEGER RANGE 0 to ram_size-1;
SIGNAL write_waitreq_reg: STD_LOGIC := '1';
SIGNAL read_waitreq_reg: STD_LOGIC := '1';
	
SIGNAL cache_size : INTEGER := 512			-- 4096 bits per block
SIGNAL block_size : INTEGER := 16			-- 128 bits per block

begin

-- make circuits here

	mem_process: PROCESS (clock)
	BEGIN

		--This is the actual synthesizable SRAM block
		-- Need to check if a cache hit first.
		IF (clock'event AND clock = '1') THEN
			IF (memwrite = '1') THEN
				ram_block(address) <= writedata;
			END IF;
		read_address_reg <= address;
		END IF;
	END PROCESS;
	readdata <= ram_block(read_address_reg);




end arch;