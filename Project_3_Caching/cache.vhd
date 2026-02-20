library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache is
generic(
	ram_size : INTEGER := 32768 -- 15 bits for address
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

-- Cache specifications:
	-- Direct-mapped
	-- 128-bit blocks (4 words per block)
	-- 4096 bits of data storage (32 blocks)
-- Main memory specifications:
	-- has only 2^15 bytes (32768 bytes)
	-- Use the lower 15 bits of the address and ignore the rest

CONSTANT block_size  : INTEGER := 128;		-- 128 bits (16 bytes) per block
CONSTANT num_blocks  : INTEGER := 32;		-- total 32 blocks in cache
-- Address breakdown: 15 bits total = 6 bits tag + 5 bits index + 4 bits offset (last 2 bits ignored for word-aligned)

TYPE CACHE_BLOCK IS RECORD -- declaire a record type to represent one cache block
	data : STD_LOGIC_VECTOR(block_size-1 downto 0);
	valid : STD_LOGIC;
	dirty : STD_LOGIC;
	tag : INTEGER range 0 to 63;
END RECORD;
TYPE CACHE IS ARRAY(num_blocks-1 downto 0) OF CACHE_BLOCK;	-- the entire cache
SIGNAL cache_array: CACHE;

TYPE ADDR IS RECORD -- total 15 bits
	tag : INTEGER range 0 to 63;			-- 6 bits
	index : INTEGER range 0 to 31;			-- 5 bits
	offset : INTEGER range 0 to 3;			-- 2 bits (word offset)
END RECORD;
SIGNAL cache_address: ADDR := (tag => 0, index => 0, offset => 0);

SIGNAL resolved_main_addr: INTEGER := 0;
SIGNAL cache_read_data: STD_LOGIC_VECTOR(31 downto 0) := (OTHERS => '0');
-- buffer for reading data from memory, since we can only read one byte at a time from memory but need to read an entire block (16 bytes)
SIGNAL read_data_buffer: STD_LOGIC_VECTOR(block_size-1 downto 0) := (OTHERS => '0');
SIGNAL read_byte_count: INTEGER range 0 to block_size/8-1 := 0;
SIGNAL write_data_buffer: STD_LOGIC_VECTOR(block_size-1 downto 0) := (OTHERS => '0');
SIGNAL write_byte_count: INTEGER range 0 to block_size/8-1 := 0;

--################# FSM signals #################--
TYPE STATE_TYPE IS (IDLE, TAG, READ_MEM, WRITE_MEM, DONE);
SIGNAL state: STATE_TYPE := IDLE;


--################# helper functions #################--
FUNCTION extract_addr(input: STD_LOGIC_VECTOR(31 downto 0)) RETURN ADDR IS
	VARIABLE effect_add: ADDR;
BEGIN
	effect_add.tag := to_integer(unsigned(input(14 downto 9)));		-- 6 bits for tag
	effect_add.index := to_integer(unsigned(input(8 downto 4)));	-- 5 bits for index
	effect_add.offset := to_integer(unsigned(input(3 downto 2)));	-- 4(-2) bits for offset but ignore last 2 bits since word-aligned
RETURN effect_add;
END FUNCTION;

FUNCTION resolve_main_addr(addr: ADDR) RETURN INTEGER IS
	VARIABLE main_addr: INTEGER;
BEGIN
	-- Calculate byte address: tag * (32 blocks * 16 bytes) + index * 16 bytes + offset * 4 bytes
	main_addr := addr.tag * 512 + addr.index * 16 + addr.offset * 4;
RETURN main_addr;
END FUNCTION;

IMPURE FUNCTION hit(addr: ADDR) RETURN BOOLEAN IS
	VARIABLE hit_result: BOOLEAN := FALSE;
BEGIN
	hit_result := (cache_array(addr.index).valid = '1') AND (cache_array(addr.index).tag = addr.tag);
RETURN hit_result;
END FUNCTION;

IMPURE FUNCTION need_write_back(addr: ADDR) RETURN BOOLEAN IS
	VARIABLE valid: BOOLEAN := (cache_array(addr.index).valid = '1');
	VARIABLE match: BOOLEAN := (cache_array(addr.index).tag = addr.tag);
	VARIABLE dirty: BOOLEAN := (cache_array(addr.index).dirty = '1');
	VARIABLE need: BOOLEAN := FALSE;
BEGIN
	need := valid AND NOT match AND dirty;
RETURN need;
END FUNCTION;

IMPURE FUNCTION read_word(addr: ADDR) RETURN STD_LOGIC_VECTOR IS
	VARIABLE word_out: STD_LOGIC_VECTOR(31 downto 0);
	VARIABLE byte_offset: INTEGER := addr.offset * 4; -- convert word offset to byte offset
BEGIN
	word_out := cache_array(addr.index).data((byte_offset+4)*8-1 downto byte_offset*8);
RETURN word_out;
END FUNCTION;

IMPURE FUNCTION write_word(addr: ADDR; data_in: STD_LOGIC_VECTOR(31 downto 0)) RETURN CACHE_BLOCK IS
	VARIABLE block_write: CACHE_BLOCK;
	VARIABLE byte_offset: INTEGER := addr.offset * 4; -- convert word offset to byte offset
BEGIN
	block_write := cache_array(addr.index);
	block_write.data((byte_offset+4)*8-1 downto byte_offset*8) := data_in;
	block_write.valid := '1';
	block_write.dirty := '1';
	block_write.tag := addr.tag;
RETURN block_write;
END FUNCTION;

IMPURE FUNCTION evict_block_addr(addr: ADDR) RETURN INTEGER IS
	VARIABLE block_evict: CACHE_BLOCK;
	VARIABLE wb_main_addr: INTEGER;
BEGIN
	block_evict := cache_array(addr.index);
	-- Calculate byte address of the block to evict
	wb_main_addr := block_evict.tag * 512 + addr.index * 16;
RETURN wb_main_addr;
END FUNCTION;

begin

-- make circuits here

	state_update: PROCESS (clock)
		VARIABLE temp_block : CACHE_BLOCK;
	BEGIN
		IF reset = '1' THEN
			cache_address <= (tag => 0, index => 0, offset => 0);
			read_data_buffer <= (OTHERS => '0');
			read_byte_count <= 0;
			write_data_buffer <= (OTHERS => '0');
			write_byte_count <= 0;
			state <= IDLE;
		ELSIF rising_edge(clock) THEN
			CASE state IS
				WHEN IDLE =>
					IF s_read = '1' OR s_write = '1' THEN
						cache_address <= extract_addr(s_addr);
						state <= TAG;
					ELSIF s_read = '0' AND s_write = '0' THEN
						state <= IDLE;
					END IF;
				WHEN TAG =>
					IF hit(cache_address) THEN
						IF s_read = '1' THEN
							cache_read_data <= read_word(cache_address);
						ELSIF s_write = '1' THEN
							cache_array(cache_address.index) <= write_word(cache_address, s_writedata);
						END IF;
						state <= DONE;
					ELSE -- miss
						IF need_write_back(cache_address) THEN
							resolved_main_addr <= evict_block_addr(cache_address);
							write_data_buffer <= cache_array(cache_address.index).data;
							write_byte_count <= 0;
							state <= WRITE_MEM;
						ELSE
							resolved_main_addr <= resolve_main_addr(cache_address);
							read_data_buffer <= (OTHERS => '0');
							read_byte_count <= 0;
							state <= READ_MEM;
						END IF;
					END IF;
				WHEN WRITE_MEM =>
					IF	m_waitrequest = '1' THEN
						-- current write-one-byte-to-memory transaction has not been completed
						state <= WRITE_MEM;
					ELSIF m_waitrequest = '0' AND write_byte_count < block_size/8-1 THEN
						m_addr <= resolved_main_addr + write_byte_count;
						m_writedata <= write_data_buffer((write_byte_count+1)*8-1 downto write_byte_count*8);
						write_byte_count <= write_byte_count + 1;
						state <= WRITE_MEM;
					ELSIF m_waitrequest = '0' AND write_byte_count = block_size/8-1 THEN
						resolved_main_addr <= resolve_main_addr(cache_address);
						read_data_buffer <= (OTHERS => '0');
						read_byte_count <= 0;
						state <= READ_MEM;
					END IF;
				WHEN READ_MEM =>
					IF m_waitrequest = '1' THEN
						-- current read-one-byte-from-memory transaction has not been completed
						state <= READ_MEM;
					ELSIF m_waitrequest = '0' AND read_byte_count < block_size/8-1 THEN
						read_data_buffer((read_byte_count+1)*8-1 downto read_byte_count*8) <= m_readdata;
						m_addr <= resolved_main_addr + read_byte_count + 1;
						read_byte_count <= read_byte_count + 1;
						state <= READ_MEM;
					ELSIF m_waitrequest = '0' AND read_byte_count = block_size/8-1 THEN
						read_data_buffer((read_byte_count+1)*8-1 downto read_byte_count*8) <= m_readdata;
						-- Update cache block with new data using temp_block
						temp_block.data := read_data_buffer;
						temp_block.valid := '1';
						temp_block.dirty := '0';
						temp_block.tag := cache_address.tag;
						cache_array(cache_address.index) <= temp_block;
						state <= DONE;
					END IF;
				WHEN DONE =>
					cache_address <= (tag => 0, index => 0, offset => 0);
					read_data_buffer <= (OTHERS => '0');
					read_byte_count <= 0;
					write_data_buffer <= (OTHERS => '0');
					write_byte_count <= 0;
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
			WHEN TAG =>
				s_waitrequest <= '1';
				m_read <= '0';
				m_write <= '0';
			WHEN WRITE_MEM =>
				s_waitrequest <= '1';
				m_read <= '0';
				m_write <= '1';
			WHEN READ_MEM =>
				s_waitrequest <= '1';
				m_read <= '1';
				m_write <= '0';
			WHEN DONE =>
				s_waitrequest <= '0';
				m_read <= '0';
				m_write <= '0';
			WHEN OTHERS =>
				s_waitrequest <= '1';
				m_read <= '0';
				m_write <= '0';
		END CASE;
	END PROCESS;

	s_readdata <= cache_read_data;



end arch;