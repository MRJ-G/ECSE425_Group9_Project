library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;

entity alu is
    port(
        a      : in  std_logic_vector(31 downto 0);
        b      : in  std_logic_vector(31 downto 0);
        op     : in  std_logic_vector(3 downto 0);
        result : out std_logic_vector(31 downto 0)
    );
end entity alu;

architecture rtl of alu is
    signal sa, sb : signed(31 downto 0);
    signal ua, ub : unsigned(31 downto 0);
begin
    sa <= signed(a);
    sb <= signed(b);
    ua <= unsigned(a);
    ub <= unsigned(b);

    process(a, b, op, sa, sb, ua, ub)
        variable shamt : natural;
    begin
        shamt := to_integer(unsigned(b(4 downto 0)));
        case op is
            when ALU_ADD  => result <= std_logic_vector(sa + sb);
            when ALU_SUB  => result <= std_logic_vector(sa - sb);
            when ALU_MUL  => result <= std_logic_vector(resize(sa * sb, 32));
            when ALU_AND  => result <= a and b;
            when ALU_OR   => result <= a or b;
            when ALU_XOR  => result <= a xor b;
            when ALU_SLL  => result <= std_logic_vector(shift_left(ua, shamt));
            when ALU_SRL  => result <= std_logic_vector(shift_right(ua, shamt));
            when ALU_SRA  => result <= std_logic_vector(shift_right(sa, shamt));
            when ALU_SLT  =>
                if sa < sb then result <= x"00000001";
                else             result <= x"00000000";
                end if;
            when ALU_SLTU =>
                if ua < ub then result <= x"00000001";
                else             result <= x"00000000";
                end if;
            when ALU_LUI   => result <= b; -- pass through upper immediate
            when ALU_AUIPC => result <= std_logic_vector(sa + sb); -- PC + imm
            when others    => result <= (others => '0');
        end case;
    end process;
end architecture rtl;
