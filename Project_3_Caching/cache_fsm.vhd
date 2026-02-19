library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache_fsm is
port(
	clock : in std_logic;
	reset : in std_logic;

    -- CPU side (from cache Avalon slave ports)
    s_read          : in  std_logic;
    s_write         : in  std_logic;
    s_waitrequest   : out std_logic;  -- stall CPU

	-- Cache datapath status (from cache internals)
    cache_hit       : in  std_logic;
    dirty_bit       : in  std_logic;
    valid_bit       : in  std_logic;

    -- Cache datapath control (to cache internals)
    cache_write_en  : out std_logic;
    dirty_bit_set   : out std_logic;
    dirty_bit_reset : out std_logic;
    valid_bit_set   : out std_logic;

    -- Memory side (drives cache's m_* ports)
    m_read          : out std_logic;
    m_write         : out std_logic;
    m_waitrequest   : in  std_logic   -- memory busy signal
);
end cache_fsm;

architecture arch of cache_fsm is

-- declare signals here


    -- FSM state type and signals, need to update
    type state_type is (IDLE, COMPARE, WRITE_BACK, FETCH, ALLOCATE);
    -- current and next state signals
    signal current_state : state_type;
    signal next_state    : state_type;



begin

-- make circuits here
process (clock, reset)
begin
    if (reset = '1') then
        current_state <= IDLE;
        -- reset logic here
    elsif rising_edge(clock) then
        -- FSM logic here
        current_state <= next_state;
        






    end if;
end process;

	
end arch;