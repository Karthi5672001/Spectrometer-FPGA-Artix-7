library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.protocol_types.all;

entity tb_command_decoder is
end tb_command_decoder;

architecture sim of tb_command_decoder is
    constant CLK_PERIOD : time := 100 ns;
    signal clk   : std_logic := '0';
    signal reset : std_logic := '1';
    signal b     : std_logic_vector(7 downto 0) := (others => '0');
    signal bv    : std_logic := '0';
    signal cmd   : command_type;
    signal seen  : std_logic := '0';
    signal seen_id   : std_logic_vector(15 downto 0) := (others => '0');
    signal seen_data : std_logic_vector(31 downto 0) := (others => '0');
begin
    clk <= not clk after CLK_PERIOD / 2;

    DUT : entity work.command_decoder
        generic map (TIMEOUT_CYCLES => 100)
        port map (clock => clk, reset => reset, byte_in => b, byte_valid => bv, command_out => cmd);

    MONITOR : process(clk)
    begin
        if rising_edge(clk) then
            if cmd.valid = '1' then
                seen <= '1';
                seen_id <= cmd.command_id;
                seen_data <= cmd.data;
            end if;
        end if;
    end process;

    STIMULUS : process
        procedure send_byte(constant value : in std_logic_vector(7 downto 0)) is
        begin
            wait until falling_edge(clk);
            b <= value;
            bv <= '1';
            wait until falling_edge(clk);
            bv <= '0';
        end procedure;
    begin
        wait for 300 ns;
        reset <= '0';
        send_byte(x"EF"); send_byte(x"00"); send_byte(x"10"); send_byte(x"00");
        send_byte(x"00"); send_byte(x"00"); send_byte(x"00"); send_byte(x"C8");
        wait for 300 ns;
        assert seen = '1' report "command not decoded" severity failure;
        assert seen_id = x"1000" report "command ID mismatch" severity failure;
        assert seen_data = x"000000C8" report "command data mismatch" severity failure;
        report "tb_command_decoder PASSED" severity note;
        wait;
    end process;
end sim;
