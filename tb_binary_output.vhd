library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.env.all;

use work.defs.all;


entity tb_binary_output is
end tb_binary_output;


architecture Simulation of tb_binary_output is

    ---------------------------------------------------------------------------
    -- Simulation clock
    ---------------------------------------------------------------------------

    constant CLOCK_PERIOD :
        time := 16.666667 ns;

    constant UART_CLOCKS_PER_BIT :
        positive := 60;

    constant UART_BIT_PERIOD :
        time := CLOCK_PERIOD * UART_CLOCKS_PER_BIT;


    ---------------------------------------------------------------------------
    -- Clock and reset
    ---------------------------------------------------------------------------

    signal clock :
        std_logic := '0';

    signal reset :
        std_logic := '1';


    ---------------------------------------------------------------------------
    -- Binary-readout signals
    ---------------------------------------------------------------------------

    signal trigger :
        std_logic := '0';

    signal integrationTime :
        natural := 2500;

    signal txByte :
        std_logic_vector(7 downto 0);

    signal txValid :
        std_logic;

    signal txWait :
        std_logic;

    signal readoutDone :
        std_logic;

    signal ramAddress :
        std_logic_vector(8 downto 0);

    signal ramData :
        std_logic_vector(15 downto 0) := (others => '0');


    ---------------------------------------------------------------------------
    -- UART transmitter signals
    ---------------------------------------------------------------------------

    signal uartReady :
        std_logic;

    signal uartTx :
        std_logic;


    ---------------------------------------------------------------------------
    -- UART monitor
    ---------------------------------------------------------------------------

    signal receivedByteCount :
        natural := 0;

    signal firstByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal secondByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal thirdByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal fourthByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal versionByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal statusByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal lengthHighByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal lengthLowByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal pixelCountHighByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal pixelCountLowByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal firstPixelHighByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal firstPixelLowByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal secondPixelHighByte :
        std_logic_vector(7 downto 0) := (others => '0');

    signal secondPixelLowByte :
        std_logic_vector(7 downto 0) := (others => '0');


begin

    ---------------------------------------------------------------------------
    -- 60 MHz clock
    ---------------------------------------------------------------------------

    clock <= not clock after CLOCK_PERIOD / 2;


    ---------------------------------------------------------------------------
    -- Device under test: binary frame generator
    ---------------------------------------------------------------------------

    BINARY_READOUT_DUT: binaryReadout
        port map (
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


    ---------------------------------------------------------------------------
    -- Device under test: high-speed UART transmitter
    ---------------------------------------------------------------------------

    FAST_SERIAL_TX_DUT: fastSerialTx
        generic map (
            CLOCKS_PER_BIT => UART_CLOCKS_PER_BIT,
            STOP_BITS      => 1
        )
        port map (
            clock => clock,
            reset => reset,

            data  => txByte,
            valid => txValid,

            ready => uartReady,
            tx    => uartTx
        );


    ---------------------------------------------------------------------------
    -- Flow control
    ---------------------------------------------------------------------------

    txWait <= (not uartReady) or txValid;


    ---------------------------------------------------------------------------
    -- Synthetic synchronous RAM model
    --
    -- RAM address N returns the value N:
    --
    -- Address 0   -> 0x0000
    -- Address 1   -> 0x0001
    -- Address 2   -> 0x0002
    -- ...
    -- Address 287 -> 0x011F
    --
    -- This model has one clock of synchronous read latency.
    ---------------------------------------------------------------------------

    RAM_MODEL: process(clock)
    begin
        if rising_edge(clock) then
            ramData <=
                std_logic_vector(
                    resize(
                        unsigned(ramAddress),
                        ramData'length
                    )
                );
        end if;
    end process;


    ---------------------------------------------------------------------------
    -- Test stimulus
    ---------------------------------------------------------------------------

    STIMULUS: process
    begin

        -----------------------------------------------------------------------
        -- Hold reset for several clock cycles
        -----------------------------------------------------------------------

        reset <= '1';
        trigger <= '0';

        wait for 20 * CLOCK_PERIOD;

        wait until rising_edge(clock);
        reset <= '0';


        -----------------------------------------------------------------------
        -- Allow initialization to settle
        -----------------------------------------------------------------------

        wait for 10 * CLOCK_PERIOD;


        -----------------------------------------------------------------------
        -- Start one binary frame
        -----------------------------------------------------------------------

        wait until rising_edge(clock);
        trigger <= '1';

        wait until rising_edge(clock);
        trigger <= '0';


        -----------------------------------------------------------------------
        -- Confirm the reader leaves the idle state
        -----------------------------------------------------------------------

        wait until readoutDone = '0';


        -----------------------------------------------------------------------
        -- Wait for the reader to complete
        -----------------------------------------------------------------------

        wait until readoutDone = '1';


        -----------------------------------------------------------------------
        -- Let the UART monitor receive the final stop bit
        -----------------------------------------------------------------------

        wait for 20 * UART_BIT_PERIOD;


        -----------------------------------------------------------------------
        -- Frame-length check
        -----------------------------------------------------------------------

        assert receivedByteCount = BINARY_FRAME_BYTES
            report
                "Incorrect frame length. Expected " &
                integer'image(BINARY_FRAME_BYTES) &
                " bytes, received " &
                integer'image(receivedByteCount)
            severity failure;


        -----------------------------------------------------------------------
        -- Header checks
        -----------------------------------------------------------------------

        assert firstByte = BINARY_SYNC_0
            report "Incorrect synchronization byte 0"
            severity failure;

        assert secondByte = BINARY_SYNC_1
            report "Incorrect synchronization byte 1"
            severity failure;

        assert thirdByte = BINARY_SYNC_2
            report "Incorrect synchronization byte 2"
            severity failure;

        assert fourthByte = BINARY_SYNC_3
            report "Incorrect synchronization byte 3"
            severity failure;

        assert versionByte = BINARY_PROTOCOL_VERSION
            report "Incorrect protocol-version byte"
            severity failure;

        assert statusByte = BINARY_STATUS_OK
            report "Incorrect status byte"
            severity failure;

        assert lengthHighByte = x"02"
            report "Incorrect remaining-length high byte"
            severity failure;

        assert lengthLowByte = x"50"
            report "Incorrect remaining-length low byte"
            severity failure;


        -----------------------------------------------------------------------
        -- Pixel-count checks
        -----------------------------------------------------------------------

        assert pixelCountHighByte = x"01"
            report "Incorrect pixel-count high byte"
            severity failure;

        assert pixelCountLowByte = x"20"
            report "Incorrect pixel-count low byte"
            severity failure;


        -----------------------------------------------------------------------
        -- First pixels from the synthetic RAM
        -----------------------------------------------------------------------

        assert firstPixelHighByte = x"00"
            report "Incorrect first-pixel high byte"
            severity failure;

        assert firstPixelLowByte = x"00"
            report "Incorrect first-pixel low byte"
            severity failure;

        assert secondPixelHighByte = x"00"
            report "Incorrect second-pixel high byte"
            severity failure;

        assert secondPixelLowByte = x"01"
            report "Incorrect second-pixel low byte"
            severity failure;


        report
            "Binary output simulation passed. Received " &
            integer'image(receivedByteCount) &
            " bytes."
            severity note;

        stop;
        wait;
    end process;


    ---------------------------------------------------------------------------
    -- UART receiver/decoder used only by the testbench
    --
    -- The decoder waits for a falling start-bit edge, samples in the middle of
    -- each data bit, and reconstructs bytes least-significant bit first.
    ---------------------------------------------------------------------------

    UART_MONITOR: process

        variable decodedByte :
            std_logic_vector(7 downto 0);

        variable byteIndex :
            natural := 0;

    begin
        wait until reset = '0';

        loop

            -------------------------------------------------------------------
            -- Detect start bit
            -------------------------------------------------------------------

            wait until falling_edge(uartTx);


            -------------------------------------------------------------------
            -- Move to the middle of data bit zero:
            --
            -- 1 complete start bit + half a data bit
            -------------------------------------------------------------------

            wait for UART_BIT_PERIOD +
                     (UART_BIT_PERIOD / 2);


            -------------------------------------------------------------------
            -- Sample eight data bits, least-significant bit first
            -------------------------------------------------------------------

            for bitIndex in 0 to 7 loop
                decodedByte(bitIndex) := uartTx;
                wait for UART_BIT_PERIOD;
            end loop;


            -------------------------------------------------------------------
            -- Check that the line is high during the stop bit
            -------------------------------------------------------------------

            assert uartTx = '1'
                report "UART stop-bit error"
                severity failure;


            -------------------------------------------------------------------
            -- Store selected bytes for later assertions
            -------------------------------------------------------------------

            case byteIndex is

                when 0 =>
                    firstByte <= decodedByte;

                when 1 =>
                    secondByte <= decodedByte;

                when 2 =>
                    thirdByte <= decodedByte;

                when 3 =>
                    fourthByte <= decodedByte;

                when 4 =>
                    versionByte <= decodedByte;

                when 5 =>
                    statusByte <= decodedByte;

                when 6 =>
                    lengthHighByte <= decodedByte;

                when 7 =>
                    lengthLowByte <= decodedByte;

                -- Pixel count is at frame offsets 16 and 17.
                when 16 =>
                    pixelCountHighByte <= decodedByte;

                when 17 =>
                    pixelCountLowByte <= decodedByte;

                -- Pixel data begins at frame offset 18.
                when 18 =>
                    firstPixelHighByte <= decodedByte;

                when 19 =>
                    firstPixelLowByte <= decodedByte;

                when 20 =>
                    secondPixelHighByte <= decodedByte;

                when 21 =>
                    secondPixelLowByte <= decodedByte;

                when others =>
                    null;

            end case;

            byteIndex := byteIndex + 1;
            receivedByteCount <= byteIndex;

        end loop;
    end process;

end Simulation;
