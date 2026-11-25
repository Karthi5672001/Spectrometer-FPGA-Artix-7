-------------------------------------------------------------------------------
-- FILE: 08_command_controller.vhd
--
-- PURPOSE:
--   Interpret complete commands received from command_decoder.vhd and update
--   the spectrometer's operating configuration.
--
-- ROLE IN THE SPECTROMETER FIRMWARE:
--
--   The host-command path is:
--
--       Python host software
--               |
--               v
--       USB-UART bridge
--               |
--               v
--            uart_rx
--               |
--               v
--       command_decoder
--               |
--               | command_in
--               v
--       command_controller
--               |
--               +--> run_enable
--               +--> single_request
--               +--> integration_counts
--               +--> test_mode
--               +--> accepted_count
--               +--> command_pulse
--
--   command_decoder.vhd identifies the command ID and data field.
--   command_controller.vhd applies the command to the stored configuration.
--
-- COMMANDS:
--
--   0x1000: Set integration time and enable continuous acquisition
--
--       command_in.data contains integration time in microseconds.
--
--       The requested value is:
--         1. Clamped to MIN_INTEGRATION_US and MAX_INTEGRATION_US.
--         2. Converted into 5 MHz detector-clock counts.
--         3. Stored in integration_counts.
--         4. Used to enable continuous acquisition.
--
--       Example:
--
--           data = 200 us
--           COUNTS_PER_US = 5
--           integration_counts = 1,000
--
--
--   0x4000: Control continuous acquisition
--
--       command_in.data(0) = '0':
--           Disable continuous acquisition.
--
--       command_in.data(0) = '1':
--           Enable or resume continuous acquisition using the stored
--           integration time.
--
--
--   0x4001: Request one spectrum
--
--       Produces a one-system-clock pulse on single_request.
--
--       spectrometer_top.vhd latches this pulse in single_pending until the
--       scheduler can safely start the acquisition.
--
--
--   0x5000: Select input/test-data mode
--
--       command_in.data(1 downto 0) = "00":
--           Use real 12-bit ADC data.
--
--       command_in.data(1 downto 0) = "01":
--           Use deterministic pixel-ramp test data.
--
--       command_in.data(1 downto 0) = "10":
--           Use frame-varying ramp test data.
--
--       command_in.data(1 downto 0) = "11":
--           Reserved.
--
--
-- UNSUPPORTED COMMANDS:
--
--   Unsupported command IDs are ignored. They do not change the configuration,
--   increment accepted_count, or assert command_pulse.
-------------------------------------------------------------------------------

library IEEE;

-- Provides std_logic and std_logic_vector.
use IEEE.STD_LOGIC_1164.ALL;

-- Provides unsigned arithmetic and conversions.
use IEEE.NUMERIC_STD.ALL;

-- Imports:
--   DEFAULT_INTEGRATION_US
--   MIN_INTEGRATION_US
--   MAX_INTEGRATION_US
--   COUNTS_PER_US
use work.hardware_config.all;

-- Imports:
--   command_type
--   clamp_us
--   us_to_counts
use work.protocol_types.all;


-------------------------------------------------------------------------------
-- ENTITY
-------------------------------------------------------------------------------

entity command_controller is
    port (

        -----------------------------------------------------------------------
        -- System/control clock.
        --
        -- In spectrometer_top.vhd this is the 10 MHz system clock.
        -----------------------------------------------------------------------

        clock :
            in std_logic;

        -----------------------------------------------------------------------
        -- Active-high synchronous reset.
        -----------------------------------------------------------------------

        reset :
            in std_logic;

        -----------------------------------------------------------------------
        -- Complete decoded command from command_decoder.vhd.
        --
        -- The controller examines command_in only while command_in.valid is
        -- high.
        -----------------------------------------------------------------------

        command_in :
            in command_type;

        -----------------------------------------------------------------------
        -- Continuous-acquisition enable.
        --
        -- '0':
        --     Do not begin another continuous acquisition.
        --
        -- '1':
        --     Allow the top-level scheduler to generate acquisitions.
        --
        -- Reset deliberately sets this output low. The presence of a default
        -- integration time must not cause acquisition to begin automatically.
        -----------------------------------------------------------------------

        run_enable :
            out std_logic;

        -----------------------------------------------------------------------
        -- One-clock request for one spectrum.
        --
        -- This output returns low by default on every clock. Command 0x4001
        -- pulses it high for one system-clock cycle.
        -----------------------------------------------------------------------

        single_request :
            out std_logic;

        -----------------------------------------------------------------------
        -- Effective integration time in 5 MHz detector-clock counts.
        --
        -- This stores the clamped and converted integration-time request.
        --
        -- With the current configuration:
        --
        --     200 us * 5 counts/us = 1,000 counts
        -----------------------------------------------------------------------

        integration_counts :
            out unsigned(31 downto 0);

        -----------------------------------------------------------------------
        -- Detector-data source selection.
        --
        -- "00": real ADC data
        -- "01": pixel-ramp test pattern
        -- "10": frame-varying ramp test pattern
        -- "11": reserved
        -----------------------------------------------------------------------

        test_mode :
            out std_logic_vector(1 downto 0);

        -----------------------------------------------------------------------
        -- Number of recognized and accepted commands since reset.
        --
        -- Unsupported commands do not increment this counter.
        --
        -- A per-frame snapshot of this value is included in transmitted
        -- spectrum metadata.
        -----------------------------------------------------------------------

        accepted_count :
            out unsigned(31 downto 0);

        -----------------------------------------------------------------------
        -- One-clock indication that a recognized command was accepted.
        --
        -- This can be used for diagnostics, LEDs, or logic-analyser probing.
        -----------------------------------------------------------------------

        command_pulse :
            out std_logic
    );

end entity command_controller;


-------------------------------------------------------------------------------
-- ARCHITECTURE
-------------------------------------------------------------------------------

architecture rtl of command_controller is

    ---------------------------------------------------------------------------
    -- Internal accepted-command counter.
    --
    -- VHDL-93/2002 does not permit reading an output port internally. The
    -- controller must read the old count in order to increment it, so the count
    -- is held in an internal register and copied to accepted_count.
    ---------------------------------------------------------------------------

    signal accepted_count_reg :
        unsigned(31 downto 0) := (others => '0');

begin

    ---------------------------------------------------------------------------
    -- Expose the internal counter through the output port.
    ---------------------------------------------------------------------------

    accepted_count <= accepted_count_reg;


    ---------------------------------------------------------------------------
    -- COMMAND-CONTROL PROCESS
    ---------------------------------------------------------------------------

    COMMAND_CONTROL_PROCESS : process(clock)

        -----------------------------------------------------------------------
        -- Temporary integration-time value in microseconds.
        --
        -- clamp_us returns a natural value that is safe to pass to
        -- us_to_counts.
        -----------------------------------------------------------------------

        variable requested_integration_us :
            natural;

    begin

        if rising_edge(clock) then

            -------------------------------------------------------------------
            -- Pulse outputs default low.
            --
            -- Each pulse is asserted only while processing the corresponding
            -- command.
            -------------------------------------------------------------------

            single_request <= '0';
            command_pulse  <= '0';


            -------------------------------------------------------------------
            -- Synchronous reset
            -------------------------------------------------------------------

            if reset = '1' then

                ---------------------------------------------------------------
                -- Acquisition remains disabled after reset.
                --
                -- A valid command must be received before continuous
                -- acquisition can start.
                ---------------------------------------------------------------

                run_enable <= '0';

                ---------------------------------------------------------------
                -- Store the default integration time.
                --
                -- DEFAULT_INTEGRATION_US = 200 us
                -- COUNTS_PER_US          = 5
                --
                -- Initial stored value:
                --
                --     200 * 5 = 1,000 detector-clock counts
                ---------------------------------------------------------------

                integration_counts <=
                    us_to_counts(
                        DEFAULT_INTEGRATION_US
                    );

                ---------------------------------------------------------------
                -- Default to real ADC data.
                ---------------------------------------------------------------

                test_mode <= "00";

                ---------------------------------------------------------------
                -- Clear the accepted-command counter.
                ---------------------------------------------------------------

                accepted_count_reg <=
                    (others => '0');


            -------------------------------------------------------------------
            -- Process a complete decoded command.
            -------------------------------------------------------------------

            elsif command_in.valid = '1' then

                case command_in.command_id is

                    -----------------------------------------------------------
                    -- 0x1000:
                    -- Set integration time and enable continuous acquisition.
                    -----------------------------------------------------------

                    when x"1000" =>

                        -------------------------------------------------------
                        -- Interpret the 32-bit command data as an unsigned
                        -- integration time in microseconds.
                        --
                        -- Clamp the request to the configured permitted range.
                        -------------------------------------------------------

                        requested_integration_us :=
                            clamp_us(
                                unsigned(command_in.data)
                            );

                        -------------------------------------------------------
                        -- Convert microseconds into 5 MHz detector-clock
                        -- counts and store the effective value.
                        -------------------------------------------------------

                        integration_counts <=
                            us_to_counts(
                                requested_integration_us
                            );

                        -------------------------------------------------------
                        -- Receiving a valid integration-time command also
                        -- enables continuous acquisition.
                        -------------------------------------------------------

                        run_enable <= '1';

                        -------------------------------------------------------
                        -- Record and indicate the accepted command.
                        -------------------------------------------------------

                        accepted_count_reg <=
                            accepted_count_reg + 1;

                        command_pulse <= '1';


                    -----------------------------------------------------------
                    -- 0x4000:
                    -- Stop or resume continuous acquisition.
                    -----------------------------------------------------------

                    when x"4000" =>

                        -------------------------------------------------------
                        -- Only data bit zero is used:
                        --
                        --     0 = stop
                        --     1 = run/resume
                        -------------------------------------------------------

                        run_enable <=
                            command_in.data(0);

                        accepted_count_reg <=
                            accepted_count_reg + 1;

                        command_pulse <= '1';


                    -----------------------------------------------------------
                    -- 0x4001:
                    -- Request exactly one spectrum.
                    -----------------------------------------------------------

                    when x"4001" =>

                        -------------------------------------------------------
                        -- Generate a one-clock pulse. The top-level scheduler
                        -- latches this request until it can safely begin the
                        -- acquisition.
                        -------------------------------------------------------

                        single_request <= '1';

                        accepted_count_reg <=
                            accepted_count_reg + 1;

                        command_pulse <= '1';


                    -----------------------------------------------------------
                    -- 0x5000:
                    -- Select the detector/test-data input mode.
                    -----------------------------------------------------------

                    when x"5000" =>

                        test_mode <=
                            command_in.data(1 downto 0);

                        accepted_count_reg <=
                            accepted_count_reg + 1;

                        command_pulse <= '1';


                    -----------------------------------------------------------
                    -- Unsupported command.
                    --
                    -- Leave all stored configuration values unchanged.
                    -----------------------------------------------------------

                    when others =>

                        null;

                end case;

            end if;

        end if;

    end process COMMAND_CONTROL_PROCESS;

end architecture rtl;
