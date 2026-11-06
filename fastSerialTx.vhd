-- Use IEEE library
library IEEE;
-- Allows use of std_logic
use IEEE.STD_LOGIC_1164.ALL;
-- Allows use of more arithmetic options, and signed and unsigned
use IEEE.NUMERIC_STD.ALL;

-- High-speed UART transmitter.
--
-- Receives parallel 8-bit data bytes and converts them into a UART serial stream 
--Transmission is controlled using a valid/ready handshake
--
-- Used by the binaryReadout module to send spectrometer data to the PC

--                valid
--                  │
--                  ▼

--               IDLE
--                  │
--                  ▼

--            START_BIT
--                  │
--                  ▼

--            DATA_BITS
--           bitIndex=0..7
--                  │
--                  ▼

--          STOP_BITS_STATE
--          stopIndex=0..N
--                  │
--                  ▼

--               IDLE

entity fastSerialTx is
    -- Configuration parameters
    generic (
        -- Defines the UART serial baud rate
        -- Number of clock cycles used to transmit one UART bit
        CLOCKS_PER_BIT : positive := 60;
        -- Defines the number of UART stop bits after every byte
        STOP_BITS      : positive := 1
    );

    port (
        -- Timing reference used by the UART transmitter
        clock : in std_logic;
        -- Resets the UART transmitter and returns it to the idle state
        reset : in std_logic;

        -- 8-bit data byte to be transmitted
        data  : in std_logic_vector(7 downto 0);
        -- Indicates that the input byte is valid and ready for transmission
        valid : in std_logic;

        -- Indicates that the transmitter can accept a new byte
        ready : out std_logic;
        -- UART serial output stream transmitted to the host PC
        tx    : out std_logic
    );
end fastSerialTx;


architecture Behavioral of fastSerialTx is

    -- Defines the UART transmitter states
    -- UART transmitter state machine:
    -- IDLE            : waiting for data
    -- START_BIT       : transmitting start bit
    -- DATA_BITS       : transmitting 8 data bits
    -- STOP_BITS_STATE : transmitting stop bit(s)
    type state_type is (
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BITS_STATE
    );

    -- Stores the current UART state, with starting state given as IDLE
    signal state : state_type := IDLE;

    -- Counts clock cycles within the current UART bit period
    signal clockCount :
        natural range 0 to CLOCKS_PER_BIT - 1 := 0;

    -- Index of the data bit currently being transmitted
    signal bitIndex :
        natural range 0 to 7 := 0;

    -- Counts the number of transmitted stop bits
    signal stopIndex :
        natural range 0 to STOP_BITS - 1 := 0;

    -- Stores the current byte being transmitted
    signal shiftRegister :
        std_logic_vector(7 downto 0) := (others => '0');

    -- Internal UART transmit signal
    -- Remains high when idle
    signal txInternal :
        std_logic := '1';

    -- Internal ready flag indicating whether a new byte can be accepted
    signal readyInternal :
        std_logic := '1';

begin

    tx    <= txInternal;
    ready <= readyInternal;


    TRANSMIT_PROCESS: process(clock)
    begin
        if rising_edge(clock) then

            if reset = '1' then
                state <= IDLE;

                clockCount <= 0;
                bitIndex   <= 0;
                stopIndex  <= 0;

                shiftRegister <= (others => '0');

                txInternal    <= '1';
                readyInternal <= '1';

            else
                case state is

                    -----------------------------------------------------------
                    -- Wait for valid data.
                    --
                    -- A byte is accepted when both ready and valid are high.
                    -----------------------------------------------------------

                    when IDLE =>
                        txInternal    <= '1';
                        readyInternal <= '1';

                        clockCount <= 0;
                        bitIndex   <= 0;
                        stopIndex  <= 0;

                        if valid = '1' then
                            shiftRegister <= data;

                            readyInternal <= '0';
                            state <= START_BIT;
                        end if;


                    -----------------------------------------------------------
                    -- Start bit: logic low for CLOCKS_PER_BIT clock cycles.
                    -----------------------------------------------------------

                    when START_BIT =>
                        txInternal    <= '0';
                        readyInternal <= '0';

                        if clockCount = CLOCKS_PER_BIT - 1 then
                            clockCount <= 0;
                            bitIndex   <= 0;

                            state <= DATA_BITS;
                        else
                            clockCount <= clockCount + 1;
                        end if;


                    -----------------------------------------------------------
                    -- Eight data bits, least-significant bit first.
                    -----------------------------------------------------------

                    when DATA_BITS =>
                        txInternal    <= shiftRegister(bitIndex);
                        readyInternal <= '0';

                        if clockCount = CLOCKS_PER_BIT - 1 then
                            clockCount <= 0;

                            if bitIndex = 7 then
                                stopIndex <= 0;
                                state <= STOP_BITS_STATE;
                            else
                                bitIndex <= bitIndex + 1;
                            end if;
                        else
                            clockCount <= clockCount + 1;
                        end if;


                    -----------------------------------------------------------
                    -- Stop bit or bits: logic high.
                    -----------------------------------------------------------

                    when STOP_BITS_STATE =>
                        txInternal    <= '1';
                        readyInternal <= '0';

                        if clockCount = CLOCKS_PER_BIT - 1 then
                            clockCount <= 0;

                            if stopIndex = STOP_BITS - 1 then
                                readyInternal <= '1';
                                state <= IDLE;
                            else
                                stopIndex <= stopIndex + 1;
                            end if;
                        else
                            clockCount <= clockCount + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end Behavioral;