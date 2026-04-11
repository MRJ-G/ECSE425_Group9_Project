library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;

entity imm_gen is
    port(
        ir  : in  std_logic_vector(31 downto 0);
        imm : out std_logic_vector(31 downto 0)
    );
end entity imm_gen;

architecture rtl of imm_gen is
    signal opcode : std_logic_vector(6 downto 0);
begin
    opcode <= get_opcode(ir);

    process(ir, opcode)
    begin
        case opcode is
            -- I-type: addi, xori, ori, andi, slti, sltiu, load, jalr
            when OP_ITYPE | OP_LOAD | OP_JALR =>
                imm <= (31 downto 12 => ir(31)) & ir(31 downto 20); -- sign-extend bits 31:20

            -- S-type: sb, sh, sw
            when OP_STORE =>
                imm <= (31 downto 12 => ir(31)) & ir(31 downto 25) & ir(11 downto 7);

            -- B-type: beq, bne, blt, bge, bltu, bgeu
            -- Immediate is already the byte offset (bit 0 = 0 implicit)
            when OP_BRANCH =>
                imm <= (31 downto 13 => ir(31))
                       & ir(31) & ir(7) & ir(30 downto 25) & ir(11 downto 8) & '0';

            -- U-type: lui, auipc
            when OP_LUI | OP_AUIPC =>
                imm <= ir(31 downto 12) & x"000"; -- imm = imm << 12

            -- J-type: jal
            -- same as branch (bit 0 = 0 implicit)
            when OP_JAL =>
                imm <= (31 downto 21 => ir(31))
                       & ir(31) & ir(19 downto 12) & ir(20) & ir(30 downto 21) & '0';

            when others =>
                imm <= (others => '0');
        end case;
    end process;

    -- Note: shift-immediate instructions (slli/srli/srai) use I-type
    -- format. The shift amount is in imm(4 downto 0) which ALU reads
    -- from the B input. The upper bits don't matter for shifts.

end architecture rtl;
