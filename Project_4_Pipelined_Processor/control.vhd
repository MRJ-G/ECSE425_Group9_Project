library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;

entity control is
    port(
        ir       : in  std_logic_vector(31 downto 0);
        RegWrite : out std_logic;
        MemRead  : out std_logic;
        MemWrite : out std_logic;
        ALUSrc   : out std_logic; -- 0 = reg, 1 = imm
        ALUOp    : out std_logic_vector(3 downto 0); -- defined in pipeline_types.vhd
        MemToReg : out std_logic_vector(1 downto 0); -- 00 = ALU, 01 = MEM, 10 = NPC(PC+4)
        Branch   : out std_logic; -- 1: branch instruction (beq/bne/blt/bge)
        BrType   : out std_logic_vector(2 downto 0);
        Jump     : out std_logic;
        IsJALR   : out std_logic
    );
end entity control;

architecture rtl of control is
    signal opcode : std_logic_vector(6 downto 0);
    signal funct3 : std_logic_vector(2 downto 0);
    signal funct7 : std_logic_vector(6 downto 0);
begin
    opcode <= get_opcode(ir);
    funct3 <= get_funct3(ir);
    funct7 <= get_funct7(ir);

    process(opcode, funct3, funct7)
    begin
        -- Defaults (NOP-safe)
        RegWrite <= '0'; MemRead <= '0'; MemWrite <= '0';
        ALUSrc   <= '0'; ALUOp   <= ALU_ADD;
        MemToReg <= WB_ALU; Branch <= '0'; BrType <= BR_NONE;
        Jump     <= '0'; IsJALR  <= '0';

        case opcode is
            -- R-type: add, sub, mul, and, or, sll, srl, sra, slt, sltu
            when OP_RTYPE =>
                RegWrite <= '1';
                case funct3 is
                    when "000" =>
                        if funct7 = "0000001" then ALUOp <= ALU_MUL;
                        elsif funct7(5) = '1' then ALUOp <= ALU_SUB; -- funct7 = 0x20
                        else                       ALUOp <= ALU_ADD; -- funct7 = 0x00
                        end if;
                    when "001" => ALUOp <= ALU_SLL;
                    when "010" => ALUOp <= ALU_SLT; -- not required
                    when "011" => ALUOp <= ALU_SLTU; -- not required
                    when "100" => ALUOp <= ALU_XOR; -- not required
                    when "101" =>
                        if funct7(5) = '1' then ALUOp <= ALU_SRA; -- funct7 = 0x20
                        else                    ALUOp <= ALU_SRL;
                        end if;
                    when "110" => ALUOp <= ALU_OR;
                    when "111" => ALUOp <= ALU_AND;
                    when others => null;
                end case;

            -- I-type ALU: addi, xori, ori, andi, slti, sltiu, slli, srli, srai
            when OP_ITYPE =>
                RegWrite <= '1';
                ALUSrc   <= '1'; -- use immediate
                case funct3 is
                    when "000" => ALUOp <= ALU_ADD;
                    when "001" => ALUOp <= ALU_SLL; -- not required
                    when "010" => ALUOp <= ALU_SLT;
                    when "011" => ALUOp <= ALU_SLTU; -- not required
                    when "100" => ALUOp <= ALU_XOR;
                    when "101" =>
                        if funct7(5) = '1' then ALUOp <= ALU_SRA; -- not required
                        else                    ALUOp <= ALU_SRL; -- not required
                        end if;
                    when "110" => ALUOp <= ALU_OR;
                    when "111" => ALUOp <= ALU_AND;
                    when others => null;
                end case;

            -- Load word (lw only)
            when OP_LOAD =>
                RegWrite <= '1';
                MemRead  <= '1';
                ALUSrc   <= '1';
                ALUOp    <= ALU_ADD;
                MemToReg <= WB_MEM;

            -- Store word (sw only)
            when OP_STORE =>
                MemWrite <= '1';
                ALUSrc   <= '1';
                ALUOp    <= ALU_ADD;

            -- Branch: beq, bne, blt, bge, bltu, bgeu
            when OP_BRANCH =>
                Branch <= '1';
                case funct3 is
                    when "000" => BrType <= BR_BEQ;
                    when "001" => BrType <= BR_BNE;
                    when "100" => BrType <= BR_BLT;
                    when "101" => BrType <= BR_BGE;
                    when "110" => BrType <= BR_BLTU; -- not required
                    when "111" => BrType <= BR_BGEU; -- not required
                    when others => null;
                end case;

            -- JAL
            when OP_JAL =>
                RegWrite <= '1';
                Jump     <= '1';
                MemToReg <= WB_PC4; -- rd = PC + 4

            -- JALR
            when OP_JALR =>
                RegWrite <= '1';
                Jump     <= '1';
                IsJALR   <= '1';
                ALUSrc   <= '1';
                ALUOp    <= ALU_ADD;
                MemToReg <= WB_PC4;

            -- LUI
            when OP_LUI =>
                RegWrite <= '1';
                ALUSrc   <= '1';
                ALUOp    <= ALU_LUI;

            -- AUIPC
            when OP_AUIPC =>
                RegWrite <= '1';
                ALUSrc   <= '1';
                ALUOp    <= ALU_AUIPC;

            when others => null;
        end case;
    end process;
end architecture rtl;
