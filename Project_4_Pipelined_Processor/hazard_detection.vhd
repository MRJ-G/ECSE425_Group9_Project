-- =============================================================================
-- (Note: combinatorial read and sync write => read and write can happen in the same cycle / as if write at fisrt half of cycle, read at second half)
--   The register file performs combinatorial reads and synchronous writes
--   (write on rising edge).  The WB stage writes at the *end* of its cycle
--   (i.e. the rising edge that starts the next cycle).  Therefore, for an
--   instruction currently in the ID stage:
--
--     1. Producer in EX  (id_ex):  result available after MEM + WB write.
--        Two more stall cycles are needed before ID can read the correct
--        value.  The condition will remain true for both stall cycles because
--        the frozen IF/ID register still holds the consumer, while the
--        producer advances through MEM then WB and finally writes the RF.
--
--     2. Producer in MEM (ex_mem): result available after WB write, which
--        happens at the rising edge that ends the *current* stall cycle.
--        One stall cycle is needed.
--
--     3. Producer in WB  (mem_wb): the WB write happens at the rising edge
--        that ends the current cycle.  The ID stage reads combinatorially
--        *before* that edge, so it sees the stale value.  One stall cycle
--        is needed so that on the *next* cycle the ID stage reads the
--        freshly-written value.
--
--   The logic below checks all three stages.  The cascading nature of stalls
--   (IF/ID frozen while id_ex/ex_mem/mem_wb advance) means a single unified
--   condition handles multi-cycle stalls correctly without a counter.
--
-- Operand use rules:
--   Rather than decode which instruction types use which registers, we
--   conservatively check *both* rs1 and rs2 for every instruction.
--   Over-stalling is functionally safe; missed stalls would be incorrect.
--   Exception: register x0 (address "00000") is hardwired to zero and never
--   written; hazards against x0 are suppressed on *both* the producer side
--   (rd /= x0) and implicitly on the consumer side (a write to x0 in the
--   producer has no effect, so the consumer already reads 0 correctly).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;

entity hazard_detection is
    port(
        -- Instruction currently in the ID stage (from IF/ID register)
        if_id_ir  : in std_logic_vector(31 downto 0);

        -- EX stage pipeline register (ID/EX)
        id_ex_ir       : in std_logic_vector(31 downto 0);
        id_ex_regwrite : in std_logic;

        -- MEM stage pipeline register (EX/MEM)
        ex_mem_ir       : in std_logic_vector(31 downto 0);
        ex_mem_regwrite : in std_logic;

        -- WB stage pipeline register (MEM/WB)
        mem_wb_ir       : in std_logic_vector(31 downto 0);
        mem_wb_regwrite : in std_logic;

        -- Output: assert '1' to stall the pipeline for one cycle
        stall : out std_logic
    );
end entity hazard_detection;

architecture rtl of hazard_detection is

    -- Source registers of the instruction currently being decoded
    signal id_rs1 : std_logic_vector(4 downto 0);
    signal id_rs2 : std_logic_vector(4 downto 0);
    signal id_opc : std_logic_vector(6 downto 0);

    -- Destination registers of instructions in downstream stages
    signal ex_rd  : std_logic_vector(4 downto 0);
    signal mem_rd : std_logic_vector(4 downto 0);
    signal wb_rd  : std_logic_vector(4 downto 0);

    -- Per-stage hazard flags
    signal hazard_ex  : std_logic;
    signal hazard_mem : std_logic;
    signal hazard_wb  : std_logic;

    -- Whether the ID instruction actually uses rs2
    -- S-type and B-type always use rs2.  R-type uses rs2.
    -- I-type, U-type, J-type do NOT use rs2 as a data source.
    signal id_uses_rs2 : std_logic;

begin

    -- Extract fields from each pipeline register
    id_rs1 <= get_rs1(if_id_ir);
    id_rs2 <= get_rs2(if_id_ir);
    id_opc <= get_opcode(if_id_ir);

    ex_rd  <= get_rd(id_ex_ir);
    mem_rd <= get_rd(ex_mem_ir);
    wb_rd  <= get_rd(mem_wb_ir);

    -- Determine whether the ID instruction uses rs2 as a data source.
    -- R-type, S-type, and B-type instructions all use rs2.
    -- I-type (ALU imm, load, JALR), U-type (LUI, AUIPC), J-type (JAL) do NOT.
    -- Conservatively treating all instructions as using rs2 is also correct
    -- (just causes extra stalls for I/U/J-type instructions).
    -- We decode here for accuracy to avoid unnecessary stalls.
    id_uses_rs2 <= '1' when (id_opc = OP_RTYPE  or
                              id_opc = OP_STORE  or
                              id_opc = OP_BRANCH)
                   else '0';

    -- -------------------------------------------------------------------------
    -- Hazard from EX stage (producer is in ID/EX):
    --   The producer has computed nothing yet (ALU result available end of EX).
    --   Two stall cycles will be needed.  However, we only assert '1' here for
    --   one cycle at a time; the frozen IF/ID causes the condition to remain
    --   true next cycle (producer moves to MEM → hazard_mem fires), and the
    --   cycle after that (producer in WB → hazard_wb fires).
    -- -------------------------------------------------------------------------
    hazard_ex <= '1' when (
                    id_ex_regwrite = '1' and
                    ex_rd /= "00000" and
                    (ex_rd = id_rs1 or
                     (id_uses_rs2 = '1' and ex_rd = id_rs2))
                 ) else '0';

    -- -------------------------------------------------------------------------
    -- Hazard from MEM stage (producer is in EX/MEM):
    --   The ALU result is in EX/MEM.ALUOutput.  The WB write occurs at the
    --   rising edge that ends this cycle.  ID reads the stale value this cycle.
    --   One stall cycle will push the write before the next ID read.
    -- -------------------------------------------------------------------------
    hazard_mem <= '1' when (
                    ex_mem_regwrite = '1' and
                    mem_rd /= "00000" and
                    (mem_rd = id_rs1 or
                     (id_uses_rs2 = '1' and mem_rd = id_rs2))
                 ) else '0';

    -- -------------------------------------------------------------------------
    -- Hazard from WB stage (producer is in MEM/WB):
    --   mem_wb.RegWrite will cause a write at the NEXT rising edge.
    --   The ID stage is reading the register file combinatorially right now,
    --   before that edge, so it sees the pre-write (stale) value.
    --   One stall cycle causes the next ID read to occur after the write.
    -- -------------------------------------------------------------------------
    hazard_wb <= '1' when (
                   mem_wb_regwrite = '1' and
                   wb_rd /= "00000" and
                   (wb_rd = id_rs1 or
                    (id_uses_rs2 = '1' and wb_rd = id_rs2))
                ) else '0';

    -- Combine: stall if any downstream stage has a pending write to a source
    -- register of the current ID instruction.
    stall <= hazard_ex or hazard_mem or hazard_wb;

end architecture rtl;