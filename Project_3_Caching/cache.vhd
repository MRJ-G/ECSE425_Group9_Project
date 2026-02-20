library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache is
generic(
	ram_size : INTEGER := 32768; -- 15 bits for address
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

COMPONENT memory IS
	GENERIC(
		ram_size : INTEGER := 32768;
		mem_delay : time := 10 ns;
		clock_period : time := 1 ns
	);
	PORT (
		clock: IN STD_LOGIC;
		writedata: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		address: IN INTEGER RANGE 0 TO ram_size-1;
		memwrite: IN STD_LOGIC;
		memread: IN STD_LOGIC;
		readdata: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
		waitrequest: OUT STD_LOGIC
	);
END memory;

-- Cache specifications:
	-- Direct-mapped
	-- 128-bit blocks (4 words per block)
	-- 4096 bits of data storage (32 blocks)
-- Main memory specifications:
	-- has only 2^15 bytes (32768 bytes)
	-- Use the lower 15 bits of the address and ignore the rest

CONSTANT block_size  : INTEGER := 128;		-- 128 bits (16 bytes) per block
CONSTANT num_blocks  : INTEGER := 32;		-- total 32 blocks in cache
CONSTANT flag_bits   : INTEGER := 2;		-- 1 valid bit and 1 dirty bit per block
CONSTANT tag_bits 	 : INTEGER := 6;		-- 15-5(index)-4(offset)
CONSTANT index_bits  : INTEGER := 5;		-- 2^5 = 32 blocks (direct-mapped)
CONSTANT offset_bits : INTEGER := 4;		-- but ignore last 2 bits since word-addressable

TYPE CACHE_BLOCK IS RECORD -- declaire a record type to represent one cache block
	data : STD_LOGIC_VECTOR(block_size-1 downto 0);
	valid : STD_LOGIC;
	dirty : STD_LOGIC;
	tag : STD_LOGIC_VECTOR(tag_bits-1 downto 0);
END RECORD;
TYPE CACHE IS ARRAY(num_blocks-1 downto 0) OF CACHE_BLOCK;	-- the entire cache
SIGNAL cache_array: CACHE;

TYPE ADDR IS RECORD -- total 15 bits
	tag : STD_LOGIC_VECTOR(tag_bits-1 downto 0);
	index : STD_LOGIC_VECTOR(index_bits-1 downto 0);
	offset : STD_LOGIC_VECTOR(offset_bits-1 downto 0);
END RECORD;
SIGNAL cache_address: ADDR;

SIGNAL mem_waitreq_reg: STD_LOGIC := '1';

--################# FSM signals #################--
TYPE STATE_TYPE IS (IDLE, TAG, READ_MEM, WRITE_MEM, DONE);
SIGNAL state: STATE_TYPE := IDLE;

-- buffer for reading data from memory, since we can only read one byte at a time from memory but need to read an entire block (16 bytes)
VARIABLE read_data_buffer: STD_LOGIC_VECTOR(31 downto 0) := (OTHERS => '0');
VARIABLE read_byte_count: INTEGER range 0 to block_size/8-1 := 0;
VARIABLE write_data_buffer: STD_LOGIC_VECTOR(31 downto 0) := (OTHERS => '0');
VARIABLE write_byte_count: INTEGER range 0 to block_size/8-1 := 0;

--################# helper functions #################--
FUNCTION extract_addr(input: STD_LOGIC_VECTOR(31 downto 0)) RETURN ADDR IS
	VARIABLE effect_add: ADDR;
BEGIN
	effect_add.tag := input(14 downto 9);	-- upper 6 bits for tag
	effect_add.index := input(8 downto 4);	-- next 5 bits for index
	effect_add.offset := input(3 downto 2);	-- ignore last 2 bits, since address is always word-aligned
RETURN effect_add;
END FUNCTION;

FUNCTION resolve_main_addr(addr: ADDR) RETURN INTEGER IS
	VARIABLE main_addr: INTEGER;
BEGIN
	main_addr := to_integer(unsigned(addr.tag)) * 32 * 16 + to_integer(unsigned(addr.index)) * 16 + to_integer(unsigned(addr.offset));
RETURN main_addr;
END FUNCTION;

FUNCTION hit(addr: ADDR) RETURN BOOLEAN IS
	VARIABLE index: INTEGER := to_integer(unsigned(addr.index));
	VARIABLE hit: BOOLEAN := FALSE;
BEGIN
	hit := (cache_array(index).valid = '1') AND (cache_array(index).tag = addr.tag);
RETURN hit;
END FUNCTION;

FUNCTION need_write_back(addr: ADDR) RETURN BOOLEAN IS
	VARIABLE index: INTEGER := to_integer(unsigned(addr.index));
	VARIABLE valid: BOOLEAN := (cache_array(index).valid = '1');
	VARIABLE match: BOOLEAN := (cache_array(index).tag = addr.tag);
	VARIABLE dirty: BOOLEAN := (cache_array(index).dirty = '1');
	VARIABLE need: BOOLEAN := FALSE;
BEGIN
	need := valid AND NOT match AND dirty;
RETURN need;
END FUNCTION;

FUNCTION read_word(addr: ADDR; offset: STD_LOGIC_VECTOR(offset_bits-1 downto 0)) RETURN STD_LOGIC_VECTOR(31 downto 0) IS
	VARIABLE word_out: STD_LOGIC_VECTOR(31 downto 0);
	VARIABLE word_index: INTEGER := to_integer(unsigned(offset));
BEGIN
	word_out := cache_array(to_integer(unsigned(addr.index))).data((word_index+1)*32-1 downto word_index*32);
RETURN word_out;
END FUNCTION;

FUNCTION write_word(addr: ADDR; offset: STD_LOGIC_VECTOR(offset_bits-1 downto 0); data_in: STD_LOGIC_VECTOR(31 downto 0)) RETURN CACHE_BLOCK IS
	VARIABLE block_write: CACHE_BLOCK;
	VARIABLE word_index: INTEGER := to_integer(unsigned(offset));
BEGIN
	block_write := cache_array(to_integer(unsigned(addr.index)));
	block_write.data((word_index+1)*32-1 downto word_index*32) := data_in;
	block_write.valid := '1';
	block_write.dirty := '1';
	block_write.tag := addr.tag;
RETURN block_write;
END FUNCTION;

begin

-- make circuits here

	state_update: PROCESS (clock)
	BEGIN
		IF reset = '1' THEN
			state <= IDLE;
		ELSIF rising_edge(clock) THEN
			CASE state IS
				WHEN IDLE =>
					IF s_read = '1' OR s_write = '1' THEN
						state <= TAG;
					END IF;
				WHEN TAG =>
					IF hit(cache_address) THEN
						state <= DONE;
					ELSE -- miss
						IF need_write_back(cache_address) THEN
							state <= WRITE_MEM;
						ELSE
							state <= READ_MEM;
						END IF;
					END IF;
				WHEN WRITE_MEM =>
					IF m_waitrequest = '1' THEN
						state <= WRITE_MEM;
					ELSE
						state <= READ_MEM;
					END IF;
				WHEN READ_MEM =>
					IF m_waitrequest = '1' THEN
						state <= READ_MEM;
					ELSE
						state <= DONE;
					END IF;
				WHEN DONE =>
					state <= IDLE;
				WHEN OTHERS =>
					state <= IDLE;
			END CASE;
		END IF;
	END PROCESS;

	output_logic: PROCESS (state)
	BEGIN
		CASE state IS
			WHEN IDLE =>
				s_waitrequest <= '1';
				m_read <= '0';
				m_write <= '0';
			-- TODO: complete update logic for TAG, WRITE_MEM, READ_MEM, and DONE states
			WHEN TAG =>
				s_waitrequest <= '1';
				m_read <= '0';
				m_write <= '0';
				IF hit(cache_address) THEN
					IF s_read = '1' THEN
						s_readdata <= read_word(cache_address, cache_address.offset);
					ELSIF s_write = '1' THEN
					cache_address <= extract_addr(s_addr);
					END IF;
				END IF;
		END CASE;
	END PROCESS;




end arch;