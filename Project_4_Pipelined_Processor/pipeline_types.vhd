library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package pipeline_types is

    -- ALU operation encoding
    constant ALU_ADD  : std_logic_vector(3 downto 0) := "0000";
    constant ALU_SUB  : std_logic_vector(3 downto 0) := "0001";
    constant ALU_MUL  : std_logic_vector(3 downto 0) := "0010";
    constant ALU_AND  : std_logic_vector(3 downto 0) := "0011";
    constant ALU_OR   : std_logic_vector(3 downto 0) := "0100";
    constant ALU_XOR  : std_logic_vector(3 downto 0) := "0101";
    constant ALU_SLL  : std_logic_vector(3 downto 0) := "0110";
    constant ALU_SRL  : std_logic_vector(3 downto 0) := "0111";
    constant ALU_SRA  : std_logic_vector(3 downto 0) := "1000";
    constant ALU_SLT  : std_logic_vector(3 downto 0) := "1001";
    constant ALU_SLTU : std_logic_vector(3 downto 0) := "1010";
    constant ALU_LUI  : std_logic_vector(3 downto 0) := "1011";
    constant ALU_AUIPC: std_logic_vector(3 downto 0) := "1100";

    -- Write-back source select
    constant WB_ALU : std_logic_vector(1 downto 0) := "00";
    constant WB_MEM : std_logic_vector(1 downto 0) := "01";
    constant WB_PC4 : std_logic_vector(1 downto 0) := "10";

    -- Branch type encoding
    constant BR_NONE : std_logic_vector(2 downto 0) := "000"; -- not a branch
    constant BR_BEQ  : std_logic_vector(2 downto 0) := "001";
    constant BR_BNE  : std_logic_vector(2 downto 0) := "010";
    constant BR_BLT  : std_logic_vector(2 downto 0) := "011";
    constant BR_BGE  : std_logic_vector(2 downto 0) := "100";
    constant BR_BLTU : std_logic_vector(2 downto 0) := "101"; -- bonus feature
    constant BR_BGEU : std_logic_vector(2 downto 0) := "110"; -- bonus feature

    -- RISC-V opcodes
    constant OP_RTYPE  : std_logic_vector(6 downto 0) := "0110011";
    constant OP_ITYPE  : std_logic_vector(6 downto 0) := "0010011";
    constant OP_LOAD   : std_logic_vector(6 downto 0) := "0000011";
    constant OP_STORE  : std_logic_vector(6 downto 0) := "0100011";
    constant OP_BRANCH : std_logic_vector(6 downto 0) := "1100011";
    constant OP_JAL    : std_logic_vector(6 downto 0) := "1101111";
    constant OP_JALR   : std_logic_vector(6 downto 0) := "1100111";
    constant OP_LUI    : std_logic_vector(6 downto 0) := "0110111";
    constant OP_AUIPC  : std_logic_vector(6 downto 0) := "0010111";

    -- IF/ID
    type if_id_t is record
        IR  : std_logic_vector(31 downto 0);
        PC  : std_logic_vector(31 downto 0);
        NPC : std_logic_vector(31 downto 0);
    end record;

    constant IF_ID_ZERO : if_id_t := (
        IR  => (others => '0'),
        PC  => (others => '0'),
        NPC => (others => '0')
    );

    -- ID/EX
    type id_ex_t is record
        IR       : std_logic_vector(31 downto 0);
        PC       : std_logic_vector(31 downto 0);
        NPC      : std_logic_vector(31 downto 0);
        A        : std_logic_vector(31 downto 0);
        B        : std_logic_vector(31 downto 0);
        Imm      : std_logic_vector(31 downto 0);
        RegWrite : std_logic;
        MemRead  : std_logic;
        MemWrite : std_logic;
        ALUSrc   : std_logic;
        ALUOp    : std_logic_vector(3 downto 0);
        MemToReg : std_logic_vector(1 downto 0);
        Branch   : std_logic;
        BrType   : std_logic_vector(2 downto 0);
        Jump     : std_logic;
        IsJALR   : std_logic;
    end record;

    constant ID_EX_ZERO : id_ex_t := (
        IR       => (others => '0'),
        PC       => (others => '0'),
        NPC      => (others => '0'),
        A        => (others => '0'),
        B        => (others => '0'),
        Imm      => (others => '0'),
        RegWrite => '0',
        MemRead  => '0',
        MemWrite => '0',
        ALUSrc   => '0',
        ALUOp    => (others => '0'),
        MemToReg => (others => '0'),
        Branch   => '0',
        BrType   => (others => '0'),
        Jump     => '0',
        IsJALR   => '0'
    );

    -- EX/MEM
    type ex_mem_t is record
        IR         : std_logic_vector(31 downto 0);
        NPC        : std_logic_vector(31 downto 0);
        ALUOutput  : std_logic_vector(31 downto 0);
        B          : std_logic_vector(31 downto 0);
        BrTarget   : std_logic_vector(31 downto 0);
        Cond       : std_logic;
        RegWrite   : std_logic;
        MemRead    : std_logic;
        MemWrite   : std_logic;
        MemToReg   : std_logic_vector(1 downto 0);
        Branch     : std_logic;
        Jump       : std_logic;
    end record;

    constant EX_MEM_ZERO : ex_mem_t := (
        IR         => (others => '0'),
        NPC        => (others => '0'),
        ALUOutput  => (others => '0'),
        B          => (others => '0'),
        BrTarget   => (others => '0'),
        Cond       => '0',
        RegWrite   => '0',
        MemRead    => '0',
        MemWrite   => '0',
        MemToReg   => (others => '0'),
        Branch     => '0',
        Jump       => '0'
    );

    -- MEM/WB
    type mem_wb_t is record
        IR         : std_logic_vector(31 downto 0);
        NPC        : std_logic_vector(31 downto 0);
        ALUOutput  : std_logic_vector(31 downto 0);
        LMD        : std_logic_vector(31 downto 0);
        RegWrite   : std_logic;
        MemToReg   : std_logic_vector(1 downto 0);
    end record;

    constant MEM_WB_ZERO : mem_wb_t := (
        IR         => (others => '0'),
        NPC        => (others => '0'),
        ALUOutput  => (others => '0'),
        LMD        => (others => '0'),
        RegWrite   => '0',
        MemToReg   => (others => '0')
    );

    -- Helper functions
    function get_rd(ir : std_logic_vector(31 downto 0)) return std_logic_vector;
    function get_rs1(ir : std_logic_vector(31 downto 0)) return std_logic_vector;
    function get_rs2(ir : std_logic_vector(31 downto 0)) return std_logic_vector;
    function get_opcode(ir : std_logic_vector(31 downto 0)) return std_logic_vector;
    function get_funct3(ir : std_logic_vector(31 downto 0)) return std_logic_vector;
    function get_funct7(ir : std_logic_vector(31 downto 0)) return std_logic_vector;

end package pipeline_types;

package body pipeline_types is
    function get_rd(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
    begin return ir(11 downto 7); end function;
    function get_rs1(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
    begin return ir(19 downto 15); end function;
    function get_rs2(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
    begin return ir(24 downto 20); end function;
    function get_opcode(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
    begin return ir(6 downto 0); end function;
    function get_funct3(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
    begin return ir(14 downto 12); end function;
    function get_funct7(ir : std_logic_vector(31 downto 0)) return std_logic_vector is
    begin return ir(31 downto 25); end function;
end package body pipeline_types;
