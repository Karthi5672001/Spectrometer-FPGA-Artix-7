library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.hardware_config.all;
use work.protocol_config.all;
use work.crc16_pkg.all;

entity tb_frame_transmitter is
end tb_frame_transmitter;

architecture sim of tb_frame_transmitter is
    constant CLK_PERIOD : time := 16.666 ns;
    constant FRAME_BYTES : natural := 22 + PIXEL_COUNT * 2 + 2;
    type byte_array_type is array (0 to FRAME_BYTES-1) of std_logic_vector(7 downto 0);
    type ram_type is array (0 to 511) of std_logic_vector(15 downto 0);
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal start : std_logic := '0';
    signal integration_counts : unsigned(31 downto 0) := to_unsigned(1000, 32);
    signal command_count : unsigned(31 downto 0) := to_unsigned(7, 32);
    signal busy, done_pulse : std_logic;
    signal ram_addr : std_logic_vector(8 downto 0);
    signal ram_data : std_logic_vector(15 downto 0) := (others => '0');
    signal tx_data : std_logic_vector(7 downto 0);
    signal tx_valid : std_logic;
    signal tx_ready : std_logic := '1';
    signal memory : ram_type := (others => (others => '0'));
    signal captured : byte_array_type := (others => (others => '0'));
    signal byte_count : natural range 0 to FRAME_BYTES := 0;
begin
    clk <= not clk after CLK_PERIOD / 2;

    DUT : entity work.frame_transmitter
        port map (
            clock => clk, reset => reset, start => start,
            integration_counts => integration_counts, command_count => command_count,
            busy => busy, done_pulse => done_pulse,
            ram_addr => ram_addr, ram_data => ram_data,
            tx_data => tx_data, tx_valid => tx_valid, tx_ready => tx_ready
        );

    RAM_MODEL : process(clk)
    begin
        if rising_edge(clk) then
            ram_data <= memory(to_integer(unsigned(ram_addr)));
        end if;
    end process;

    BYTE_MONITOR : process(clk)
    begin
        if rising_edge(clk) then
            if tx_valid = '1' then
                assert byte_count < FRAME_BYTES report "too many frame bytes" severity failure;
                captured(byte_count) <= tx_data;
                byte_count <= byte_count + 1;
            end if;
        end if;
    end process;

    STIMULUS : process
        variable expected_crc : unsigned(15 downto 0);
        variable done_seen : boolean := false;
    begin
        for i in 0 to PIXEL_COUNT-1 loop
            memory(i) <= std_logic_vector(to_unsigned(i, 16));
        end loop;
        wait for 200 ns;
        wait until falling_edge(clk); reset <= '0';
        wait until falling_edge(clk); start <= '1';
        wait until falling_edge(clk); start <= '0';

        for i in 0 to 10000 loop
            wait until rising_edge(clk);
            if done_pulse = '1' then done_seen := true; exit; end if;
        end loop;
        assert done_seen report "frame transmitter timed out" severity failure;
        wait until rising_edge(clk); wait for 1 ns;
        assert byte_count = FRAME_BYTES report "incorrect frame byte count" severity failure;
        assert captured(0)=SYNC_0 and captured(1)=SYNC_1 and captured(2)=SYNC_2 and captured(3)=SYNC_3 report "sync marker mismatch" severity failure;
        assert captured(4)=PROTOCOL_VERSION report "protocol version mismatch" severity failure;
        assert captured(6)=x"02" and captured(7)=x"54" report "remaining length is not 596 (0x0254)" severity failure;
        assert captured(8)=x"00" and captured(9)=x"00" and captured(10)=x"00" and captured(11)=x"00" report "initial frame sequence mismatch" severity failure;
        assert captured(12)=x"00" and captured(13)=x"00" and captured(14)=x"03" and captured(15)=x"E8" report "integration metadata mismatch" severity failure;
        assert captured(16)=x"00" and captured(17)=x"00" and captured(18)=x"00" and captured(19)=x"07" report "command count metadata mismatch" severity failure;
        assert captured(20)=x"01" and captured(21)=x"20" report "pixel count mismatch" severity failure;
        assert captured(22)=x"00" and captured(23)=x"00" report "pixel 0 mismatch" severity failure;
        assert captured(24)=x"00" and captured(25)=x"01" report "pixel 1 mismatch" severity failure;
        assert captured(FRAME_BYTES-4)=x"01" and captured(FRAME_BYTES-3)=x"1F" report "pixel 287 mismatch" severity failure;

        expected_crc := CRC16_INITIAL;
        for i in 4 to FRAME_BYTES-3 loop
            expected_crc := crc16_next(expected_crc, captured(i));
        end loop;
        assert captured(FRAME_BYTES-2)=std_logic_vector(expected_crc(15 downto 8)) report "CRC high byte mismatch" severity failure;
        assert captured(FRAME_BYTES-1)=std_logic_vector(expected_crc(7 downto 0)) report "CRC low byte mismatch" severity failure;
        report "tb_frame_transmitter PASSED" severity note;
        wait;
    end process;
end sim;
