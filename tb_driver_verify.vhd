library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.env.all;

use work.defs.all;

entity tb_driver_verify is
end tb_driver_verify;

architecture Simulation of tb_driver_verify is

    ------------------------------------------------------------------------
    -- Clocks
    ------------------------------------------------------------------------

    constant SYSCLK_PERIOD  : time := 100 ns;   -- 10 MHz
    constant DATACLK_PERIOD : time := 200 ns;   -- 5 MHz

    signal sysClk  : std_logic := '0';
    signal dataClk : std_logic := '0';

    ------------------------------------------------------------------------
    -- Driver interface
    ------------------------------------------------------------------------

    signal trig : std_logic := '0';

    signal parameter : parameterList_type :=
        defaultParameter;

    signal done : std_logic;

    signal readoutClk :
        std_logic := '0';

    signal readoutAddr :
        std_logic_vector(8 downto 0) :=
        (others => '0');

    signal readoutData :
        std_logic_vector(15 downto 0);

    signal devClk :
        std_logic;

    signal devStart :
        std_logic;

    signal EOS :
        std_logic := '0';

    signal ADC_clock :
        std_logic;

    signal ADC_data :
        std_logic_vector(11 downto 0) :=
        (others => '0');

    signal debug :
        std_logic_vector(7 downto 0);

    ------------------------------------------------------------------------
    -- Monitoring
    ------------------------------------------------------------------------

    signal devStartSeen :
        boolean := false;

begin

    ------------------------------------------------------------------------
    -- Clocks
    ------------------------------------------------------------------------

    sysClk <= not sysClk after SYSCLK_PERIOD/2;

    dataClk <= not dataClk after DATACLK_PERIOD/2;

    readoutClk <= dataClk;

    ------------------------------------------------------------------------
    -- DUT
    ------------------------------------------------------------------------

    DUT : entity work.driver
        port map
        (
            sysClk => sysClk,
            trig => trig,
            parameter => parameter,
            done => done,

            readoutClk => readoutClk,
            readoutAddr => readoutAddr,
            readoutData => readoutData,

            devClk => devClk,
            devStart => devStart,
            dataClk => dataClk,
            EOS => EOS,

            ADC_clock => ADC_clock,
            ADC_data => ADC_data,

            debug => debug
        );

    ------------------------------------------------------------------------
    -- Synthetic ADC
    --
    -- Generates increasing values:
    -- 0,1,2,3...
    ------------------------------------------------------------------------

    ADC_MODEL : process(dataClk)

        variable sampleValue :
            natural := 0;

    begin

        if falling_edge(dataClk) then

            ADC_data <=
                std_logic_vector
                (
                    to_unsigned
                    (
                        sampleValue mod 4096,
                        12
                    )
                );

            sampleValue := sampleValue + 1;

        end if;

    end process;

    ------------------------------------------------------------------------
    -- Observe devStart activity
    ------------------------------------------------------------------------

    DEVSTART_MONITOR : process(dataClk)
    begin

        if falling_edge(dataClk) then

            if devStart = '0' then
                devStartSeen <= true;
            end if;

        end if;

    end process;

    ------------------------------------------------------------------------
    -- Test stimulus
    ------------------------------------------------------------------------

    STIMULUS : process
    begin

        report
            "Starting driver verification"
            severity note;

        --------------------------------------------------------------------
        -- Configure integration time
        --------------------------------------------------------------------

        parameter.driver.integrationTime <= 2500;

        wait for 10 us;

        --------------------------------------------------------------------
        -- Trigger acquisition
        --------------------------------------------------------------------

        wait until rising_edge(sysClk);

        trig <= '1';

        wait until rising_edge(sysClk);

        trig <= '0';

        --------------------------------------------------------------------
        -- Driver should leave idle
        --------------------------------------------------------------------

        wait until done = '0';

        report
            "Driver accepted acquisition trigger"
            severity note;

        --------------------------------------------------------------------
        -- Wait for acquisition to complete
        --------------------------------------------------------------------

        wait until done = '1';

        report
            "Driver reported acquisition complete"
            severity note;

        --------------------------------------------------------------------
        -- Checks
        --------------------------------------------------------------------

        assert devStartSeen
            report
                "devStart never became active"
            severity failure;

        assert ADC_clock = dataClk
            report
                "ADC_clock does not follow dataClk"
            severity failure;

        report
            "PASS - Driver timing test completed"
            severity note;

        stop;
        wait;

    end process;

end Simulation;
