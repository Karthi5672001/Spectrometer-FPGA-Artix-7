library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_uart_loopback is
end tb_uart_loopback;

architecture sim of tb_uart_loopback is
    constant CLK_PERIOD : time := 10 ns;
    constant CLKS_PER_BIT_TB : positive := 10;
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal tx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_valid, tx_ready, serial_line : std_logic := '0';
    signal rx_data : std_logic_vector(7 downto 0);
    signal rx_valid, framing_error : std_logic;
begin
    clk <= not clk after CLK_PERIOD / 2;

    TX_DUT : entity work.uart_tx
        generic map (CLKS_PER_BIT => CLKS_PER_BIT_TB)
        port map (clock => clk, reset => reset, data => tx_data, valid => tx_valid, ready => tx_ready, tx => serial_line);

    RX_DUT : entity work.uart_rx
        generic map (CLKS_PER_BIT => CLKS_PER_BIT_TB)
        port map (clock => clk, reset => reset, rx => serial_line, data => rx_data, valid => rx_valid, framing_error => framing_error);

    STIMULUS : process
        procedure send_and_check(constant value : in std_logic_vector(7 downto 0)) is
            variable received : boolean := false;
        begin
            while tx_ready /= '1' loop wait until rising_edge(clk); end loop;
            wait until falling_edge(clk);
            tx_data <= value;
            tx_valid <= '1';
            wait until falling_edge(clk);
            tx_valid <= '0';
            for i in 0 to 200 loop
                wait until rising_edge(clk);
                if rx_valid = '1' then
                    received := true;
                    assert rx_data = value report "UART loopback data mismatch" severity failure;
                    exit;
                end if;
            end loop;
            assert received report "UART loopback timed out" severity failure;
            assert framing_error = '0' report "UART framing error" severity failure;
        end procedure;
    begin
        wait for 100 ns;
        wait until falling_edge(clk); reset <= '0';
        send_and_check(x"00");
        send_and_check(x"55");
        send_and_check(x"A5");
        send_and_check(x"FF");
        report "tb_uart_loopback PASSED" severity note;
        wait;
    end process;
end sim;
