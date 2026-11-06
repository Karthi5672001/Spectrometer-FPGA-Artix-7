-- Use IEEE library
library IEEE;
-- Allows use of std_logic
use IEEE.STD_LOGIC_1164.ALL;
-- Allows use of more arithmetic options, and signed and unsigned
use IEEE.NUMERIC_STD.ALL;
-- Import everything from the package named defs; imports all the constants, records, functions and types defined there
use work.defs.all; 

-- Generates a binary spectrum frame from BRAM data and streams it to the UART transmitter
entity binaryReadout is
    port (
        -----------------------------------------------------------------------
        -- Control
        -----------------------------------------------------------------------

        -- Fast-clock domain used for readout and transmission
        clock : in std_logic;
        -- Returns the frame generator to its idle state
        reset : in std_logic;
        -- Pulse indicating that a newly captured spectrum is ready
        trig  : in std_logic;

        -- Integration time associated with the current spectrum
        -- Included in the transmitted metadata
        integrationTime : in natural;


        -----------------------------------------------------------------------
        -- Byte-transmitter interface
        -----------------------------------------------------------------------

        -- Byte currently being transmitted
        txByte  : out std_logic_vector(7 downto 0);
        -- Pulse requesting transmission of txByte
        txValid : out std_logic;
        -- UART busy indicator
        -- Transmission pauses until txWait returns low
        txWait  : in  std_logic;


        -----------------------------------------------------------------------
        -- Status and spectrum-RAM interface
        -----------------------------------------------------------------------

        -- Indicates whether frame generation is complete
        done : out std_logic;

        -- Address of the spectrum sample being read
        addr : out std_logic_vector(8 downto 0);
        -- Pixel value returned by the spectrum RAM
        data : in  std_logic_vector(15 downto 0)
    );
end entity binaryReadout;


architecture Behavioral of binaryReadout is

    ---------------------------------------------------------------------------
    -- State machine
    ---------------------------------------------------------------------------

    type state_type is (
        IDLE,
        SEND_METADATA,
        SET_PIXEL_ADDRESS,
        WAIT_FOR_RAM,
        LATCH_PIXEL,
        SEND_PIXEL_HIGH,
        SEND_PIXEL_LOW,
        SEND_CRC_HIGH,
        SEND_CRC_LOW
    );

    signal state :
        state_type := IDLE;


    ---------------------------------------------------------------------------
    -- Frame state
    ---------------------------------------------------------------------------

    signal frameSequence :
        unsigned(31 downto 0) := (others => '0');

    signal capturedIntegrationTime :
        unsigned(31 downto 0) := (others => '0');

    signal crc :
        unsigned(15 downto 0) := CRC16_INITIAL;


    ---------------------------------------------------------------------------
    -- Metadata state
    --
    -- There are 18 metadata bytes, with valid indices 0 through 17.
    --
    -- The earlier range of 0 through 13 prevented metadataIndex from reaching
    -- 17. That made the pixel-read state transition unreachable during
    -- synthesis and allowed Vivado to remove the RAM Port-B read path.
    ---------------------------------------------------------------------------

    signal metadataIndex :
        natural range 0 to 17 := 0;


    ---------------------------------------------------------------------------
    -- Pixel state
    ---------------------------------------------------------------------------

    signal pixelIndex :
        natural range 0 to DATA_LEN - 1 := 0;

    signal pixelWord :
        std_logic_vector(15 downto 0) := (others => '0');


    ---------------------------------------------------------------------------
    -- CRC-16/CCITT-FALSE
    --
    -- Polynomial: 0x1021
    -- Initial:    0xFFFF
    -- Reflect:    false
    -- Final XOR:  0x0000
    ---------------------------------------------------------------------------

    function crc16Next (
        currentCrc : unsigned(15 downto 0);
        nextByte   : std_logic_vector(7 downto 0)
    ) return unsigned is

        variable result :
            unsigned(15 downto 0);

    begin
        result :=
            currentCrc xor
            shift_left(
                resize(
                    unsigned(nextByte),
                    16
                ),
                8
            );

        for bitNumber in 0 to 7 loop
            if result(15) = '1' then
                result :=
                    shift_left(result, 1) xor
                    CRC16_POLYNOMIAL;
            else
                result :=
                    shift_left(result, 1);
            end if;
        end loop;

        return result;
    end function;


    ---------------------------------------------------------------------------
    -- Frame metadata
    --
    -- Index  Byte
    -- -----  ---------------------------------------------------------------
    -- 0      Sync 0
    -- 1      Sync 1
    -- 2      Sync 2
    -- 3      Sync 3
    -- 4      Protocol version
    -- 5      Status
    -- 6      Remaining frame length, high byte
    -- 7      Remaining frame length, low byte
    -- 8      Frame sequence [31:24]
    -- 9      Frame sequence [23:16]
    -- 10     Frame sequence [15:8]
    -- 11     Frame sequence [7:0]
    -- 12     Integration count [31:24]
    -- 13     Integration count [23:16]
    -- 14     Integration count [15:8]
    -- 15     Integration count [7:0]
    -- 16     Pixel count high byte
    -- 17     Pixel count low byte
    --
    -- Complete frame:
    --
    --   Metadata:         18 bytes
    --   Pixel payload:   576 bytes
    --   CRC:               2 bytes
    --   Total:           596 bytes
    ---------------------------------------------------------------------------

    function metadataByte (
        indexValue     : natural;
        sequenceValue  : unsigned(31 downto 0);
        integrationVal : unsigned(31 downto 0)
    ) return std_logic_vector is

        constant remainingLength :
            unsigned(15 downto 0) :=
                to_unsigned(
                    BINARY_REMAINING_BYTES,
                    16
                );

        constant pixelCount :
            unsigned(15 downto 0) :=
                to_unsigned(
                    DATA_LEN,
                    16
                );

    begin
        case indexValue is

            when 0 =>
                return BINARY_SYNC_0;

            when 1 =>
                return BINARY_SYNC_1;

            when 2 =>
                return BINARY_SYNC_2;

            when 3 =>
                return BINARY_SYNC_3;

            when 4 =>
                return BINARY_PROTOCOL_VERSION;

            when 5 =>
                return BINARY_STATUS_OK;

            when 6 =>
                return std_logic_vector(
                    remainingLength(15 downto 8)
                );

            when 7 =>
                return std_logic_vector(
                    remainingLength(7 downto 0)
                );

            when 8 =>
                return std_logic_vector(
                    sequenceValue(31 downto 24)
                );

            when 9 =>
                return std_logic_vector(
                    sequenceValue(23 downto 16)
                );

            when 10 =>
                return std_logic_vector(
                    sequenceValue(15 downto 8)
                );

            when 11 =>
                return std_logic_vector(
                    sequenceValue(7 downto 0)
                );

            when 12 =>
                return std_logic_vector(
                    integrationVal(31 downto 24)
                );

            when 13 =>
                return std_logic_vector(
                    integrationVal(23 downto 16)
                );

            when 14 =>
                return std_logic_vector(
                    integrationVal(15 downto 8)
                );

            when 15 =>
                return std_logic_vector(
                    integrationVal(7 downto 0)
                );

            when 16 =>
                return std_logic_vector(
                    pixelCount(15 downto 8)
                );

            when 17 =>
                return std_logic_vector(
                    pixelCount(7 downto 0)
                );

            when others =>
                return x"00";

        end case;
    end function;


begin

    ---------------------------------------------------------------------------
    -- Binary frame generator
    ---------------------------------------------------------------------------

    BINARY_READOUT_PROCESS: process(clock)

        variable nextByte :
            std_logic_vector(7 downto 0);

    begin
        if rising_edge(clock) then

            -------------------------------------------------------------------
            -- Default transmitter write-enable
            -------------------------------------------------------------------

            txValid <= '0';


            -------------------------------------------------------------------
            -- Synchronous reset
            -------------------------------------------------------------------

            if reset = '1' then
                state <=
                    IDLE;

                txByte <=
                    (others => '0');

                txValid <=
                    '0';

                done <=
                    '1';

                addr <=
                    (others => '0');

                frameSequence <=
                    (others => '0');

                capturedIntegrationTime <=
                    (others => '0');

                crc <=
                    CRC16_INITIAL;

                metadataIndex <=
                    0;

                pixelIndex <=
                    0;

                pixelWord <=
                    (others => '0');


            -------------------------------------------------------------------
            -- Normal operation
            -------------------------------------------------------------------

            else
                case state is

                    -----------------------------------------------------------
                    -- Wait for an acquisition-complete trigger
                    -----------------------------------------------------------

                    when IDLE =>
                        done <=
                            '1';

                        addr <=
                            (others => '0');

                        if trig = '1' then
                            done <=
                                '0';

                            capturedIntegrationTime <=
                                to_unsigned(
                                    integrationTime,
                                    capturedIntegrationTime'length
                                );

                            metadataIndex <=
                                0;

                            pixelIndex <=
                                0;

                            crc <=
                                CRC16_INITIAL;

                            state <=
                                SEND_METADATA;
                        end if;


                    -----------------------------------------------------------
                    -- Send sync marker and metadata
                    --
                    -- Sync bytes zero through three are not included in the
                    -- CRC. CRC coverage begins at protocol-version byte four.
                    -----------------------------------------------------------

                    when SEND_METADATA =>
                        done <=
                            '0';

                        if txWait = '0' then
                            nextByte :=
                                metadataByte(
                                    metadataIndex,
                                    frameSequence,
                                    capturedIntegrationTime
                                );

                            txByte <=
                                nextByte;

                            txValid <=
                                '1';

                            if metadataIndex >= 4 then
                                crc <=
                                    crc16Next(
                                        crc,
                                        nextByte
                                    );
                            end if;

                            if metadataIndex = 17 then
                                pixelIndex <=
                                    0;

                                state <=
                                    SET_PIXEL_ADDRESS;

                            else
                                metadataIndex <=
                                    metadataIndex + 1;
                            end if;
                        end if;


                    -----------------------------------------------------------
                    -- Apply the next synchronous RAM read address
                    -----------------------------------------------------------

                    when SET_PIXEL_ADDRESS =>
                        done <=
                            '0';

                        addr <=
                            std_logic_vector(
                                to_unsigned(
                                    pixelIndex,
                                    addr'length
                                )
                            );

                        state <=
                            WAIT_FOR_RAM;


                    -----------------------------------------------------------
                    -- Wait for synchronous RAM Port-B read latency
                    --
                    -- The address was applied during the preceding state.
                    -- This state allows the block RAM output to update.
                    -----------------------------------------------------------

                    when WAIT_FOR_RAM =>
                        done <=
                            '0';

                        state <=
                            LATCH_PIXEL;


                    -----------------------------------------------------------
                    -- Capture the RAM output
                    -----------------------------------------------------------

                    when LATCH_PIXEL =>
                        done <=
                            '0';

                        pixelWord <=
                            data;

                        state <=
                            SEND_PIXEL_HIGH;


                    -----------------------------------------------------------
                    -- Send the high byte of the current pixel
                    -----------------------------------------------------------

                    when SEND_PIXEL_HIGH =>
                        done <=
                            '0';

                        if txWait = '0' then
                            txByte <=
                                pixelWord(15 downto 8);

                            txValid <=
                                '1';

                            crc <=
                                crc16Next(
                                    crc,
                                    pixelWord(15 downto 8)
                                );

                            state <=
                                SEND_PIXEL_LOW;
                        end if;


                    -----------------------------------------------------------
                    -- Send the low byte of the current pixel
                    -----------------------------------------------------------

                    when SEND_PIXEL_LOW =>
                        done <=
                            '0';

                        if txWait = '0' then
                            txByte <=
                                pixelWord(7 downto 0);

                            txValid <=
                                '1';

                            crc <=
                                crc16Next(
                                    crc,
                                    pixelWord(7 downto 0)
                                );

                            if pixelIndex = DATA_LEN - 1 then
                                state <=
                                    SEND_CRC_HIGH;

                            else
                                pixelIndex <=
                                    pixelIndex + 1;

                                state <=
                                    SET_PIXEL_ADDRESS;
                            end if;
                        end if;


                    -----------------------------------------------------------
                    -- Send final CRC high byte
                    --
                    -- The transmitted CRC bytes are not included in the CRC.
                    -----------------------------------------------------------

                    when SEND_CRC_HIGH =>
                        done <=
                            '0';

                        if txWait = '0' then
                            txByte <=
                                std_logic_vector(
                                    crc(15 downto 8)
                                );

                            txValid <=
                                '1';

                            state <=
                                SEND_CRC_LOW;
                        end if;


                    -----------------------------------------------------------
                    -- Send final CRC low byte and complete the frame
                    -----------------------------------------------------------

                    when SEND_CRC_LOW =>
                        done <=
                            '0';

                        if txWait = '0' then
                            txByte <=
                                std_logic_vector(
                                    crc(7 downto 0)
                                );

                            txValid <=
                                '1';

                            frameSequence <=
                                frameSequence + 1;

                            state <=
                                IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture Behavioral;