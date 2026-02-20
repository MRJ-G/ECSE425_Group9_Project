library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache_tb is
end cache_tb;

architecture behavior of cache_tb is

-- Helper function to convert std_logic_vector to hex string
function to_hex_string(slv: std_logic_vector) return string is
    variable hexlen : integer := (slv'length + 3) / 4;
    variable result : string(1 to hexlen);
    variable nibble : std_logic_vector(3 downto 0);
    variable idx : integer := 0;
begin
    for i in 0 to hexlen-1 loop
        idx := slv'high - i*4;
        if idx - 3 < slv'low then
            -- Last nibble might be partial
            nibble := (others => '0');
            nibble(idx - slv'low downto 0) := slv(idx downto slv'low);
        else
            nibble := slv(idx downto idx-3);
        end if;
        
        case nibble is
            when "0000" => result(i+1) := '0';
            when "0001" => result(i+1) := '1';
            when "0010" => result(i+1) := '2';
            when "0011" => result(i+1) := '3';
            when "0100" => result(i+1) := '4';
            when "0101" => result(i+1) := '5';
            when "0110" => result(i+1) := '6';
            when "0111" => result(i+1) := '7';
            when "1000" => result(i+1) := '8';
            when "1001" => result(i+1) := '9';
            when "1010" => result(i+1) := 'A';
            when "1011" => result(i+1) := 'B';
            when "1100" => result(i+1) := 'C';
            when "1101" => result(i+1) := 'D';
            when "1110" => result(i+1) := 'E';
            when "1111" => result(i+1) := 'F';
            when others => result(i+1) := 'X';
        end case;
    end loop;
    return result;
end function;

component cache is
generic(
    ram_size : INTEGER := 32768
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
end component;

component memory is
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
end component;
	
-- test signals
signal reset : std_logic := '0';
signal clk : std_logic := '0';
constant clk_period : time := 1 ns;

signal s_addr : std_logic_vector (31 downto 0);
signal s_read : std_logic;
signal s_readdata : std_logic_vector (31 downto 0);
signal s_write : std_logic;
signal s_writedata : std_logic_vector (31 downto 0);
signal s_waitrequest : std_logic;

signal m_addr : integer range 0 to 2147483647;
signal m_read : std_logic;
signal m_readdata : std_logic_vector (7 downto 0);
signal m_write : std_logic;
signal m_writedata : std_logic_vector (7 downto 0);
signal m_waitrequest : std_logic;

begin

-- Connect the components which we instantiated above to their
-- respective signals.
dut: cache 
port map(
    clock => clk,
    reset => reset,

    s_addr => s_addr,
    s_read => s_read,
    s_readdata => s_readdata,
    s_write => s_write,
    s_writedata => s_writedata,
    s_waitrequest => s_waitrequest,

    m_addr => m_addr,
    m_read => m_read,
    m_readdata => m_readdata,
    m_write => m_write,
    m_writedata => m_writedata,
    m_waitrequest => m_waitrequest
);

MEM : memory
port map (
    clock => clk,
    writedata => m_writedata,
    address => m_addr,
    memwrite => m_write,
    memread => m_read,
    readdata => m_readdata,
    waitrequest => m_waitrequest
);
				

clk_process : process
begin
  clk <= '0';
  wait for clk_period/2;
  clk <= '1';
  wait for clk_period/2;
end process;

test_process : process
begin
    -- Initialize signals
    s_read <= '0';
    s_write <= '0';
    s_addr <= (others => '0');
    s_writedata <= (others => '0');
    
    -- Reset the cache
    reset <= '1';
    wait for clk_period;
    reset <= '0';
    wait for clk_period;
    
    report "Starting cache tests...";
    
    -- Test 1: Write to cache (address 0x0000)
    report "Test 1: Write data 0xDEADBEEF to address 0x0000";
    s_addr <= x"00000000";
    s_write <= '1';
    s_writedata <= x"DEADBEEF";
    wait until s_waitrequest = '0';
    wait for clk_period;
    s_write <= '0';
    wait for clk_period * 2;
    
    -- Test 2: Read from same address (should hit)
    report "Test 2: Read from address 0x0000 (expect cache hit)";
    s_addr <= x"00000000";
    s_read <= '1';
    wait until s_waitrequest = '0';
    wait for clk_period;
    assert s_readdata = x"DEADBEEF" 
        report "ERROR: Read data mismatch! Expected 0xDEADBEEF, got 0x" & to_hex_string(s_readdata)
        severity error;
    report "Read data: 0x" & to_hex_string(s_readdata);
    s_read <= '0';
    wait for clk_period * 2;
    
    -- Test 3: Write to another address in same block
    report "Test 3: Write data 0x12345678 to address 0x0004";
    s_addr <= x"00000004";
    s_write <= '1';
    s_writedata <= x"12345678";
    wait until s_waitrequest = '0';
    wait for clk_period;
    s_write <= '0';
    wait for clk_period * 2;
    
    -- Test 4: Read from new address (should hit, same block)
    report "Test 4: Read from address 0x0004 (expect cache hit)";
    s_addr <= x"00000004";
    s_read <= '1';
    wait until s_waitrequest = '0';
    wait for clk_period;
    assert s_readdata = x"12345678"
        report "ERROR: Read data mismatch! Expected 0x12345678, got 0x" & to_hex_string(s_readdata)
        severity error;
    report "Read data: 0x" & to_hex_string(s_readdata);
    s_read <= '0';
    wait for clk_period * 2;
    
    -- Test 5: Write to different block (will cause miss and eviction)
    report "Test 5: Write data 0xCAFEBABE to address 0x0200 (different index)";
    s_addr <= x"00000200";  -- Different index, will cause eviction
    s_write <= '1';
    s_writedata <= x"CAFEBABE";
    wait until s_waitrequest = '0';
    wait for clk_period;
    s_write <= '0';
    wait for clk_period * 5;  -- Allow time for write-back and read
    
    -- Test 6: Read from evicted address (should miss and load from memory)
    report "Test 6: Read from address 0x0000 (expect cache miss)";
    s_addr <= x"00000000";
    s_read <= '1';
    wait until s_waitrequest = '0';
    wait for clk_period;
    report "Read data: 0x" & to_hex_string(s_readdata);
    s_read <= '0';
    wait for clk_period * 2;
    
    report "All tests completed!";
    wait;
    
end process;
	
end;