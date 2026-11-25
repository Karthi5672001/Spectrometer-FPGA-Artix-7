library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.hardware_config.all;

entity tb_detector_capture is
end tb_detector_capture;

architecture sim of tb_detector_capture is
    constant SYS_PERIOD : time := 100 ns;
    constant DATA_PERIOD : time := 200 ns;
    signal sys_clock : std_logic := '0';
    signal data_clock : std_logic := '0';
    signal sys_reset : std_logic := '1';
    signal start : std_logic := '0';
    signal integration_counts : unsigned(31 downto 0) := to_unsigned(5, 32);
    signal adc_data : std_logic_vector(11 downto 0) := (others => '0');
    signal test_mode : std_logic_vector(1 downto 0) := "01";
    signal dev_clock, dev_start, adc_clock, busy, done_pulse, ram_we : std_logic;
    signal ram_addr : std_logic_vector(8 downto 0);
    signal ram_data : std_logic_vector(15 downto 0);
    signal write_count : natural := 0;
begin
    sys_clock <= not sys_clock after SYS_PERIOD / 2;
    data_clock <= not data_clock after DATA_PERIOD / 2;

    DUT : entity work.detector_capture
        port map (
            sys_clock => sys_clock, sys_reset => sys_reset, start => start,
            integration_counts => integration_counts, data_clock => data_clock,
            adc_data => adc_data, test_mode => test_mode,
            dev_clock => dev_clock, dev_start => dev_start, adc_clock => adc_clock,
            busy => busy, done_pulse => done_pulse,
            ram_we => ram_we, ram_addr => ram_addr, ram_data => ram_data
        );

    WRITE_MONITOR : process(data_clock)
    begin
        if rising_edge(data_clock) then
            if ram_we = '1' then
                assert to_integer(unsigned(ram_addr)) = write_count report "RAM address sequence mismatch" severity failure;
                assert to_integer(unsigned(ram_data)) = write_count report "ramp test data mismatch" severity failure;
                write_count <= write_count + 1;
            end if;
        end if;
    end process;

    STIMULUS : process
        variable done_seen : boolean := false;
    begin
        wait for 500 ns;
        wait until falling_edge(sys_clock); sys_reset <= '0';
        wait until falling_edge(sys_clock); start <= '1';
        wait until falling_edge(sys_clock); start <= '0';

        for i in 0 to 2000 loop
            wait until rising_edge(sys_clock);
            if done_pulse = '1' then done_seen := true; exit; end if;
        end loop;

        assert done_seen report "detector capture completion timed out" severity failure;
        wait for DATA_PERIOD * 2;
        assert write_count = PIXEL_COUNT report "capture did not write exactly 288 pixels" severity failure;
        assert busy = '0' report "capture remained busy after completion" severity failure;
        assert adc_clock = data_clock report "ADC clock is not routed from data clock" severity failure;
        report "tb_detector_capture PASSED" severity note;
        wait;
    end process;
end sim;
