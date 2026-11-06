library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.env.all;

use work.defs.all;


entity tb_driver_acquisition is
end entity tb_driver_acquisition;


architecture Simulation of tb_driver_acquisition is

    ---------------------------------------------------------------------------
    -- Clock periods
    ---------------------------------------------------------------------------

    constant SYS_CLOCK_PERIOD :
        time := 100 ns;

    constant READOUT_CLOCK_PERIOD :
        time := 16.666667 ns;

    constant EXPECTED_DEVICE_CLOCK_PERIOD :
        time := 200 ns;


    ---------------------------------------------------------------------------
    -- Test configuration
    ---------------------------------------------------------------------------

    constant TEST_INTEGRATION_TIME :
        natural := 100;

    constant ACQUISITION_TIMEOUT_CYCLES :
        natural := 50000;

    constant RAM_SETTLE_TIME :
        time := 1 ns;


    ---------------------------------------------------------------------------
    -- Clocks
    ---------------------------------------------------------------------------

    signal sysClk :
        std_logic := '0';

    signal readoutClk :
        std_logic := '0';


    ---------------------------------------------------------------------------
    -- Driver control
    ---------------------------------------------------------------------------

    signal trigger :
        std_logic := '0';

    signal testParameters :
        parameterList_type := (
            driver => (
                integrationTime => TEST_INTEGRATION_TIME,
                useTestData     => '0'
            ),

            readout => (
                useTestData => '0'
            ),

            repPeriod => 1
        );

    signal driverDone :
        std_logic;


    ---------------------------------------------------------------------------
    -- RAM read port
    ---------------------------------------------------------------------------

    signal readoutAddress :
        std_logic_vector(8 downto 0) := (others => '0');

    signal readoutData :
        std_logic_vector(15 downto 0);


    ---------------------------------------------------------------------------
    -- Spectrometer interface
    ---------------------------------------------------------------------------

    signal deviceClock :
        std_logic;

    signal deviceStart :
        std_logic;

    signal dataClock :
        std_logic;

    signal endOfScan :
        std_logic := '0';


    ---------------------------------------------------------------------------
    -- ADC interface
    ---------------------------------------------------------------------------

    signal adcClock :
        std_logic;

    signal adcData :
        std_logic_vector(11 downto 0) := (others => '0');


    ---------------------------------------------------------------------------
    -- Debug interface
    ---------------------------------------------------------------------------

    signal debug :
        std_logic_vector(7 downto 0);


    ---------------------------------------------------------------------------
    -- Test status
    ---------------------------------------------------------------------------

    signal deviceClockChecked :
        std_logic := '0';


begin

    ---------------------------------------------------------------------------
    -- 10 MHz system clock
    ---------------------------------------------------------------------------

    SYSTEM_CLOCK_GENERATOR: process
    begin
        loop
            sysClk <= '0';
            wait for SYS_CLOCK_PERIOD / 2;

            sysClk <= '1';
            wait for SYS_CLOCK_PERIOD / 2;
        end loop;
    end process;


    ---------------------------------------------------------------------------
    -- 60 MHz RAM-read clock
    ---------------------------------------------------------------------------

    READOUT_CLOCK_GENERATOR: process
    begin
        loop
            readoutClk <= '0';
            wait for READOUT_CLOCK_PERIOD / 2;

            readoutClk <= '1';
            wait for READOUT_CLOCK_PERIOD / 2;
        end loop;
    end process;


    ---------------------------------------------------------------------------
    -- Simulated returned spectrometer data clock
    ---------------------------------------------------------------------------

    dataClock <= deviceClock;


    ---------------------------------------------------------------------------
    -- Simulated physical ADC
    --
    -- The ADC model advances one count on each falling data-clock edge while
    -- devStart is low.
    --
    -- The driver captures adcData on falling edges and writes the registered
    -- sample to RAM on rising edges.
    ---------------------------------------------------------------------------

    ADC_MODEL: process(dataClock)

        variable adcCount :
            unsigned(11 downto 0) := (others => '0');

        variable acquisitionActive :
            boolean := false;

    begin
        if falling_edge(dataClock) then

            if deviceStart = '0' then

                if acquisitionActive = false then
                    adcCount :=
                        (others => '0');

                    acquisitionActive :=
                        true;

                else
                    adcCount :=
                        adcCount + 1;
                end if;

                adcData <=
                    std_logic_vector(adcCount);

            else
                acquisitionActive :=
                    false;

                adcData <=
                    std_logic_vector(adcCount);
            end if;
        end if;
    end process;


    ---------------------------------------------------------------------------
    -- Driver under test
    --
    -- Positional association avoids using the VHDL-2008 reserved word
    -- "parameter" as a named formal association.
    ---------------------------------------------------------------------------

    DRIVER_DUT: entity work.driver(Behavioral)
        port map (
            sysClk,
            trigger,
            testParameters,
            driverDone,

            readoutClk,
            readoutAddress,
            readoutData,

            deviceClock,
            deviceStart,
            dataClock,
            endOfScan,

            adcClock,
            adcData,

            debug
        );


    ---------------------------------------------------------------------------
    -- Device-clock check
    ---------------------------------------------------------------------------

    DEVICE_CLOCK_MONITOR: process

        variable firstEdgeTime :
            time := 0 ns;

        variable secondEdgeTime :
            time := 0 ns;

        variable measuredPeriod :
            time := 0 ns;

    begin
        -- Ignore the first potentially partial simulation clock period.
        wait until rising_edge(deviceClock);

        wait until rising_edge(deviceClock);
        firstEdgeTime := now;

        wait until rising_edge(deviceClock);
        secondEdgeTime := now;

        measuredPeriod :=
            secondEdgeTime - firstEdgeTime;

        assert measuredPeriod = EXPECTED_DEVICE_CLOCK_PERIOD
            report
                "Incorrect device-clock period"
            severity failure;

        deviceClockChecked <= '1';

        report
            "Device clock verified at 5 MHz"
            severity note;

        wait;
    end process;


    ---------------------------------------------------------------------------
    -- Acquisition stimulus and RAM verification
    ---------------------------------------------------------------------------

    STIMULUS_AND_CHECKS: process

        variable acquisitionStarted :
            boolean := false;

        variable acquisitionCompleted :
            boolean := false;

        variable firstWord :
            unsigned(15 downto 0) := (others => '0');

        variable previousWord :
            unsigned(15 downto 0) := (others => '0');

        variable observedWord :
            unsigned(15 downto 0) := (others => '0');

        variable expectedSample :
            unsigned(11 downto 0) := (others => '0');

    begin

        -----------------------------------------------------------------------
        -- Initial conditions
        -----------------------------------------------------------------------

        trigger        <= '0';
        readoutAddress <= (others => '0');
        endOfScan      <= '0';


        -----------------------------------------------------------------------
        -- Allow initialization
        -----------------------------------------------------------------------

        for initializationCycle in 0 to 19 loop
            wait until rising_edge(sysClk);
        end loop;

        wait for 1 ns;


        -----------------------------------------------------------------------
        -- Confirm production-mode settings
        -----------------------------------------------------------------------

        assert testParameters.driver.integrationTime =
               TEST_INTEGRATION_TIME
            report
                "Incorrect test integration time"
            severity failure;

        assert testParameters.driver.useTestData = '0'
            report
                "Driver test-data mode must be disabled"
            severity failure;

        assert driverDone = '1'
            report
                "Driver did not initialize in the idle state"
            severity failure;


        -----------------------------------------------------------------------
        -- Apply one acquisition trigger
        -----------------------------------------------------------------------

        wait until falling_edge(sysClk);
        trigger <= '1';

        wait until falling_edge(sysClk);
        trigger <= '0';


        -----------------------------------------------------------------------
        -- Wait for acquisition start
        -----------------------------------------------------------------------

        acquisitionStarted := false;

        for timeoutCycle in 0 to ACQUISITION_TIMEOUT_CYCLES - 1 loop
            wait until rising_edge(sysClk);
            wait for 1 ns;

            if driverDone = '0' then
                acquisitionStarted := true;
                exit;
            end if;
        end loop;

        assert acquisitionStarted
            report
                "Acquisition did not start"
            severity failure;

        report
            "Driver accepted the acquisition trigger"
            severity note;


        -----------------------------------------------------------------------
        -- Wait for acquisition completion
        -----------------------------------------------------------------------

        acquisitionCompleted := false;

        for timeoutCycle in 0 to ACQUISITION_TIMEOUT_CYCLES - 1 loop
            wait until rising_edge(sysClk);
            wait for 1 ns;

            if driverDone = '1' then
                acquisitionCompleted := true;
                exit;
            end if;
        end loop;

        assert acquisitionCompleted
            report
                "Acquisition did not complete"
            severity failure;

        report
            "Acquisition completed"
            severity note;


        -----------------------------------------------------------------------
        -- Let the final RAM activity settle
        -----------------------------------------------------------------------

        for settleCycle in 0 to 3 loop
            wait until rising_edge(readoutClk);
        end loop;

        wait for RAM_SETTLE_TIME;


        -----------------------------------------------------------------------
        -- Read RAM address zero
        -----------------------------------------------------------------------

        wait until falling_edge(readoutClk);

        readoutAddress <=
            (others => '0');

        wait until rising_edge(readoutClk);
        wait for RAM_SETTLE_TIME;

        firstWord :=
            unsigned(readoutData);

        previousWord :=
            firstWord;

        assert firstWord(15 downto 12) = "0000"
            report
                "RAM address 0 does not contain a 12-bit ADC sample"
            severity failure;


        -----------------------------------------------------------------------
        -- Verify addresses 1 through 287
        --
        -- The exact first stored count depends on the acquisition delay.
        -- The important property is that every subsequent RAM word is the next
        -- 12-bit ADC count.
        -----------------------------------------------------------------------

        for pixelIndex in 1 to DATA_LEN - 1 loop

            wait until falling_edge(readoutClk);

            readoutAddress <=
                std_logic_vector(
                    to_unsigned(
                        pixelIndex,
                        readoutAddress'length
                    )
                );

            wait until rising_edge(readoutClk);
            wait for RAM_SETTLE_TIME;

            observedWord :=
                unsigned(readoutData);

            expectedSample :=
                previousWord(11 downto 0) + 1;

            assert observedWord(15 downto 12) = "0000"
                report
                    "Upper ADC padding bits are not zero at RAM address " &
                    integer'image(pixelIndex)
                severity failure;

            assert observedWord(11 downto 0) = expectedSample
                report
                    "Non-consecutive ADC sample at RAM address " &
                    integer'image(pixelIndex) &
                    ". Previous sample = " &
                    integer'image(
                        to_integer(previousWord(11 downto 0))
                    ) &
                    ", current sample = " &
                    integer'image(
                        to_integer(observedWord(11 downto 0))
                    )
                severity failure;

            previousWord :=
                observedWord;
        end loop;


        -----------------------------------------------------------------------
        -- Final checks
        -----------------------------------------------------------------------

        assert deviceClockChecked = '1'
            report
                "Device-clock verification did not complete"
            severity failure;


        -----------------------------------------------------------------------
        -- Success
        -----------------------------------------------------------------------

        report
            "Acquisition ADC-path simulation passed. " &
            integer'image(DATA_LEN) &
            " consecutive physical-ADC samples verified."
            severity note;

        report
            "First stored ADC sample = " &
            integer'image(
                to_integer(firstWord(11 downto 0))
            ) &
            ", last stored ADC sample = " &
            integer'image(
                to_integer(previousWord(11 downto 0))
            )
            severity note;

        stop;
        wait;
    end process;


    ---------------------------------------------------------------------------
    -- Global timeout
    ---------------------------------------------------------------------------

    GLOBAL_TIMEOUT: process
    begin
        wait for 10 ms;

        assert false
            report
                "Global simulation timeout"
            severity failure;

        stop;
        wait;
    end process;

end architecture Simulation;