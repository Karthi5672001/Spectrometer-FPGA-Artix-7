-------------------------------------------------------------------------------
-- FILE: 11_spectrometer_top.vhd
--
-- PURPOSE:
--   Top-level module for the Artix-7 spectrometer firmware.
--
-- ROLE IN THE FIRMWARE:
--
--   This module connects all major firmware blocks:
--
--       12 MHz board clock
--               |
--               v
--       Clocking Wizard
--          |          |
--       10 MHz      60 MHz
--          |          |
--          |          +--> Frame transmitter
--          |          +--> Spectrum UART transmitter
--          |          +--> Spectrum RAM read port
--          |
--          +--> Command UART receiver
--          +--> Command decoder
--          +--> Command controller
--          +--> Acquisition scheduler
--          +--> Detector integration controller
--
--   The complete signal path is:
--
--       Python command
--           |
--           v
--       RX_USB
--           |
--           v
--       uart_rx
--           |
--           v
--       command_decoder
--           |
--           v
--       command_controller
--           |
--           v
--       acquisition scheduler
--           |
--           v
--       detector_capture
--           |
--           v
--       dual-port spectrum RAM
--           |
--           v
--       frame_transmitter
--           |
--           v
--       uart_tx
--           |
--           v
--       TX_USB
--           |
--           v
--       Python frame decoder
--
-- CLOCK DOMAINS:
--
--   sys_clk:
--       10 MHz command, scheduling, and detector-control clock.
--
--   fast_clk:
--       60 MHz spectrum-RAM read and UART-transmission clock.
--
--   GPIO36:
--       External 5 MHz detector/data clock used for ADC capture and RAM writes.
--
-- RESET:
--
--   Reset is asserted while the Clocking Wizard is not locked:
--
--       pll_reset <= not pll_locked;
--
--   reset_sync creates a separately synchronized reset for the 10 MHz and
--   60 MHz domains.
--
-- FRAME RATE:
--
--   The scheduler uses TARGET_FRAME_PERIOD_CYCLES to limit acquisition starts
--   to a nominal maximum of 50 spectra per second.
--
-- UART HANDSHAKE:
--
--   frame_tx_ready prevents frame_transmitter from advancing twice before
--   uart_tx registers the current byte:
--
--       frame_tx_ready <= tx_ready and not tx_valid;
--
--   This correction prevents the alternate-byte loss observed in laboratory
--   testing.
-------------------------------------------------------------------------------

library IEEE;

use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hardware_config.all;
use work.protocol_types.all;


-------------------------------------------------------------------------------
-- ENTITY
-------------------------------------------------------------------------------

entity spectrometer_top is
    port (
        -----------------------------------------------------------------------
        -- Board clock and USB-UART input
        -----------------------------------------------------------------------

        -- Cmod A7 12 MHz onboard oscillator.
        GCLK : in std_logic;

        -- Serial command input from the USB-UART bridge.
        RX_USB : in std_logic;

        -- Serial spectrum output toward the USB-UART bridge.
        TX_USB : out std_logic;


        -----------------------------------------------------------------------
        -- ADC and spectrometer outputs
        -----------------------------------------------------------------------

        -- Clock forwarded to the external ADC.
        GPIO1 : out std_logic;

        -- Spectrometer integration/start signal.
        GPIO21 : out std_logic;

        -- Nominal 5 MHz spectrometer clock.
        GPIO22 : out std_logic;


        -----------------------------------------------------------------------
        -- Twelve-bit ADC input
        --
        -- GPIO3 is ADC bit zero.
        -- GPIO14 is ADC bit eleven.
        -----------------------------------------------------------------------

        GPIO3  : in std_logic;
        GPIO4  : in std_logic;
        GPIO5  : in std_logic;
        GPIO6  : in std_logic;
        GPIO7  : in std_logic;
        GPIO8  : in std_logic;
        GPIO9  : in std_logic;
        GPIO10 : in std_logic;
        GPIO11 : in std_logic;
        GPIO12 : in std_logic;
        GPIO13 : in std_logic;
        GPIO14 : in std_logic;


        -----------------------------------------------------------------------
        -- Returned detector/data clock
        -----------------------------------------------------------------------

        GPIO36 : in std_logic;


        -----------------------------------------------------------------------
        -- Diagnostic LEDs
        -----------------------------------------------------------------------

        LD0_R : out std_logic;
        LD0_G : out std_logic;
        LD0_B : out std_logic;

        LD1 : out std_logic;
        LD2 : out std_logic
    );
end entity spectrometer_top;


-------------------------------------------------------------------------------
-- ARCHITECTURE
-------------------------------------------------------------------------------

architecture rtl of spectrometer_top is

    ---------------------------------------------------------------------------
    -- Vivado Clocking Wizard
    --
    -- Expected configuration:
    --
    --   Input:
    --       12 MHz
    --
    --   Outputs:
    --       clk_out1 = 10 MHz
    --       clk_out2 = 60 MHz
    --
    --   locked output enabled
    ---------------------------------------------------------------------------

    component pll is
        port (
            clk_out1 : out std_logic;
            clk_out2 : out std_logic;
            locked   : out std_logic;
            reset    : in  std_logic;
            clk_in1  : in  std_logic
        );
    end component;


    ---------------------------------------------------------------------------
    -- Vivado Block Memory Generator
    --
    -- Expected configuration:
    --
    --   True dual-port RAM
    --   512 addresses
    --   16 bits per address
    --   Independent clocks
    --
    -- Port A:
    --   Written from the external GPIO36 data-clock domain.
    --
    -- Port B:
    --   Read from the 60 MHz fast-clock domain.
    ---------------------------------------------------------------------------

    component blk_mem_gen_0 is
        port (
            clka  : in  std_logic;
            ena   : in  std_logic;
            wea   : in  std_logic_vector(0 downto 0);
            addra : in  std_logic_vector(8 downto 0);
            dina  : in  std_logic_vector(15 downto 0);
            douta : out std_logic_vector(15 downto 0);

            clkb  : in  std_logic;
            enb   : in  std_logic;
            web   : in  std_logic_vector(0 downto 0);
            addrb : in  std_logic_vector(8 downto 0);
            dinb  : in  std_logic_vector(15 downto 0);
            doutb : out std_logic_vector(15 downto 0)
        );
    end component;


    ---------------------------------------------------------------------------
    -- Clock and reset signals
    ---------------------------------------------------------------------------

    signal sys_clk :
        std_logic;

    signal fast_clk :
        std_logic;

    signal pll_locked :
        std_logic;

    signal pll_reset :
        std_logic;

    signal sys_reset :
        std_logic;

    signal fast_reset :
        std_logic;


    ---------------------------------------------------------------------------
    -- Command UART signals
    ---------------------------------------------------------------------------

    signal rx_byte :
        std_logic_vector(7 downto 0);

    signal rx_valid :
        std_logic;

    signal rx_error :
        std_logic;

    signal command :
        command_type;


    ---------------------------------------------------------------------------
    -- Command-controller outputs
    ---------------------------------------------------------------------------

    signal run_enable :
        std_logic;

    signal single_request :
        std_logic;

    signal command_pulse :
        std_logic;

    signal integration_counts :
        unsigned(31 downto 0);

    signal command_count :
        unsigned(31 downto 0);

    signal test_mode :
        std_logic_vector(1 downto 0);


    ---------------------------------------------------------------------------
    -- Per-frame metadata snapshots
    --
    -- These registers are captured after detector storage completes. They are
    -- then held stable while the 60 MHz frame transmitter reads them.
    ---------------------------------------------------------------------------

    signal frame_integration_counts :
        unsigned(31 downto 0) := (others => '0');

    signal frame_command_count :
        unsigned(31 downto 0) := (others => '0');


    ---------------------------------------------------------------------------
    -- Acquisition control and status
    ---------------------------------------------------------------------------

    signal capture_start :
        std_logic := '0';

    signal capture_busy :
        std_logic;

    signal capture_done :
        std_logic;

    -- Latches a one-spectrum request until it can be serviced.
    signal single_pending :
        std_logic := '0';


    ---------------------------------------------------------------------------
    -- Frame-transmitter control and status
    ---------------------------------------------------------------------------

    signal frame_start :
        std_logic := '0';

    signal frame_busy :
        std_logic;

    signal frame_done :
        std_logic;


    ---------------------------------------------------------------------------
    -- Frame-request CDC: sys_clk to fast_clk
    ---------------------------------------------------------------------------

    signal frame_request_toggle_sys :
        std_logic := '0';

    signal frame_request_meta :
        std_logic := '0';

    signal frame_request_sync :
        std_logic := '0';

    signal frame_request_previous :
        std_logic := '0';


    ---------------------------------------------------------------------------
    -- Frame-busy CDC: fast_clk to sys_clk
    ---------------------------------------------------------------------------

    signal frame_busy_meta :
        std_logic := '0';

    signal frame_busy_sys :
        std_logic := '0';


    ---------------------------------------------------------------------------
    -- Frame-rate scheduler
    ---------------------------------------------------------------------------

    signal frame_period :
        natural range 0 to TARGET_FRAME_PERIOD_CYCLES := 0;


    ---------------------------------------------------------------------------
    -- ADC and spectrum RAM signals
    ---------------------------------------------------------------------------

    signal adc_bus :
        std_logic_vector(11 downto 0);

    signal ram_write_enable :
        std_logic;

    signal ram_write_enable_vector :
        std_logic_vector(0 downto 0);

    signal ram_write_address :
        std_logic_vector(8 downto 0);

    signal ram_read_address :
        std_logic_vector(8 downto 0);

    signal ram_write_data :
        std_logic_vector(15 downto 0);

    signal ram_read_data :
        std_logic_vector(15 downto 0);


    ---------------------------------------------------------------------------
    -- Fast UART byte interface
    ---------------------------------------------------------------------------

    signal tx_byte :
        std_logic_vector(7 downto 0);

    signal tx_valid :
        std_logic;

    -- Raw ready signal produced by uart_tx.
    signal tx_ready :
        std_logic;

    -- Gated ready signal presented to frame_transmitter.
    signal frame_tx_ready :
        std_logic;


    ---------------------------------------------------------------------------
    -- Vivado CDC attributes
    ---------------------------------------------------------------------------

    attribute ASYNC_REG : string;

    attribute ASYNC_REG of frame_request_meta :
        signal is "TRUE";

    attribute ASYNC_REG of frame_request_sync :
        signal is "TRUE";

    attribute ASYNC_REG of frame_busy_meta :
        signal is "TRUE";

    attribute ASYNC_REG of frame_busy_sys :
        signal is "TRUE";

begin

    ---------------------------------------------------------------------------
    -- Static conversions and control signals
    ---------------------------------------------------------------------------

    -- Prevent the frame transmitter from issuing another byte during the clock
    -- cycle in which uart_tx accepts the current tx_valid byte.
    frame_tx_ready <=
        tx_ready and not tx_valid;

    -- Hold both internal clock domains in reset while the MMCM is unlocked.
    pll_reset <=
        not pll_locked;

    -- Convert the scalar RAM write-enable into the one-bit vector expected by
    -- the Block Memory Generator.
    ram_write_enable_vector(0) <=
        ram_write_enable;


    ---------------------------------------------------------------------------
    -- Clock generation
    ---------------------------------------------------------------------------

    U_PLL : pll
        port map (
            clk_out1 => sys_clk,
            clk_out2 => fast_clk,
            locked   => pll_locked,
            reset    => '0',
            clk_in1  => GCLK
        );


    ---------------------------------------------------------------------------
    -- Reset synchronization
    ---------------------------------------------------------------------------

    U_SYS_RESET : entity work.reset_sync
        port map (
            clock       => sys_clk,
            async_reset => pll_reset,
            reset_out   => sys_reset
        );

    U_FAST_RESET : entity work.reset_sync
        port map (
            clock       => fast_clk,
            async_reset => pll_reset,
            reset_out   => fast_reset
        );


    ---------------------------------------------------------------------------
    -- Command UART receiver
    ---------------------------------------------------------------------------

    U_UART_RX : entity work.uart_rx
        generic map (
            CLKS_PER_BIT => COMMAND_CLKS_PER_BIT
        )
        port map (
            clock         => sys_clk,
            reset         => sys_reset,
            rx            => RX_USB,
            data          => rx_byte,
            valid         => rx_valid,
            framing_error => rx_error
        );


    ---------------------------------------------------------------------------
    -- Eight-byte command-packet decoder
    ---------------------------------------------------------------------------

    U_COMMAND_DECODER : entity work.command_decoder
        port map (
            clock       => sys_clk,
            reset       => sys_reset,
            byte_in     => rx_byte,
            byte_valid  => rx_valid,
            command_out => command
        );


    ---------------------------------------------------------------------------
    -- Command interpreter and stored configuration
    ---------------------------------------------------------------------------

    U_COMMAND_CONTROLLER : entity work.command_controller
        port map (
            clock              => sys_clk,
            reset              => sys_reset,
            command_in         => command,
            run_enable         => run_enable,
            single_request     => single_request,
            integration_counts => integration_counts,
            test_mode          => test_mode,
            accepted_count     => command_count,
            command_pulse      => command_pulse
        );


    ---------------------------------------------------------------------------
    -- Assemble the twelve-bit ADC input bus
    --
    -- GPIO3 is bit zero and GPIO14 is bit eleven.
    ---------------------------------------------------------------------------

    adc_bus <=
        GPIO14 &
        GPIO13 &
        GPIO12 &
        GPIO11 &
        GPIO10 &
        GPIO9  &
        GPIO8  &
        GPIO7  &
        GPIO6  &
        GPIO5  &
        GPIO4  &
        GPIO3;


    ---------------------------------------------------------------------------
    -- Detector integration and data capture
    ---------------------------------------------------------------------------

    U_DETECTOR_CAPTURE : entity work.detector_capture
        port map (
            sys_clock         => sys_clk,
            sys_reset         => sys_reset,
            start             => capture_start,
            integration_counts => integration_counts,

            data_clock        => GPIO36,
            adc_data          => adc_bus,
            test_mode         => test_mode,

            dev_clock         => GPIO22,
            dev_start         => GPIO21,
            adc_clock         => GPIO1,

            busy              => capture_busy,
            done_pulse        => capture_done,

            ram_we            => ram_write_enable,
            ram_addr          => ram_write_address,
            ram_data          => ram_write_data
        );


    ---------------------------------------------------------------------------
    -- Dual-port spectrum RAM
    ---------------------------------------------------------------------------

    U_SPECTRUM_RAM : blk_mem_gen_0
        port map (
            -------------------------------------------------------------------
            -- Port A: detector/data-clock write side
            -------------------------------------------------------------------

            clka  => GPIO36,
            ena   => '1',
            wea   => ram_write_enable_vector,
            addra => ram_write_address,
            dina  => ram_write_data,
            douta => open,

            -------------------------------------------------------------------
            -- Port B: fast-clock read side
            -------------------------------------------------------------------

            clkb  => fast_clk,
            enb   => '1',
            web   => "0",
            addrb => ram_read_address,
            dinb  => x"0000",
            doutb => ram_read_data
        );


    ---------------------------------------------------------------------------
    -- Binary spectrum-frame generator
    ---------------------------------------------------------------------------

    U_FRAME_TRANSMITTER : entity work.frame_transmitter
        port map (
            clock              => fast_clk,
            reset              => fast_reset,
            start              => frame_start,

            integration_counts => frame_integration_counts,
            command_count      => frame_command_count,

            busy               => frame_busy,
            done_pulse         => frame_done,

            ram_addr           => ram_read_address,
            ram_data           => ram_read_data,

            tx_data            => tx_byte,
            tx_valid           => tx_valid,

            -- Use the gated handshake, not raw tx_ready.
            tx_ready           => frame_tx_ready
        );


    ---------------------------------------------------------------------------
    -- 1 Mbaud spectrum UART transmitter
    ---------------------------------------------------------------------------

    U_UART_TX : entity work.uart_tx
        generic map (
            CLKS_PER_BIT => FAST_CLKS_PER_BIT
        )
        port map (
            clock => fast_clk,
            reset => fast_reset,
            data  => tx_byte,
            valid => tx_valid,
            ready => tx_ready,
            tx    => TX_USB
        );


    ---------------------------------------------------------------------------
    -- Acquisition scheduler
    --
    -- A new acquisition may begin only when:
    --
    --   - continuous acquisition is enabled or a single request is pending;
    --   - detector capture is idle;
    --   - frame transmission is idle;
    --   - the target frame period has elapsed.
    --
    -- This design intentionally avoids overlapping detector capture and frame
    -- transmission, simplifying RAM ownership and CDC behavior.
    ---------------------------------------------------------------------------

    ACQUISITION_SCHEDULER : process(sys_clk)
    begin
        if rising_edge(sys_clk) then

            -------------------------------------------------------------------
            -- capture_start is a one-system-clock pulse.
            -------------------------------------------------------------------

            capture_start <= '0';


            -------------------------------------------------------------------
            -- Synchronize frame-transmitter busy into sys_clk.
            -------------------------------------------------------------------

            frame_busy_meta <=
                frame_busy;

            frame_busy_sys <=
                frame_busy_meta;


            -------------------------------------------------------------------
            -- Reset scheduler state
            -------------------------------------------------------------------

            if sys_reset = '1' then

                -- Allow the first commanded acquisition to begin immediately.
                frame_period <=
                    TARGET_FRAME_PERIOD_CYCLES;

                frame_request_toggle_sys <=
                    '0';

                single_pending <=
                    '0';

                frame_integration_counts <=
                    us_to_counts(DEFAULT_INTEGRATION_US);

                frame_command_count <=
                    (others => '0');


            -------------------------------------------------------------------
            -- Normal scheduling
            -------------------------------------------------------------------

            else

                ---------------------------------------------------------------
                -- Latch a one-frame request until it can be serviced.
                ---------------------------------------------------------------

                if single_request = '1' then

                    single_pending <= '1';

                end if;


                ---------------------------------------------------------------
                -- Count toward the target 20 ms acquisition-start interval.
                ---------------------------------------------------------------

                if frame_period < TARGET_FRAME_PERIOD_CYCLES then

                    frame_period <=
                        frame_period + 1;

                end if;


                ---------------------------------------------------------------
                -- Start a new acquisition when all conditions are satisfied.
                ---------------------------------------------------------------

                if
                    (
                        run_enable = '1' or
                        single_pending = '1'
                    ) and
                    capture_busy = '0' and
                    frame_busy_sys = '0' and
                    frame_period >= TARGET_FRAME_PERIOD_CYCLES
                then

                    capture_start <= '1';

                    frame_period <= 0;

                    single_pending <= '0';

                end if;


                ---------------------------------------------------------------
                -- Detector capture completed.
                --
                -- Snapshot metadata before toggling the frame request. The
                -- multi-bit values remain stable while the event crosses into
                -- the fast-clock domain and throughout transmission.
                ---------------------------------------------------------------

                if capture_done = '1' then

                    frame_integration_counts <=
                        integration_counts;

                    frame_command_count <=
                        command_count;

                    frame_request_toggle_sys <=
                        not frame_request_toggle_sys;

                end if;

            end if;

        end if;
    end process ACQUISITION_SCHEDULER;


    ---------------------------------------------------------------------------
    -- Transfer completed-frame event into the fast-clock domain.
    --
    -- A toggle is used because a one-clock sys_clk pulse could otherwise be
    -- missed by the fast-clock state machine.
    ---------------------------------------------------------------------------

    FRAME_REQUEST_CDC : process(fast_clk)
    begin
        if rising_edge(fast_clk) then

            -- frame_start is a one-fast-clock pulse.
            frame_start <= '0';

            if fast_reset = '1' then

                frame_request_meta <=
                    '0';

                frame_request_sync <=
                    '0';

                frame_request_previous <=
                    '0';

            else

                frame_request_meta <=
                    frame_request_toggle_sys;

                frame_request_sync <=
                    frame_request_meta;

                frame_request_previous <=
                    frame_request_sync;

                if
                    frame_request_sync /=
                    frame_request_previous
                then

                    frame_start <= '1';

                end if;

            end if;

        end if;
    end process FRAME_REQUEST_CDC;


    ---------------------------------------------------------------------------
    -- Diagnostic LEDs
    ---------------------------------------------------------------------------

    -- Red output currently follows "PLL not locked".
    LD0_R <=
        not pll_locked;

    -- Green output indicates continuous acquisition enable.
    LD0_G <=
        not run_enable;

    -- Blue output indicates active frame transmission.
    LD0_B <=
        not frame_busy;

    -- Brief pulse when a supported command is accepted.
    LD1 <=
        command_pulse;

    -- High while detector integration/capture is active.
    LD2 <=
        capture_busy;

end architecture rtl;
