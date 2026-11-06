-- Use IEEE library
library IEEE;
-- Allows use of std_logic
use IEEE.STD_LOGIC_1164.ALL;
-- Import everything from the package named defs; imports all the constants, records, functions and types defined there
use work.defs.all;

-- Defines the interface between the UART communication block and the rest of the FPGA.
entity serialComms is
    port (
        -- System clock used internally by the UART logic
        clock:    in  std_logic;
        -- Resets the UART receiver/transmitter and command parser
        reset:    in  std_logic;
        -- UART transmit pin for serial output
        txSerial: out std_logic;
        -- Incoming UART signal serial input
        rxSerial: in  std_logic;
        -- Transmit data byte
        txData:   in  std_logic_vector(7 downto 0);
        -- Indicates that txData contains a valid byte that should be transmitted
        txValid:  in  std_logic;
        -- Busy flag from the transmitter
        txWait:   out std_logic;
        -- Received Command
        rxCmd:    out cmd_type
    );
end serialComms;

-- Data Flow
--
-- Receive Path:
--     rxSerial
--         ↓
--       uart
--         ↓
--   rxData/rxValid
--         ↓
--     rxCommand
--         ↓
--       rxCmd
--
-- Transmit Path:
--      txData
--         ↓
--    serialTxFifo
--         ↓
--       uart
--         ↓
--     txSerial

architecture Behavioral of serialComms is

-- Indicates that the UART transmitter can accept a new byte
signal txReady:      std_logic;
-- Requests a byte from the transmit FIFO
signal readEnable:   std_logic := '0';
-- Indicates that the transmit FIFO contains no data
signal empty:        std_logic;

-- Byte read from the transmit FIFO and supplied to the UART
signal fifoDataOut:  std_logic_vector(7 downto 0);
-- Valid pulse indicating that fifoDataOut contains a byte to send
signal fifoValidOut: std_logic := '0';

-- Byte received by the UART receiver
signal rxData:       std_logic_vector(7 downto 0);
-- Valid pulse indicating that rxData contains a newly received byte
signal rxValid:      std_logic;

begin

-- Command frame decoder
-- Converts incoming UART bytes into structured command packets
RX_CMD: rxCommand
    port map (
        -- System clock used by the command decoder
        clock     => clock,
        -- Received UART byte stream
        din       => rxData,
        -- Indicates when a new UART byte is available
        din_valid => rxValid,
        -- Decoded command output for commandHandler
        cmd       => rxCmd
    );

-- Transmit control state machine
-- Moves bytes from the FIFO into the UART whenever data is available and the UART transmitter is ready
UART_CTRL: process(clock)
    -- Transmit state machine:
    -- 0 = Initialize
    -- 1 = Wait for FIFO data
    -- 2 = Wait for UART ready
    -- 3 = Read byte from FIFO
    -- 4 = Complete transfer
    variable state: natural range 0 to 4 := 0;
begin
    if rising_edge(clock) then
        -- Return transmitter control logic to its idle state
        if reset = '1' then
            state        := 0;
            readEnable   <= '0';
            -- FIFO output becomes valid one clock cycle after rd_en is asserted
            fifoValidOut <= '0';

        else
            -- fifoValidOut is asserted one cycle after readEnable.
            fifoValidOut <= readEnable;

            case state is
                -- Initialization state
                when 0 =>
                    readEnable <= '0';
                    state := 1;

                -- Wait until data is available in the transmit FIFO
                when 1 =>
                    readEnable <= '0';

                    if empty = '0' then
                        state := 2;
                    end if;

                -- Wait for the UART transmitter to become ready
                when 2 =>
                    if txReady = '1' then
                        state := 3;
                    end if;

                -- Request one byte from the transmit FIFO
                when 3 =>
                    readEnable <= '1';
                    state := 4;

                -- Return to FIFO monitoring state
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

-- UART transceiver
-- Handles serial transmission and reception of bytes
COMMS: uart
    -- 8-bit data
    -- 1 stop bit
    -- Baud rate determined by SERIAL_CLK_DIV
    generic map (
        data_len  => 8,
        stop_bits => 1,
        clk_div   => SERIAL_CLK_DIV
    )
    port map (
        clock   => clock,
        reset   => reset,
        -- Byte currently being transmitted
        txData  => fifoDataOut,
        -- Indicates that fifoDataOut contains a valid byte
        txValid => fifoValidOut,
        -- UART transmitter ready for another byte
        txReady => txReady,
        -- Physical UART transmit pin
        txOut   => txSerial,
        -- Received UART byte
        rxData  => rxData,
        -- Indicates a newly received UART byte
        rxValid => rxValid,
        -- Receive errors are ignored
        rxError => open,
        -- Physical UART receive pin
        rxIn    => rxSerial
    );

-- Transmit FIFO buffer
-- Decouples user transmit requests from UART transmission timing
TX_FIFO: serialTxFifo
    port map (
        clk       => clock,
        srst      => reset,
        -- Byte supplied by the user for transmission
        din       => txData,
        -- Store a byte in the FIFO
        wr_en     => txValid,
        -- Remove a byte from the FIFO for transmission
        rd_en     => readEnable,
        -- Byte currently being supplied to the UART
        dout      => fifoDataOut,
        full      => open,
        -- Indicates that no transmit data is buffered
        empty     => empty,
        -- Asserted when FIFO occupancy exceeds the programmable threshold
        -- Used by external logic as a transmit busy/backpressure signal
        prog_full => txWait
    );


end Behavioral;