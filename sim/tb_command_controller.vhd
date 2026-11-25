library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.hardware_config.all;
use work.protocol_types.all;

entity tb_command_controller is
end tb_command_controller;

architecture sim of tb_command_controller is
    constant CLK_PERIOD : time := 100 ns;
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal command_in : command_type := COMMAND_IDLE;
    signal run_enable, single_request, command_pulse : std_logic;
    signal integration_counts, accepted_count : unsigned(31 downto 0);
    signal test_mode : std_logic_vector(1 downto 0);
begin
    clk <= not clk after CLK_PERIOD / 2;

    DUT : entity work.command_controller
        port map (
            clock => clk, reset => reset, command_in => command_in,
            run_enable => run_enable, single_request => single_request,
            integration_counts => integration_counts, test_mode => test_mode,
            accepted_count => accepted_count, command_pulse => command_pulse
        );

    STIMULUS : process
        procedure issue_command(
            constant command_id_value : in std_logic_vector(15 downto 0);
            constant data_value : in std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(clk);
            command_in.command_id <= command_id_value;
            command_in.data <= data_value;
            command_in.valid <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            assert command_pulse = '1' report "accepted command did not generate command_pulse" severity failure;
            wait until falling_edge(clk);
            command_in.valid <= '0';
        end procedure;
    begin
        wait for 250 ns;
        wait until falling_edge(clk);
        reset <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;

        assert run_enable = '0' report "acquisition enabled after reset" severity failure;
        assert integration_counts = to_unsigned(1000, 32) report "200 us default is not 1000 counts" severity failure;
        assert accepted_count = to_unsigned(0, 32) report "accepted count not reset" severity failure;

        issue_command(x"1000", x"000000C8");
        assert run_enable = '1' report "0x1000 did not enable acquisition" severity failure;
        assert integration_counts = to_unsigned(1000, 32) report "200 us command did not produce 1000 counts" severity failure;
        assert accepted_count = to_unsigned(1, 32) report "accepted count mismatch after integration command" severity failure;

        issue_command(x"4000", x"00000000");
        assert run_enable = '0' report "stop command did not stop acquisition" severity failure;
        assert accepted_count = to_unsigned(2, 32) report "accepted count mismatch after stop" severity failure;

        issue_command(x"4000", x"00000001");
        assert run_enable = '1' report "resume command did not resume acquisition" severity failure;
        assert accepted_count = to_unsigned(3, 32) report "accepted count mismatch after resume" severity failure;

        issue_command(x"4001", x"00000000");
        assert single_request = '1' report "single-frame request pulse missing" severity failure;
        wait until rising_edge(clk); wait for 1 ns;
        assert single_request = '0' report "single-frame request was not one clock" severity failure;

        issue_command(x"5000", x"00000002");
        assert test_mode = "10" report "test mode selection mismatch" severity failure;

        wait until falling_edge(clk);
        command_in.command_id <= x"9999";
        command_in.data <= (others => '0');
        command_in.valid <= '1';
        wait until rising_edge(clk); wait for 1 ns;
        assert command_pulse = '0' report "unsupported command was accepted" severity failure;
        assert accepted_count = to_unsigned(5, 32) report "unsupported command changed count" severity failure;
        wait until falling_edge(clk); command_in.valid <= '0';

        report "tb_command_controller PASSED" severity note;
        wait;
    end process;
end sim;
