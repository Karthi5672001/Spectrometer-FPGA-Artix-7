-------------------------------------------------------------------------------
-- FILE: 09_detector_capture.vhd
--
-- PURPOSE:
--   Control detector integration timing, receive the detector's returned data
--   clock, capture 12-bit ADC samples, and write one 288-pixel spectrum into
--   dual-port block RAM.
--
-- ROLE IN THE SPECTROMETER FIRMWARE:
--
--   The acquisition path is:
--
--       spectrometer_top scheduler
--                  |
--                  | start pulse
--                  v
--          detector_capture
--                  |
--                  +--> dev_clock: 5 MHz detector clock
--                  +--> dev_start: integration/start signal
--                  +--> adc_clock: clock forwarded to the ADC
--                  |
--                  v
--            detector readout
--                  |
--                  +--> data_clock
--                  +--> adc_data
--                  |
--                  v
--          spectrum RAM Port A
--
--   The module contains logic in two clock domains:
--
--       sys_clock domain:
--           - Generates the 5 MHz detector clock.
--           - Times the requested integration period.
--           - Controls dev_start.
--           - Reports busy and done_pulse.
--
--       data_clock domain:
--           - Waits for the detector readout event.
--           - Delays until the first valid pixel.
--           - Captures exactly PIXEL_COUNT samples.
--           - Writes samples to spectrum RAM.
--
-- CLOCK-DOMAIN CROSSINGS:
--
--   A toggle-based event transfer is used in each direction:
--
--       start_toggle_sys:
--           sys_clock -> data_clock
--
--       done_toggle_data:
--           data_clock -> sys_clock
--
--   Toggle synchronization is used because a one-clock pulse could otherwise
--   be missed when crossing between unrelated clock domains.
--
-- DATA MODES:
--
--       "00": Real ADC data, zero-extended from 12 to 16 bits.
--
--       "01": Pixel ramp:
--
--                 pixel 0   = 0x0000
--                 pixel 1   = 0x0001
--                 ...
--                 pixel 287 = 0x011F
--
--       "10": Frame-varying pixel ramp.
--
--             Alternate acquisitions set bit 15, helping detect stale or
--             mixed frames:
--
--                 frame A: 0x0000 to 0x011F
--                 frame B: 0x8000 to 0x811F
--
--       "11": Reserved; outputs zero.
-------------------------------------------------------------------------------

library IEEE;

use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hardware_config.all;


-------------------------------------------------------------------------------
-- ENTITY
-------------------------------------------------------------------------------

entity detector_capture is
    port (
        -----------------------------------------------------------------------
        -- System-clock control interface
        -----------------------------------------------------------------------

        -- 10 MHz control clock.
        sys_clock : in std_logic;

        -- Active-high reset for the system-clock state machine.
        sys_reset : in std_logic;

        -- One-system-clock pulse requesting a new acquisition.
        start : in std_logic;

        -- Effective integration time in 5 MHz detector-clock counts.
        integration_counts : in unsigned(31 downto 0);


        -----------------------------------------------------------------------
        -- Detector and ADC input interface
        -----------------------------------------------------------------------

        -- Returned detector/data clock.
        --
        -- Spectrum RAM writes occur on rising edges of this clock.
        data_clock : in std_logic;

        -- Twelve-bit ADC sample.
        adc_data : in std_logic_vector(11 downto 0);

        -- Selects real ADC or generated test data.
        test_mode : in std_logic_vector(1 downto 0);


        -----------------------------------------------------------------------
        -- Detector and ADC output interface
        -----------------------------------------------------------------------

        -- Nominal 5 MHz detector clock generated from sys_clock.
        dev_clock : out std_logic;

        -- Detector integration/start control.
        dev_start : out std_logic;

        -- Clock forwarded to the ADC.
        adc_clock : out std_logic;


        -----------------------------------------------------------------------
        -- Acquisition status
        -----------------------------------------------------------------------

        -- High from acquisition start until all pixels have been stored.
        busy : out std_logic;

        -- One-system-clock pulse indicating capture completion.
        done_pulse : out std_logic;


        -----------------------------------------------------------------------
        -- Spectrum RAM Port-A write interface
        -----------------------------------------------------------------------

        -- One-data-clock RAM write-enable pulse per pixel.
        ram_we : out std_logic;

        -- RAM address, from zero to PIXEL_COUNT - 1.
        ram_addr : out std_logic_vector(8 downto 0);

        -- Sixteen-bit spectrum value written into RAM.
        ram_data : out std_logic_vector(15 downto 0)
    );
end entity detector_capture;


-------------------------------------------------------------------------------
-- ARCHITECTURE
-------------------------------------------------------------------------------

architecture rtl of detector_capture is

    ---------------------------------------------------------------------------
    -- System-clock acquisition states
    ---------------------------------------------------------------------------

    type sys_state_type is (
        IDLE,
        INTEGRATE,
        WAIT_CAPTURE
    );

    signal sys_state :
        sys_state_type := IDLE;


    ---------------------------------------------------------------------------
    -- Detector-clock generation and integration counter
    ---------------------------------------------------------------------------

    -- Internal detector clock. Toggling on each 10 MHz sys_clock edge produces
    -- a 5 MHz square wave.
    signal dev_clock_internal :
        std_logic := '0';

    -- Counts complete 5 MHz detector-clock periods during integration.
    signal integration_counter :
        unsigned(31 downto 0) := (others => '0');


    ---------------------------------------------------------------------------
    -- Start-event CDC: sys_clock to data_clock
    ---------------------------------------------------------------------------

    -- Toggles whenever integration finishes and detector readout should begin.
    signal start_toggle_sys :
        std_logic := '0';

    -- Two-stage synchronizer in the data_clock domain.
    signal start_meta :
        std_logic := '0';

    signal start_sync :
        std_logic := '0';

    -- Previous synchronized toggle value, used for change detection.
    signal start_previous :
        std_logic := '0';


    ---------------------------------------------------------------------------
    -- Completion-event CDC: data_clock to sys_clock
    ---------------------------------------------------------------------------

    -- Toggles after the final pixel has been written.
    signal done_toggle_data :
        std_logic := '0';

    -- Two-stage synchronizer in the sys_clock domain.
    signal done_meta :
        std_logic := '0';

    signal done_sync :
        std_logic := '0';

    -- Previous synchronized toggle value, used for change detection.
    signal done_previous :
        std_logic := '0';


    ---------------------------------------------------------------------------
    -- ADC capture and pixel-storage state
    ---------------------------------------------------------------------------

    -- ADC sample captured on the falling edge of data_clock.
    signal adc_latched :
        std_logic_vector(11 downto 0) := (others => '0');

    -- High while the data-clock process is collecting one spectrum.
    signal capturing :
        std_logic := '0';

    -- Counts invalid/dummy data-clock periods before pixel zero.
    signal first_pixel_delay_count :
        natural range 0 to FIRST_PIXEL_DELAY := 0;

    -- Current spectrum sample index.
    signal pixel_index :
        natural range 0 to PIXEL_COUNT - 1 := 0;

    -- Stable frame marker captured from the synchronized acquisition event.
    --
    -- This avoids using start_toggle_sys directly in the data_clock domain.
    signal frame_pattern_bit :
        std_logic := '0';


    ---------------------------------------------------------------------------
    -- Vivado CDC attributes
    ---------------------------------------------------------------------------

    attribute ASYNC_REG : string;

    attribute ASYNC_REG of done_meta :
        signal is "TRUE";

    attribute ASYNC_REG of done_sync :
        signal is "TRUE";

    attribute ASYNC_REG of start_meta :
        signal is "TRUE";

    attribute ASYNC_REG of start_sync :
        signal is "TRUE";

begin

    ---------------------------------------------------------------------------
    -- External clock outputs
    ---------------------------------------------------------------------------

    -- Forward the returned detector data clock to the ADC.
    adc_clock <= data_clock;

    -- Drive the detector with the internally divided 5 MHz clock.
    dev_clock <= dev_clock_internal;


    ---------------------------------------------------------------------------
    -- System-clock acquisition controller
    ---------------------------------------------------------------------------

    SYSTEM_CONTROL : process(sys_clock)
    begin
        if rising_edge(sys_clock) then

            -------------------------------------------------------------------
            -- Divide the 10 MHz system clock by two.
            -------------------------------------------------------------------

            dev_clock_internal <=
                not dev_clock_internal;


            -------------------------------------------------------------------
            -- done_pulse is asserted for only one sys_clock cycle.
            -------------------------------------------------------------------

            done_pulse <= '0';


            -------------------------------------------------------------------
            -- Synchronize the capture-complete toggle into sys_clock.
            -------------------------------------------------------------------

            done_meta     <= done_toggle_data;
            done_sync     <= done_meta;
            done_previous <= done_sync;


            -------------------------------------------------------------------
            -- System-clock reset
            -------------------------------------------------------------------

            if sys_reset = '1' then

                sys_state <= IDLE;

                dev_clock_internal <= '0';

                dev_start <= '0';

                busy <= '0';

                integration_counter <=
                    (others => '0');

                start_toggle_sys <= '0';

                done_meta <= '0';
                done_sync <= '0';
                done_previous <= '0';


            -------------------------------------------------------------------
            -- Normal acquisition control
            -------------------------------------------------------------------

            else

                case sys_state is

                    -----------------------------------------------------------
                    -- Wait for the top-level scheduler to request acquisition.
                    -----------------------------------------------------------

                    when IDLE =>

                        dev_start <= '0';
                        busy      <= '0';

                        if start = '1' then

                            dev_start <= '1';
                            busy      <= '1';

                            integration_counter <=
                                (others => '0');

                            sys_state <= INTEGRATE;

                        end if;


                    -----------------------------------------------------------
                    -- Hold dev_start active for the requested integration time.
                    -----------------------------------------------------------

                    when INTEGRATE =>

                        busy <= '1';

                        -- dev_clock_internal is low once during each complete
                        -- 5 MHz detector-clock period.
                        if dev_clock_internal = '0' then

                            if
                                integration_counter + 1 >=
                                integration_counts
                            then

                                dev_start <= '0';

                                -- Toggle the event bit rather than sending a
                                -- short pulse across the clock-domain boundary.
                                start_toggle_sys <=
                                    not start_toggle_sys;

                                sys_state <= WAIT_CAPTURE;

                            else

                                integration_counter <=
                                    integration_counter + 1;

                            end if;

                        end if;


                    -----------------------------------------------------------
                    -- Wait until all PIXEL_COUNT samples have been stored.
                    -----------------------------------------------------------

                    when WAIT_CAPTURE =>

                        busy <= '1';

                        if done_sync /= done_previous then

                            busy <= '0';

                            done_pulse <= '1';

                            sys_state <= IDLE;

                        end if;

                end case;

            end if;

        end if;
    end process SYSTEM_CONTROL;


    ---------------------------------------------------------------------------
    -- ADC input latch
    --
    -- adc_data is sampled on the falling edge of data_clock. The corresponding
    -- RAM write occurs on a later rising edge, giving the ADC output time to
    -- settle before storage.
    ---------------------------------------------------------------------------

    ADC_INPUT_LATCH : process(data_clock)
    begin
        if falling_edge(data_clock) then

            adc_latched <= adc_data;

        end if;
    end process ADC_INPUT_LATCH;


    ---------------------------------------------------------------------------
    -- Data-clock capture and RAM-write controller
    ---------------------------------------------------------------------------

    DATA_CAPTURE : process(data_clock)

        variable sample_value :
            unsigned(15 downto 0);

    begin
        if rising_edge(data_clock) then

            -------------------------------------------------------------------
            -- RAM write-enable defaults low.
            -------------------------------------------------------------------

            ram_we <= '0';


            -------------------------------------------------------------------
            -- Synchronize and edge-detect the acquisition-start toggle.
            -------------------------------------------------------------------

            start_meta     <= start_toggle_sys;
            start_sync     <= start_meta;
            start_previous <= start_sync;


            -------------------------------------------------------------------
            -- Begin a new detector readout.
            -------------------------------------------------------------------

            if
                start_sync /= start_previous and
                capturing = '0'
            then

                capturing <= '1';

                first_pixel_delay_count <= 0;

                pixel_index <= 0;

                -- Capture the synchronized toggle phase for mode-2 test data.
                frame_pattern_bit <= start_sync;


            -------------------------------------------------------------------
            -- Capture one spectrum.
            -------------------------------------------------------------------

            elsif capturing = '1' then

                ---------------------------------------------------------------
                -- Wait through detector dummy/pipeline clocks.
                ---------------------------------------------------------------

                if first_pixel_delay_count < FIRST_PIXEL_DELAY then

                    first_pixel_delay_count <=
                        first_pixel_delay_count + 1;

                else

                    -----------------------------------------------------------
                    -- Generate or capture the current sample.
                    -----------------------------------------------------------

                    case test_mode is

                        -------------------------------------------------------
                        -- Real ADC mode.
                        --
                        -- Zero-extend the 12-bit ADC value to 16 bits.
                        -------------------------------------------------------

                        when "00" =>

                            sample_value :=
                                resize(
                                    unsigned(adc_latched),
                                    16
                                );


                        -------------------------------------------------------
                        -- Deterministic ramp test mode.
                        -------------------------------------------------------

                        when "01" =>

                            sample_value :=
                                to_unsigned(
                                    pixel_index,
                                    16
                                );


                        -------------------------------------------------------
                        -- Frame-varying ramp test mode.
                        -------------------------------------------------------

                        when "10" =>

                            sample_value :=
                                to_unsigned(
                                    pixel_index,
                                    16
                                );

                            if frame_pattern_bit = '1' then

                                sample_value :=
                                    sample_value xor
                                    to_unsigned(
                                        32768,
                                        16
                                    );

                            end if;


                        -------------------------------------------------------
                        -- Reserved mode.
                        -------------------------------------------------------

                        when others =>

                            sample_value :=
                                (others => '0');

                    end case;


                    -----------------------------------------------------------
                    -- Write the current sample to spectrum RAM.
                    -----------------------------------------------------------

                    ram_addr <=
                        std_logic_vector(
                            to_unsigned(
                                pixel_index,
                                ram_addr'length
                            )
                        );

                    ram_data <=
                        std_logic_vector(sample_value);

                    ram_we <= '1';


                    -----------------------------------------------------------
                    -- Advance to the next pixel or finish the frame.
                    -----------------------------------------------------------

                    if pixel_index = PIXEL_COUNT - 1 then

                        capturing <= '0';

                        -- Toggle the completion event for synchronization into
                        -- the system-clock domain.
                        done_toggle_data <=
                            not done_toggle_data;

                    else

                        pixel_index <=
                            pixel_index + 1;

                    end if;

                end if;

            end if;

        end if;
    end process DATA_CAPTURE;

end architecture rtl;
