library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.env.all;

use work.defs.all;

entity tb_binary_pixel_sequence is
end tb_binary_pixel_sequence;

architecture Simulation of tb_binary_pixel_sequence is

    constant CLOCK_PERIOD : time := 16.666667 ns;

    constant UART_CLOCKS_PER_BIT : positive := 60;

    constant UART_BIT_PERIOD :
        time := CLOCK_PERIOD * UART_CLOCKS_PER_BIT;

    signal clock : std_logic := '0';
    signal reset : std_logic := '1';

    signal trigger : std_logic := '0';

    signal integrationTime :
        natural := 2500;

    signal txByte  : std_logic_vector(7 downto 0);
    signal txValid : std_logic;
    signal txWait  : std_logic;

    signal readoutDone :
        std_logic;

    signal ramAddress :
        std_logic_vector(8 downto 0);

    signal ramData :
        std_logic_vector(15 downto 0) :=
        (others => '0');

    signal uartReady :
        std_logic;

    signal uartTx :
        std_logic;

    signal receivedByteCount :
        natural := 0;

    type pixel_array_t is
        array (0 to DATA_LEN - 1) of natural;

    signal receivedPixels :
        pixel_array_t :=
        (others => 0);

begin

    ------------------------------------------------------------------
    -- 60 MHz clock
    ------------------------------------------------------------------

    clock <= not clock after CLOCK_PERIOD / 2;

    ------------------------------------------------------------------
    -- DUT
    ------------------------------------------------------------------

    BINARY_READOUT_DUT : binaryReadout
        port map
        (
            clock           => clock,
            reset           => reset,
            trig            => trigger,
            integrationTime => integrationTime,

            txByte  => txByte,
            txValid => txValid,
            txWait  => txWait,

            done => readoutDone,
            addr => ramAddress,
            data => ramData
        );

    FAST_SERIAL_TX_DUT : fastSerialTx
        generic map
        (
            CLOCKS_PER_BIT => UART_CLOCKS_PER_BIT,
            STOP_BITS      => 1
        )
        port map
        (
            clock => clock,
            reset => reset,

            data  => txByte,
            valid => txValid,

            ready => uartReady,
            tx    => uartTx
        );

    txWait <= (not uartReady) or txValid;

    ------------------------------------------------------------------
    -- Synthetic RAM
    ------------------------------------------------------------------

    RAM_MODEL : process(clock)
    begin

        if rising_edge(clock) then

            ramData <=
                std_logic_vector
                (
                    resize
                    (
                        unsigned(ramAddress),
                        16
                    )
                );

        end if;

    end process;

    ------------------------------------------------------------------
    -- Stimulus
    ------------------------------------------------------------------

    STIMULUS : process
    begin

        reset <= '1';

        wait for 20 * CLOCK_PERIOD;

        wait until rising_edge(clock);

        reset <= '0';

        wait for 10 * CLOCK_PERIOD;

        wait until rising_edge(clock);

        trigger <= '1';

        wait until rising_edge(clock);

        trigger <= '0';

        wait until readoutDone = '0';

        wait until readoutDone = '1';

        wait for 20 * UART_BIT_PERIOD;

        assert receivedByteCount =
               BINARY_FRAME_BYTES
            report
                "Expected "
                & integer'image(BINARY_FRAME_BYTES)
                & " bytes but received "
                & integer'image(receivedByteCount)
            severity failure;

        for i in 0 to DATA_LEN - 1 loop

            assert receivedPixels(i) = i
                report
                    "Pixel sequence error at pixel "
                    & integer'image(i)
                    & ". Expected "
                    & integer'image(i)
                    & ", received "
                    & integer'image(receivedPixels(i))
                severity failure;

        end loop;

        report
            "PASS - Verified all "
            & integer'image(DATA_LEN)
            & " pixels."
            severity note;

        stop;

        wait;

    end process;

    ------------------------------------------------------------------
    -- UART monitor
    ------------------------------------------------------------------

    UART_MONITOR : process

        variable decodedByte :
            std_logic_vector(7 downto 0);

        variable byteIndex :
            natural := 0;

        variable pixelIndex :
            natural := 0;

        variable pixelHigh :
            natural := 0;

        variable pixelLow :
            natural := 0;

    begin

        wait until reset = '0';

        loop

            wait until falling_edge(uartTx);

            wait for UART_BIT_PERIOD +
                     (UART_BIT_PERIOD / 2);

            for bitIndex in 0 to 7 loop

                decodedByte(bitIndex) :=
                    uartTx;

                wait for UART_BIT_PERIOD;

            end loop;

            assert uartTx = '1'
                report "UART stop-bit error"
                severity failure;

            ---------------------------------------------------------
            -- Pixel data starts at byte 18
            ---------------------------------------------------------

            if byteIndex >= 18 and
               byteIndex < (18 + DATA_LEN * 2)
            then

                pixelIndex :=
                    (byteIndex - 18) / 2;

                if ((byteIndex - 18) mod 2) = 0
                then

                    pixelHigh :=
                        to_integer
                        (
                            unsigned(decodedByte)
                        );

                else

                    pixelLow :=
                        to_integer
                        (
                            unsigned(decodedByte)
                        );

                    receivedPixels(pixelIndex)
                        <=
                        (pixelHigh * 256)
                        + pixelLow;

                end if;

            end if;

            byteIndex := byteIndex + 1;

            receivedByteCount <= byteIndex;

        end loop;

    end process;

end Simulation;