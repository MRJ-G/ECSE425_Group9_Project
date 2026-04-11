library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pipeline_types.all;

entity processor is
    port(
        clk   : in std_logic;
        reset : in std_logic;
        -- Testbench: load instructions into imem
        imem_load_addr : in  integer range 0 to 1023;
        imem_load_data : in  std_logic_vector(31 downto 0);
        imem_load_en   : in  std_logic;
        -- Testbench: dump data memory block (base word index, 0..8191)
        dmem_dump_addr : in  integer range 0 to 8191;
        dmem_dump_data : out std_logic_vector(32*32-1 downto 0);
        -- Testbench: dump register file
        reg_dump : out std_logic_vector(32*32-1 downto 0) -- 32 registers * 32 bits
    );
end entity processor;

architecture rtl of processor is

    -- Pipeline registers
    signal if_id  : if_id_t  := IF_ID_ZERO;
    signal id_ex  : id_ex_t  := ID_EX_ZERO;
    signal ex_mem : ex_mem_t := EX_MEM_ZERO;
    signal mem_wb : mem_wb_t := MEM_WB_ZERO;

    -- PC
    signal pc      : std_logic_vector(31 downto 0) := (others => '0');
    signal pc_next : std_logic_vector(31 downto 0);

    -- Hazard / flush
    signal stall       : std_logic := '0';
    signal branch_taken: std_logic;

    -- Decode stage wires, updated by control and imm_gen
    signal ctrl_RegWrite : std_logic;
    signal ctrl_MemRead  : std_logic;
    signal ctrl_MemWrite : std_logic;
    signal ctrl_ALUSrc   : std_logic;
    signal ctrl_ALUOp    : std_logic_vector(3 downto 0);
    signal ctrl_MemToReg : std_logic_vector(1 downto 0);
    signal ctrl_Branch   : std_logic;
    signal ctrl_BrType   : std_logic_vector(2 downto 0);
    signal ctrl_Jump     : std_logic;
    signal ctrl_IsJALR   : std_logic;
    signal decoded_imm   : std_logic_vector(31 downto 0);

    -- Register file wires
    signal rf_rs1_data : std_logic_vector(31 downto 0);
    signal rf_rs2_data : std_logic_vector(31 downto 0);
    signal wb_rd_addr  : std_logic_vector(4 downto 0);
    signal wb_rd_data  : std_logic_vector(31 downto 0);

    -- Execute stage wires
    signal alu_a      : std_logic_vector(31 downto 0);
    signal alu_b      : std_logic_vector(31 downto 0);
    signal alu_result : std_logic_vector(31 downto 0);
    signal br_target  : std_logic_vector(31 downto 0);
    signal br_cond    : std_logic;

    -- Instruction memory signals
    signal imem_addr      : integer range 0 to 1023;
    signal imem_readdata  : std_logic_vector(31 downto 0);
    signal imem_real_addr : integer range 0 to 1023;

    -- Data memory signals
    signal dmem_addr      : integer range 0 to 8191;
    signal dmem_readdata  : std_logic_vector(31 downto 0);
    signal dmem_write_en  : std_logic;
    signal dmem_dump_bus  : std_logic_vector(32*32-1 downto 0);

begin

    -- ================================================================
    --  MEMORY INSTANTIATION
    -- ================================================================

    -- Instruction memory (1024 words)
    imem_real_addr <= imem_load_addr when imem_load_en = '1'
                      else imem_addr;

    u_imem: entity work.memory
        generic map(ram_size => 1024)
        port map(
            clock     => clk,
            writedata => imem_load_data,
            address   => imem_real_addr,
            memwrite  => imem_load_en,
            memread   => '1',
            readdata  => imem_readdata,
            dump_base_addr => 0,
            dump_out       => open
        );

    -- Data memory (8192 words = 32768 bytes)
    u_dmem: entity work.memory
        generic map(ram_size => 8192)
        port map(
            clock     => clk,
            writedata => ex_mem.B,
            address   => dmem_addr,
            memwrite  => dmem_write_en,
            memread   => '1',
            readdata  => dmem_readdata,
            dump_base_addr => dmem_dump_addr,
            dump_out       => dmem_dump_bus
        );

    dmem_dump_data <= dmem_dump_bus;

    -- ================================================================
    --      COMPONENT INSTANTIATION
    -- ================================================================

    u_control: entity work.control
        port map(
            ir       => if_id.IR,
            RegWrite => ctrl_RegWrite,
            MemRead  => ctrl_MemRead,
            MemWrite => ctrl_MemWrite,
            ALUSrc   => ctrl_ALUSrc,
            ALUOp    => ctrl_ALUOp,
            MemToReg => ctrl_MemToReg,
            Branch   => ctrl_Branch,
            BrType   => ctrl_BrType,
            Jump     => ctrl_Jump,
            IsJALR   => ctrl_IsJALR
        );

    u_imm_gen: entity work.imm_gen
        port map(
            ir  => if_id.IR,
            imm => decoded_imm
        );

    u_regfile: entity work.register_file
        port map(
            clk      => clk,
            rs1_addr => get_rs1(if_id.IR),
            rs2_addr => get_rs2(if_id.IR),
            rs1_data => rf_rs1_data,
            rs2_data => rf_rs2_data,
            rd_addr  => wb_rd_addr,
            rd_data  => wb_rd_data,
            rd_write => mem_wb.RegWrite,
            reg_out  => reg_dump
        );

    u_alu: entity work.alu
        port map(
            a      => alu_a,
            b      => alu_b,
            op     => id_ex.ALUOp,
            result => alu_result
        );

    -- ================================================================
    --  STAGE 1: INSTRUCTION FETCH
    -- ================================================================

    imem_addr <= to_integer(unsigned(pc(11 downto 2)));
    
    -- Redirect from EX-stage decision so PC/flush take effect on the very next edge.
    branch_taken <= (id_ex.Branch and br_cond) or id_ex.Jump;

    pc_next <= br_target when branch_taken = '1'
               else std_logic_vector(unsigned(pc) + 4);

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                pc <= (others => '0');
            elsif stall = '0' then
                pc <= pc_next;
            end if; -- if stall = '1', hold the PC (don't fetch a new instruction)
        end if;
    end process;

    -- ================================================================
    --  IF/ID PIPELINE REGISTER
    -- ================================================================

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' or branch_taken = '1' then
                if_id <= IF_ID_ZERO;
            elsif stall = '0' then
                if_id.IR  <= imem_readdata;
                if_id.PC  <= pc;
                if_id.NPC <= std_logic_vector(unsigned(pc) + 4);
            end if;
        end if;
    end process;

    -- ================================================================
    --  STAGE 2: INSTRUCTION DECODE
    -- ================================================================

    -- Decode stage: control unit+immediate generator+register file read (all init above)
        -- Control: generate control signals based on opcode/funct3/funct7
        -- Immediate generator: generate immediate based on instruction format
        -- Register file: read rs1/rs2

    -- ================================================================
    --  ID/EX PIPELINE REGISTER
    -- ================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' or branch_taken = '1' or stall = '1' then
                id_ex <= ID_EX_ZERO; -- reset or no-op
            else
                id_ex.IR       <= if_id.IR;
                id_ex.PC       <= if_id.PC;
                id_ex.NPC      <= if_id.NPC;
                id_ex.A        <= rf_rs1_data;
                id_ex.B        <= rf_rs2_data;
                id_ex.Imm      <= decoded_imm;
                id_ex.RegWrite <= ctrl_RegWrite;
                id_ex.MemRead  <= ctrl_MemRead;
                id_ex.MemWrite <= ctrl_MemWrite;
                id_ex.ALUSrc   <= ctrl_ALUSrc;
                id_ex.ALUOp    <= ctrl_ALUOp;
                id_ex.MemToReg <= ctrl_MemToReg;
                id_ex.Branch   <= ctrl_Branch;
                id_ex.BrType   <= ctrl_BrType;
                id_ex.Jump     <= ctrl_Jump;
                id_ex.IsJALR   <= ctrl_IsJALR;
            end if;
        end if;
    end process;

    -- ================================================================
    --  STAGE 3: EXECUTE
    -- ================================================================
    
    alu_a <= id_ex.PC when id_ex.ALUOp = ALU_AUIPC
             else id_ex.A; -- only auipc uses the PC as ALU input A, otherwise use the register value

    alu_b <= id_ex.Imm when id_ex.ALUSrc = '1'
             else id_ex.B;

    -- JALR: PC = A + imm (alu_result)
    -- Other: PC = PC + imm (dedicated adder in EX, not ALU)
    br_target <= alu_result when id_ex.IsJALR = '1'
                 else std_logic_vector(unsigned(id_ex.PC) + unsigned(id_ex.Imm));

    ------------------------------------------------------------------------------
    -- alu_result is computed in the ALU module (in component instantiation above)
    ------------------------------------------------------------------------------

    -- BR COND resolution using dedicated circuit in EX stage (not ALU)
    process(id_ex)
        variable sa, sb : signed(31 downto 0);
        variable ua, ub : unsigned(31 downto 0);
    begin
        sa := signed(id_ex.A);
        sb := signed(id_ex.B);
        ua := unsigned(id_ex.A); -- not required
        ub := unsigned(id_ex.B); -- not required
        case id_ex.BrType is
            when BR_BEQ  => br_cond <= '1' when id_ex.A = id_ex.B   else '0';
            when BR_BNE  => br_cond <= '1' when id_ex.A /= id_ex.B  else '0';
            when BR_BLT  => br_cond <= '1' when sa < sb             else '0';
            when BR_BGE  => br_cond <= '1' when sa >= sb            else '0';
            when BR_BLTU => br_cond <= '1' when ua < ub             else '0'; -- not required
            when BR_BGEU => br_cond <= '1' when ua >= ub            else '0'; -- not required
            when others  => br_cond <= '0';
        end case;
    end process;

    -- ================================================================
    --  EX/MEM PIPELINE REGISTER
    -- ================================================================

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' or branch_taken = '1' then
                ex_mem <= EX_MEM_ZERO;
            else
                ex_mem.IR        <= id_ex.IR;
                ex_mem.NPC       <= id_ex.NPC;
                ex_mem.ALUOutput <= alu_result;
                ex_mem.B         <= id_ex.B;
                ex_mem.BrTarget  <= br_target;
                ex_mem.Cond      <= br_cond;
                ex_mem.RegWrite  <= id_ex.RegWrite;
                ex_mem.MemRead   <= id_ex.MemRead;
                ex_mem.MemWrite  <= id_ex.MemWrite;
                ex_mem.MemToReg  <= id_ex.MemToReg;
                ex_mem.Branch    <= id_ex.Branch;
                ex_mem.Jump      <= id_ex.Jump;
            end if;
        end if;
    end process;

    -- ================================================================
    --  STAGE 4: MEMORY
    -- ================================================================

    -- Word address = byte address / 4
    dmem_addr    <= to_integer(unsigned(ex_mem.ALUOutput(14 downto 2)));
    dmem_write_en <= ex_mem.MemWrite;

    -- lw: just pass the full word through
    -- sw: ex_mem.B is connected directly to memory writedata above

    -- ================================================================
    --  MEM/WB PIPELINE REGISTER
    -- ================================================================

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                mem_wb <= MEM_WB_ZERO;
            else
                mem_wb.IR        <= ex_mem.IR;
                mem_wb.NPC       <= ex_mem.NPC;
                mem_wb.ALUOutput <= ex_mem.ALUOutput;
                mem_wb.LMD       <= dmem_readdata;
                mem_wb.RegWrite  <= ex_mem.RegWrite;
                mem_wb.MemToReg  <= ex_mem.MemToReg;
            end if;
        end if;
    end process;

    -- ================================================================
    --  STAGE 5: WRITE BACK
    -- ================================================================

    wb_rd_addr <= get_rd(mem_wb.IR);

    wb_rd_data <= mem_wb.LMD       when mem_wb.MemToReg = WB_MEM
                  else mem_wb.NPC  when mem_wb.MemToReg = WB_PC4
                  else mem_wb.ALUOutput;

    -- ================================================================
    --  HAZARD DETECTION (placeholder)
    -- ================================================================
    -- Uncomment to enable:
    -- stall <= '1' when
    --   (id_ex.RegWrite='1' and get_rd(id_ex.IR)/="00000" and
    --    (get_rd(id_ex.IR)=get_rs1(if_id.IR) or
    --     get_rd(id_ex.IR)=get_rs2(if_id.IR)))
    --   or
    --   (ex_mem.RegWrite='1' and get_rd(ex_mem.IR)/="00000" and
    --    (get_rd(ex_mem.IR)=get_rs1(if_id.IR) or
    --     get_rd(ex_mem.IR)=get_rs2(if_id.IR)))
    --   else '0';
    stall <= '0';

end architecture rtl;
