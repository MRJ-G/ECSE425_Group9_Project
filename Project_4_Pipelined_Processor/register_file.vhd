library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity register_file is
    port(
        clk        : in  std_logic;
        -- read ports (combinational)
        rs1_addr   : in  std_logic_vector(4 downto 0);
        rs2_addr   : in  std_logic_vector(4 downto 0);
        rs1_data   : out std_logic_vector(31 downto 0);
        rs2_data   : out std_logic_vector(31 downto 0);
        -- write port (on rising edge)
        rd_addr    : in  std_logic_vector(4 downto 0);
        rd_data    : in  std_logic_vector(31 downto 0);
        rd_write   : in  std_logic;
        -- reset
        reset : in std_logic;
        -- dump port for testbench
        reg_out    : out std_logic_vector(32*32-1 downto 0)
    );
end entity register_file;

architecture rtl of register_file is
    type reg_array_t is array(0 to 31) of std_logic_vector(31 downto 0);
    signal regs : reg_array_t := (others => (others => '0'));
begin
    process(clk, reset)
    begin
        if reset = '1' then
            regs <= (others => (others => '0'));
        elsif rising_edge(clk) then
            if rd_write = '1' and unsigned(rd_addr) /= 0 then
                regs(to_integer(unsigned(rd_addr))) <= rd_data;
            end if;
        end if;
    end process;

    -- Read is combinational; x0 always 0
    rs1_data <= (others => '0') when unsigned(rs1_addr) = 0
                else regs(to_integer(unsigned(rs1_addr)));
    rs2_data <= (others => '0') when unsigned(rs2_addr) = 0
                else regs(to_integer(unsigned(rs2_addr)));

    -- Flatten for testbench dump
    gen_out: for i in 0 to 31 generate
        reg_out(32*(i+1)-1 downto 32*i) <= regs(i);
    end generate;
end architecture rtl;
