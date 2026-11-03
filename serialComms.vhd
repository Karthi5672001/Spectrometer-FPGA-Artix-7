library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.defs.all;


entity serialComms is
    port (
        clock:    in  std_logic;
        reset:    in  std_logic;
        txSerial: out std_logic;
        rxSerial: in  std_logic;
        txData:   in  std_logic_vector(7 downto 0);
        txValid:  in  std_logic;
        txWait:   out std_logic;
        rxCmd:    out cmd_type
    );
end serialComms;


architecture Behavioral of serialComms is

signal txReady:      std_logic;
signal readEnable:   std_logic := '0';
signal empty:        std_logic;

signal fifoDataOut:  std_logic_vector(7 downto 0);
signal fifoValidOut: std_logic := '0';

signal rxData:       std_logic_vector(7 downto 0);
signal rxValid:      std_logic;

begin


RX_CMD: rxCommand
    port map (
        clock     => clock,
        din       => rxData,
        din_valid => rxValid,
        cmd       => rxCmd
    );


UART_CTRL: process(clock)
    variable state: natural range 0 to 4 := 0;
begin
    if rising_edge(clock) then
        if reset = '1' then
            state        := 0;
            readEnable   <= '0';
            fifoValidOut <= '0';

        else
            -- fifoValidOut is asserted one cycle after readEnable.
            fifoValidOut <= readEnable;

            case state is
                when 0 =>
                    readEnable <= '0';
                    state := 1;

                when 1 =>
                    readEnable <= '0';

                    if empty = '0' then
                        state := 2;
                    end if;

                when 2 =>
                    if txReady = '1' then
                        state := 3;
                    end if;

                when 3 =>
                    readEnable <= '1';
                    state := 4;

                when 4 =>
                    readEnable <= '0';
                    state := 1;

                when others =>
                    state := 0;
                    readEnable <= '0';
            end case;
        end if;
    end if;
end process;


COMMS: uart
    generic map (
        data_len  => 8,
        stop_bits => 1,
        clk_div   => SERIAL_CLK_DIV
    )
    port map (
        clock   => clock,
        reset   => reset,
        txData  => fifoDataOut,
        txValid => fifoValidOut,
        txReady => txReady,
        txOut   => txSerial,
        rxData  => rxData,
        rxValid => rxValid,
        rxError => open,
        rxIn    => rxSerial
    );


TX_FIFO: serialTxFifo
    port map (
        clk       => clock,
        srst      => reset,
        din       => txData,
        wr_en     => txValid,
        rd_en     => readEnable,
        dout      => fifoDataOut,
        full      => open,
        empty     => empty,
        prog_full => txWait
    );


end Behavioral;