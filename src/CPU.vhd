library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;


entity CPU is port(
    CLK         : in    std_logic;
    MEM_ADDR    : out   std_logic_vector(15 downto 0);
    MEM_IN      : out   std_logic_vector(15 downto 0);
    MEM_OUT     : in    std_logic_vector(15 downto 0);
    MEM_WE      : out   std_logic;
    HALT        : in    std_logic;
    INTERRUPT   : in    std_logic;

    DEBUG_OUT   : out   std_logic_vector(7 downto 0) := X"00"
);
end entity;

architecture mannerisms of CPU is
    -- Custom types used
    type EXEC_STATES_T  is (FETCH, IDLE, EXEC, CONTD, CONTD2);
    type REGS_T         is array (15 downto 0) of std_logic_vector(15 downto 0);

    -- CPU micro-state
    signal state                :   EXEC_STATES_T                   := FETCH;
    signal state_after_idle     :   EXEC_STATES_T                   := FETCH;
    
    -- Saved values for subsequent instruction cycles
    signal opcode_contd         :   std_logic_vector(5 downto 0)    := "000000";
    signal dst_contd            :   std_logic_vector(4 downto 0)    := "00000";
    signal src_contd            :   std_logic_vector(4 downto 0)    := "00000";
    signal dst_content_contd    :   std_logic_vector(15 downto 0)   := X"0000";
    signal src_content_contd    :   std_logic_vector(15 downto 0)   := X"0000";

    -- General purpose registers
    signal regs                 :   REGS_T                          := (others => X"0000");

    -- Instruction pointer
    signal ip                   :   std_logic_vector(15 downto 0)   := X"0000";

    -- Interrupt stuff
    signal last_interrupt       : std_logic := '0';

begin
    -- insert mem things
    DEBUG_OUT <= regs(0)(7 downto 0);

    process(CLK)
        -- alu_op_out: contains the last carry bit to set the flag
        variable alu_op_out : std_logic_vector(16 downto 0);
        variable alu_minus  : std_logic_vector(15 downto 0);
        -- mult_tmp: contains the full result of a multiplication
        variable mult_tmp : std_logic_vector(31 downto 0) := X"00000000";
        -- tmp
        variable tmp : std_logic_vector(15 downto 0);

        variable opcode : std_logic_vector(5 downto 0);
        variable src : std_logic_vector(4 downto 0);
        variable dst : std_logic_vector(4 downto 0);

        variable dst_content : std_logic_vector(15 downto 0);
        variable src_content : std_logic_vector(15 downto 0);

        variable tmp_content : std_logic_vector(15 downto 0);
        variable jmp_cond_ok : std_logic;
    begin
        if(rising_edge(CLK)) then
            case state is
                when FETCH =>
                    if (INTERRUPT = '1' and last_interrupt = '0' and regs(14)(4) = '1') then
                        MEM_ADDR <= regs(15) - 1;
                        MEM_WE <= '1';
                        MEM_IN <= ip;
    
                        regs(15) <= regs(15) - 1;
    
                        ip <= X"0002";
    
                        state_after_idle <= FETCH;
                        state <= IDLE;
                    elsif (HALT = '0') then
                        MEM_ADDR <= ip;
                        MEM_WE <= '0';
    
                        state <= IDLE;
                        state_after_idle <= EXEC;
                    end if;

                    last_interrupt <= INTERRUPT;

                when IDLE =>
                    state <= state_after_idle;

                when EXEC =>
                    opcode := MEM_OUT(5 downto 0);
                    dst := MEM_OUT(10 downto 6);
                    src := MEM_OUT(15 downto 11);

                    dst_content := regs(to_integer(unsigned(dst)));
                    src_content := regs(to_integer(unsigned(src)));

                    opcode_contd <= opcode;
                    dst_contd <= dst;
                    src_contd <= src;
                    
                    dst_content_contd <= dst_content;
                    src_content_contd <= src_content;
                    
                    case opcode is

                        -- ld (r): puts [src] into dst
                        when "000000" =>
                            MEM_ADDR <= src_content;
                            
                            state <= IDLE;
                            state_after_idle <= CONTD;
                            -- FALLTHROUGH CONTD

                        -- ld (i): puts [imm] in dst
                        when "000001" =>
                            MEM_ADDR <= ip + 1;

                            state_after_idle <= CONTD;
                            state <= IDLE;

                        -- st (r): store src into [dst]
                        when "000010" =>
                            MEM_ADDR <= dst_content;
                            MEM_IN <= src_content;
                            MEM_WE <= '1';
                        
                            ip <= ip + 1;
                            state <= IDLE;
                            state_after_idle <= FETCH;

                        -- st (i): store src into [imm]
                        when "000011" =>
                            MEM_ADDR <= ip + 1;

                            state <= IDLE;
                            state_after_idle <= CONTD;

                        -- mov: move src into dst
                        when "000100" =>
                            regs(to_integer(unsigned(dst))) <= src_content;

                            ip <= ip + 1;
                            state <= FETCH;

                        -- ldi: put imm into dst
                        when "000101" =>
                            MEM_ADDR <= ip + 1;

                            state <= IDLE;
                            state_after_idle <= CONTD;
                            -- FALLTHROUGH CONTD
                        
                        
                         -- xch: exchange dst and src
                        when "000110" =>
                            regs(to_integer(unsigned(src))) <= dst_content;
                            regs(to_integer(unsigned(dst))) <= src_content;

                            ip <= ip + 1;
                            state <= FETCH;
                        
                        -- add: puts dst+src into dst
                        when "000111" =>
                            alu_op_out := (dst_content(15) & dst_content) + (src_content(15) & src_content);

                            -- result
                            regs(to_integer(unsigned(dst))) <= alu_op_out(15 downto 0);

                            -- flags
                            if (alu_op_out(15 downto 0) = X"0000") then
                                regs(14)(0) <= '1';
                            else
                                regs(14)(0) <= '0';
                            end if;

                            regs(14)(1) <= alu_op_out(15);
                            regs(14)(2) <= alu_op_out(16);

                            if ((alu_op_out(15) = '1' and dst_content(15) = '0' and src_content(15) = '0')
                                    or
                                    (alu_op_out(15) = '0' and dst_content(15) = '1' and src_content(15) = '1')) then
                                regs(14)(3) <= '1';
                            else
                                regs(14)(3) <= '0';
                            end if;


                            ip <= ip + 1;
                            state <= FETCH;
                        
                        -- sub: put dst-src into dst
                        when "001000" =>
                            alu_minus := X"0000" - src_content;
                            alu_op_out := (dst_content(15) & dst_content) - (src_content(15) & src_content);

                            -- result
                            regs(to_integer(unsigned(dst))) <= alu_op_out(15 downto 0);

                            -- flags
                            if (alu_op_out(15 downto 0) = X"0000") then
                                regs(14)(0) <= '1';
                            else
                                regs(14)(0) <= '0';
                            end if;
                            regs(14)(1) <= alu_op_out(15);
                            regs(14)(2) <= alu_op_out(16);
                            
                            if ((alu_op_out(15) = '1' and dst_content(15) = '0' and alu_minus(15) = '0')
                                    or
                                    (alu_op_out(15) = '0' and dst_content(15) = '1' and alu_minus(15) = '1')) then
                                regs(14)(3) <= '1';
                            else
                                regs(14)(3) <= '0';
                            end if;

                            ip <= ip + 1;
                            state <= FETCH;
                      
                        -- cmp: compares dst and src
                        when "001001" =>
                            alu_minus := X"0000" - src_content;
                            alu_op_out := (dst_content(15) & dst_content) - (src_content(15) & src_content);

                            if (alu_op_out(15 downto 0) = "0000000000000000") then
                                regs(14)(0) <= '1';
                            else
                                regs(14)(0) <= '0';
                            end if;
                            regs(14)(1) <= alu_op_out(15);
                            regs(14)(2) <= alu_op_out(16);

                            if ((alu_op_out(15) = '1' and dst_content(15) = '0' and alu_minus(15) = '0')
                                    or
                                    (alu_op_out(15) = '0' and dst_content(15) = '1' and alu_minus(15) = '1')) then
                                regs(14)(3) <= '1';
                            else
                                regs(14)(3) <= '0';
                            end if;

                            ip <= ip + 1;
                            state <= FETCH;

                        -- inc: increment dst
                        when "001010" =>
                            alu_op_out := ('0' & dst_content) + X"0001";

                            -- result
                            regs(to_integer(unsigned(dst))) <= alu_op_out(15 downto 0);

                            -- flags
                            if (alu_op_out(15 downto 0) = X"0000") then
                                regs(14)(0) <= '1';
                            else
                                regs(14)(0) <= '0';
                            end if;

                            regs(14)(1) <= alu_op_out(15);
                            regs(14)(2) <= alu_op_out(16);

                            if ((alu_op_out(15) = '1' and dst_content(15) = '0' and src_content(15) = '0')
                                    or
                                    (alu_op_out(15) = '0' and dst_content(15) = '1' and src_content(15) = '1')) then
                                regs(14)(3) <= '1';
                            else
                                regs(14)(3) <= '0';
                            end if;


                            ip <= ip + 1;
                            state <= FETCH;
                        
                        -- dec: decrement dst
                        when "001011" =>
                            alu_minus := X"FFFF";
                            alu_op_out := ('0' & dst_content) + ('0' & alu_minus);

                            -- result
                            regs(to_integer(unsigned(dst))) <= alu_op_out(15 downto 0);

                            -- flags
                            if (alu_op_out(15 downto 0) = X"0000") then
                                regs(14)(0) <= '1';
                            else
                                regs(14)(0) <= '0';
                            end if;
                            regs(14)(1) <= alu_op_out(15);
                            regs(14)(2) <= alu_op_out(16);
                            
                            if ((alu_op_out(15) = '1' and dst_content(15) = '0' and alu_minus(15) = '0')
                                    or
                                    (alu_op_out(15) = '0' and dst_content(15) = '1' and alu_minus(15) = '1')) then
                                regs(14)(3) <= '1';
                            else
                                regs(14)(3) <= '0';
                            end if;

                            ip <= ip + 1;
                            state <= FETCH;

                        -- mul: put dst*src into d:dst
                        when "001100" =>
                            mult_tmp := dst_content*src_content;

                            regs(to_integer(unsigned(dst))) <= mult_tmp(15 downto 0);
                            regs(13) <= mult_tmp(31 downto 16);

                            -- Compute flags
                            if (mult_tmp = X"00000000") then
                                regs(14)(0) <= '1';
                            else
                                regs(14)(0) <= '0';
                            end if;

                            regs(14)(1) <= mult_tmp(31);

                            if (mult_tmp(31 downto 16) = X"0000") then
                                regs(14)(2) <= '0';
                            else
                                regs(14)(2) <= '1';
                            end if;

                            ip <= ip + 1;
                            state <= FETCH;

                        
                        -- xor: dst = dst xor b
                        when "001101" =>
                            tmp := dst_content xor src_content;
                            regs(to_integer(unsigned(dst))) <= tmp;

                            if (tmp = X"0000") then
                                regs(14)(0) <= '1';
                            else
                                regs(14)(0) <= '0';
                            end if;
                            regs(14)(1) <= tmp(15);
                            regs(14)(2) <= '0';

                            ip <= ip + 1;
                            state <= FETCH;
                        
                        -- and: dst = dst and src
                        when "001110" =>
                            tmp := dst_content and src_content;
                            regs(to_integer(unsigned(dst))) <= tmp;

                            if (tmp = X"0000") then
                                regs(14)(0) <= '1';
                            else
                                regs(14)(0) <= '0';
                            end if;
                            regs(14)(1) <= tmp(15);
                            regs(14)(2) <= '0';

                            ip <= ip + 1;
                            state <= FETCH;

                        -- or: dst = dst or src
                        when "001111" =>
                            tmp := dst_content or src_content;
                            regs(to_integer(unsigned(dst))) <= tmp;

                            if (tmp = X"0000") then
                                regs(14)(0) <= '1';
                            else
                                regs(14)(0) <= '0';
                            end if;
                            regs(14)(1) <= tmp(15);
                            regs(14)(2) <= '0';

                            ip <= ip + 1;
                            state <= FETCH;
                      
                        -- shl: shift left
                        when "010000" => 
                            regs(to_integer(unsigned(dst))) <= std_logic_vector(shift_left(unsigned(dst_content), to_integer(unsigned(src))));

                            ip <= ip + 1;
                            state <= FETCH;

                        -- shr: shift right
                        when "010001" =>
                            regs(to_integer(unsigned(dst))) <= std_logic_vector(shift_right(unsigned(dst_content), to_integer(unsigned(src))));

                            ip <= ip + 1;
                            state <= FETCH;

                        -- push (r): push dst
                        when "010010" =>
                            -- write dst_content into [rsp - 1]
                            MEM_ADDR <= regs(15) - 1;
                            MEM_IN <= dst_content;
                            MEM_WE <= '1';

                            -- decrement dst
                            regs(15) <= regs(15) - 1;

                            ip <= ip + 1;
                            state_after_idle <= FETCH;
                            state <= IDLE;

                        -- push (i): push imm
                        when "010011" =>
                            MEM_ADDR <= ip + 1;
                            regs(15) <= regs(15) - 1;

                            state_after_idle <= CONTD;
                            state <= IDLE;

                        -- pop: pop to dst
                        when "010100" =>
                            MEM_ADDR <= regs(15);

                            regs(15) <= regs(15) + 1;
                            
                            state_after_idle <= CONTD;
                            state <= IDLE;

                        -- jmp: jump to dst
                        when "010110" | "010111" =>
                            case src(3 downto 0) is
                                -- bit 0: 0 indicates equality
                                -- bit 1: 0 indicates >
                                -- bit 2: 0 indicates <
                                -- bit 3: 0 indicates unsignedness (no regard on sign)

                                -- unconditional
                                when "0000" =>
                                    jmp_cond_ok := '1';
                                -- ==
                                when "0110" =>
                                    jmp_cond_ok := regs(14)(0);
                                -- !=
                                when "0001" =>
                                    jmp_cond_ok := not regs(14)(0);
                                -- >
                                when "1101" =>
                                    jmp_cond_ok := not (regs(14)(1) xor regs(14)(3)) and not regs(14)(0);
                                -- >=
                                when "1100" =>
                                    jmp_cond_ok := not (regs(14)(1) xor regs(14)(3));
                                -- <
                                when "1011" =>
                                    jmp_cond_ok := regs(14)(1) xor regs(14)(3);
                                -- <=
                                when "1010" =>
                                    jmp_cond_ok := (regs(14)(1) xor regs(14)(3)) or regs(14)(0);
                                -- above
                                when "0101" =>
                                    jmp_cond_ok := not regs(14)(2) and not regs(14)(0);
                                -- above or equal
                                when "0100" =>
                                    jmp_cond_ok := not regs(14)(2);
                                -- below / carry set
                                when "0011" =>
                                    jmp_cond_ok := regs(14)(2);
                                -- below or equal
                                when "0010" =>
                                    jmp_cond_ok := regs(14)(2) or regs(14)(0);
                                when others =>
                                    jmp_cond_ok := '0';
                            end case;


                            if (jmp_cond_ok = '1') then
                                case (opcode) is
                                    when "010110" =>
                                        ip <= dst_content;
                                        state <= FETCH;
                                    when others =>
                                        MEM_ADDR <= ip + 1;
                                        state_after_idle <= CONTD;
                                        state <= IDLE;
                                end case;
                            else
                                case (opcode) is
                                    when "010110" =>
                                        ip <= ip + 1;
                                    when others =>
                                        ip <= ip + 2;
                                end case;
                                state <= FETCH;
                            end if;
                            
                            -- END jmp

                        -- call: puts ip + 1 on the stack, jumps to location
                        when "011000" | "011001" =>
                            MEM_ADDR <= regs(15) - 1;
                            MEM_WE <= '1';

                            regs(15) <= regs(15) - 1;

                            case (opcode) is
                                when "011000" =>
                                    MEM_IN <= ip + 1;

                                    ip <= dst_content;
                                    state_after_idle <= FETCH;
                                when others => 
                                    MEM_IN <= ip + 2;

                                    state_after_idle <= CONTD;
                            end case;

                            state <= IDLE;

                        -- ret: return using IP from stack
                        when "011010" =>
                            MEM_ADDR <= regs(15);

                            regs(15) <= regs(15) + 1;
                            
                            state_after_idle <= CONTD;
                            state <= IDLE;

                        -- hlt: halt
                        when "011011" =>
                            state <= FETCH;

                    when others => null; -- to compile
                    end case;

                when CONTD =>
                    -- restore the variable
                    opcode := opcode_contd;
                    dst := dst_contd;
                    src := src_contd;
                    dst_content := dst_content_contd;
                    src_content := src_content_contd;

                    case opcode is
                        -- ld (r): load [src] into dst
                        when "000000" =>
                            regs(to_integer(unsigned(dst))) <= MEM_OUT;

                            ip <= ip + 1;
                            state <= FETCH;

                        -- ld (i): puts [imm] in dst
                        when "000001" =>
                            MEM_ADDR <= MEM_OUT;

                            state_after_idle <= CONTD2;
                            state <= IDLE;

                        -- st (i): stores src into [imm]
                        when "000011" =>
                            MEM_ADDR <= MEM_OUT;
                            MEM_IN <= src_content;
                            MEM_WE <= '1';

                            ip <= ip + 2;
                            state_after_idle <= FETCH;
                            state <= IDLE;

                        -- ldi: put imm into dst
                        when "000101" =>
                            regs(to_integer(unsigned(dst))) <= MEM_OUT;

                            ip <= ip + 2;
                            state <= FETCH;
                        
                        -- psi: push immediate
                        when "010011" =>
                            MEM_ADDR <= regs(15);
                            MEM_IN <= MEM_OUT;
                            MEM_WE <= '1';

                            ip <= ip + 2;
                            state_after_idle <= FETCH;
                            state <= IDLE;

                        -- pop: pop to dst
                        when "010100" =>
                            regs(to_integer(unsigned(dst))) <= MEM_OUT;

                            ip <= ip + 1;
                            state <= FETCH;
                     
                        -- jmp: contd for immediate
                        when "010111" =>
                            ip <= MEM_OUT;
                            state <= FETCH;               

                        -- call: puts ip + 1 on the stack, jumps to location
                        when "011001" =>
                            -- if here, immediate value jump
                            MEM_ADDR <= ip + 1;
                            MEM_WE <= '0';

                            state_after_idle <= CONTD2;
                            state <= IDLE;

                        -- ret: return using IP from the stack
                        when "011010" =>
                            ip <= MEM_OUT;
                            state <= FETCH;

                        when others => null; -- to compile
                    end case;
	
                when CONTD2 =>
                    opcode := opcode_contd;
                    dst := dst_contd;
                    dst_content := dst_content_contd;

                    case opcode is
                        -- ld (i): puts [imm] in dst
                        when "000001" =>
                            regs(to_integer(unsigned(dst))) <= MEM_OUT;

                            ip <= ip + 2;
                            state <= FETCH;

                        -- call: puts ip + 1 on the stack, jumps to location
                        when "011001" =>
                            -- if here, immediate value jump
                            ip <= MEM_OUT;
                            state <= FETCH;

                        when others => null;
                    end case;
            end case;
        end if;
    end process;
end architecture; -- mannerisms




