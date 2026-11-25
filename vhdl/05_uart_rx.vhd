-------------------------------------------------------------------------------
-- FILE: 05_uart_rx.vhd
--
-- PURPOSE:
--   Receive an asynchronous UART serial stream and convert each valid UART
--   character into one parallel eight-bit byte.
--
-- UART CONFIGURATION:
--   - One start bit
--   - Eight data bits
--   - No parity
--   - One stop bit
--   - Least-significant data bit transmitted first
--
-- ROLE IN THE SPECTROMETER FIRMWARE:
--
--   Commands from the Python host follow this path:
--
--       Python command-line software
--                   |
--                   v
--       Cmod A7 USB-UART bridge
--                   |
--                   v
--                RX_USB
--                   |
--                   v
--               uart_rx
--                   |
--                   | data and valid
--                   v
--           command_decoder
--
--   uart_rx handles only the physical UART byte format. It does not interpret
--   the command header, command ID, or command data.
--
--   command_decoder.vhd receives each completed byte and reconstructs the
--   eight-byte command packet:
--
--       EF 00 CMD_H CMD_L DATA_3 DATA_2 DATA_1 DATA_0
--
-- CURRENT CLOCK AND BAUD SETTINGS:
--
--   System clock:
--
--       10 MHz
--
--   UART baud:
--
--       1,000,000 bits per second
--
--   Therefore:
--
--       CLKS_PER_BIT = 10,000,000 / 1,000,000 = 10
--
--   Each UART bit lasts ten system-clock cycles, or one microsecond.
-------------------------------------------------------------------------------

library IEEE;

-- Provides std_logic, std_logic_vector, and rising_edge.
use IEEE.STD_LOGIC_1164.ALL;


-------------------------------------------------------------------------------
-- ENTITY
-------------------------------------------------------------------------------

entity uart_rx is

    generic (

        -----------------------------------------------------------------------
        -- Number of receiver-clock cycles in one UART bit period.
        --
        -- For the current firmware:
        --
        --     clock frequency = 10 MHz
        --     baud rate       = 1 MHz
        --
        --     CLKS_PER_BIT = 10
        --
        -- The generic allows the receiver to be reused with another clock or
        -- baud rate without changing the state machine.
        -----------------------------------------------------------------------

        CLKS_PER_BIT : positive := 10
    );

    port (

        -----------------------------------------------------------------------
        -- Receiver clock.
        --
        -- In spectrometer_top.vhd this is the 10 MHz system clock generated
        -- by the Clocking Wizard.
        -----------------------------------------------------------------------

        clock : in std_logic;

        -----------------------------------------------------------------------
        -- Active-high synchronous reset.
        --
        -- Returns the receiver to IDLE and clears its counters and output.
        -----------------------------------------------------------------------

        reset : in std_logic;

        -----------------------------------------------------------------------
        -- Asynchronous UART serial input.
        --
        -- Connected to RX_USB at the top level.
        --
        -- UART idle level is logic high.
        -----------------------------------------------------------------------

        rx : in std_logic;

        -----------------------------------------------------------------------
        -- Most recently received eight-bit data byte.
        --
        -- This output is updated only after a valid stop bit has been detected.
        -----------------------------------------------------------------------

        data : out std_logic_vector(7 downto 0);

        -----------------------------------------------------------------------
        -- One-clock pulse indicating that data contains a newly received byte.
        --
        -- command_decoder samples data when valid is high.
        -----------------------------------------------------------------------

        valid : out std_logic;

        -----------------------------------------------------------------------
        -- One-clock pulse indicating that the expected stop bit was low.
        --
        -- A low stop bit indicates malformed UART data, incorrect baud timing,
        -- excessive clock mismatch, electrical noise, or loss of framing.
        --
        -- The invalid byte is not presented with valid high.
        -----------------------------------------------------------------------

        framing_error : out std_logic
    );

end entity uart_rx;


-------------------------------------------------------------------------------
-- ARCHITECTURE
-------------------------------------------------------------------------------

architecture rtl of uart_rx is

    ---------------------------------------------------------------------------
    -- UART receiver state machine
    ---------------------------------------------------------------------------

    type state_type is (

        -----------------------------------------------------------------------
        -- Waiting for the serial input to transition from idle high to low.
        -----------------------------------------------------------------------

        IDLE,

        -----------------------------------------------------------------------
        -- Waiting until approximately the middle of the possible start bit,
        -- then verifying that the input is still low.
        -----------------------------------------------------------------------

        START_BIT,

        -----------------------------------------------------------------------
        -- Sampling the eight UART data bits.
        -----------------------------------------------------------------------

        DATA_BITS,

        -----------------------------------------------------------------------
        -- Waiting for and verifying the stop bit.
        -----------------------------------------------------------------------

        STOP_BIT
    );

    signal state :
        state_type := IDLE;


    ---------------------------------------------------------------------------
    -- UART input synchronizer
    --
    -- rx is asynchronous relative to clock. The two-register chain reduces
    -- the probability that metastability propagates into the receiver state
    -- machine.
    --
    -- The state machine uses rx_sync rather than the raw rx input.
    ---------------------------------------------------------------------------

    signal rx_meta :
        std_logic := '1';

    signal rx_sync :
        std_logic := '1';

    ---------------------------------------------------------------------------
    -- Inform Vivado that rx_meta and rx_sync form an asynchronous-input
    -- synchronization chain.
    ---------------------------------------------------------------------------

    attribute ASYNC_REG : string;

    attribute ASYNC_REG of rx_meta :
        signal is "TRUE";

    attribute ASYNC_REG of rx_sync :
        signal is "TRUE";


    ---------------------------------------------------------------------------
    -- Clock-cycle counter within the current UART bit.
    --
    -- The counter counts down to zero. At zero, the state machine samples the
    -- synchronized UART input or advances to the next state.
    ---------------------------------------------------------------------------

    signal clock_count :
        natural range 0 to CLKS_PER_BIT - 1 := 0;


    ---------------------------------------------------------------------------
    -- Index of the UART data bit currently being received.
    --
    -- UART data is sent least-significant bit first:
    --
    --     bit 0, bit 1, ... bit 7
    ---------------------------------------------------------------------------

    signal bit_index :
        natural range 0 to 7 := 0;


    ---------------------------------------------------------------------------
    -- Temporary storage for the eight received data bits.
    ---------------------------------------------------------------------------

    signal shift_register :
        std_logic_vector(7 downto 0) := (others => '0');

begin

    ---------------------------------------------------------------------------
    -- UART RECEIVER PROCESS
    ---------------------------------------------------------------------------

    UART_RECEIVER : process(clock)
    begin

        if rising_edge(clock) then

            -------------------------------------------------------------------
            -- Synchronize the asynchronous UART input.
            --
            -- rx_meta is the first synchronization stage.
            -- rx_sync is the second synchronization stage.
            -------------------------------------------------------------------

            rx_meta <= rx;
            rx_sync <= rx_meta;


            -------------------------------------------------------------------
            -- Pulse outputs default low.
            --
            -- They are asserted only during the specific clock cycle in which
            -- a byte or framing error is completed.
            -------------------------------------------------------------------

            valid         <= '0';
            framing_error <= '0';


            -------------------------------------------------------------------
            -- Synchronous reset
            -------------------------------------------------------------------

            if reset = '1' then

                state <= IDLE;

                clock_count <= 0;

                bit_index <= 0;

                shift_register <=
                    (others => '0');

                data <=
                    (others => '0');


            -------------------------------------------------------------------
            -- Normal UART reception
            -------------------------------------------------------------------

            else

                case state is

                    -----------------------------------------------------------
                    -- IDLE
                    --
                    -- UART is normally high while idle.
                    --
                    -- A low level may indicate the beginning of a start bit.
                    -- The receiver waits approximately half of one bit period
                    -- before checking the start bit again.
                    -----------------------------------------------------------

                    when IDLE =>

                        if rx_sync = '0' then

                            clock_count <=
                                CLKS_PER_BIT / 2;

                            state <= START_BIT;

                        end if;


                    -----------------------------------------------------------
                    -- START_BIT
                    --
                    -- Verify the serial input near the centre of the possible
                    -- start bit.
                    --
                    -- If the input has returned high, the low transition was
                    -- probably noise or a short glitch, so return to IDLE.
                    -----------------------------------------------------------

                    when START_BIT =>

                        if clock_count = 0 then

                            if rx_sync = '0' then

                                clock_count <=
                                    CLKS_PER_BIT - 1;

                                bit_index <= 0;

                                state <= DATA_BITS;

                            else

                                state <= IDLE;

                            end if;

                        else

                            clock_count <=
                                clock_count - 1;

                        end if;


                    -----------------------------------------------------------
                    -- DATA_BITS
                    --
                    -- Sample one data bit after each complete UART bit period.
                    --
                    -- The first received bit is stored in bit zero because UART
                    -- transmits data least-significant bit first.
                    -----------------------------------------------------------

                    when DATA_BITS =>

                        if clock_count = 0 then

                            shift_register(bit_index) <=
                                rx_sync;

                            clock_count <=
                                CLKS_PER_BIT - 1;

                            if bit_index = 7 then

                                state <= STOP_BIT;

                            else

                                bit_index <=
                                    bit_index + 1;

                            end if;

                        else

                            clock_count <=
                                clock_count - 1;

                        end if;


                    -----------------------------------------------------------
                    -- STOP_BIT
                    --
                    -- A valid UART stop bit must be high.
                    --
                    -- If the stop bit is high:
                    --   - copy the completed byte to data;
                    --   - pulse valid for one clock.
                    --
                    -- If the stop bit is low:
                    --   - pulse framing_error;
                    --   - do not pulse valid.
                    -----------------------------------------------------------

                    when STOP_BIT =>

                        if clock_count = 0 then

                            if rx_sync = '1' then

                                data <=
                                    shift_register;

                                valid <= '1';

                            else

                                framing_error <= '1';

                            end if;

                            state <= IDLE;

                        else

                            clock_count <=
                                clock_count - 1;

                        end if;

                end case;

            end if;

        end if;

    end process UART_RECEIVER;

end architecture rtl;
