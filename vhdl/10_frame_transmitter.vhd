-------------------------------------------------------------------------------
-- FILE: 10_frame_transmitter.vhd
--
-- PURPOSE:
--   Construct and transmit one complete binary spectrum frame.
--
-- ROLE IN THE SPECTROMETER FIRMWARE:
--
--   After detector_capture.vhd stores 288 samples in spectrum RAM,
--   spectrometer_top.vhd pulses start.
--
--   frame_transmitter then:
--
--     1. Snapshots the integration-time and command-count metadata.
--     2. Transmits the four-byte synchronization marker.
--     3. Transmits the frame metadata.
--     4. Reads 288 sixteen-bit pixels from dual-port block RAM.
--     5. Transmits each pixel most-significant byte first.
--     6. Calculates CRC-16/CCITT-FALSE over metadata and pixel bytes.
--     7. Appends the two-byte CRC.
--     8. Increments the frame sequence number.
--     9. Pulses done_pulse.
--
-- FRAME FORMAT:
--
--   Byte 0:  Synchronization byte 0 = 0xA5
--   Byte 1:  Synchronization byte 1 = 0x5A
--   Byte 2:  Synchronization byte 2 = 0xC3
--   Byte 3:  Synchronization byte 3 = 0x3C
--
--   Byte 4:  Protocol version
--   Byte 5:  Status/FEC mode
--
--   Byte 6:  Remaining-frame length bits 15 downto 8
--   Byte 7:  Remaining-frame length bits 7 downto 0
--
--   Byte 8:  Frame sequence bits 31 downto 24
--   Byte 9:  Frame sequence bits 23 downto 16
--   Byte 10: Frame sequence bits 15 downto 8
--   Byte 11: Frame sequence bits 7 downto 0
--
--   Byte 12: Integration count bits 31 downto 24
--   Byte 13: Integration count bits 23 downto 16
--   Byte 14: Integration count bits 15 downto 8
--   Byte 15: Integration count bits 7 downto 0
--
--   Byte 16: Accepted command count bits 31 downto 24
--   Byte 17: Accepted command count bits 23 downto 16
--   Byte 18: Accepted command count bits 15 downto 8
--   Byte 19: Accepted command count bits 7 downto 0
--
--   Byte 20: Pixel count bits 15 downto 8
--   Byte 21: Pixel count bits 7 downto 0
--
--   Bytes 22 to 597:
--       288 pixels, two bytes per pixel, most-significant byte first
--
--   Byte 598: CRC bits 15 downto 8
--   Byte 599: CRC bits 7 downto 0
--
-- FRAME SIZE:
--
--   Header including sync:
--
--       22 bytes
--
--   Pixel payload:
--
--       288 pixels * 2 bytes = 576 bytes
--
--   CRC:
--
--       2 bytes
--
--   Total:
--
--       22 + 576 + 2 = 600 bytes
--
--   Bytes after the four-byte synchronization marker:
--
--       600 - 4 = 596 bytes = 0x0254
--
-- CRC COVERAGE:
--
--   The CRC excludes:
--
--       - Four synchronization bytes
--       - The two transmitted CRC bytes
--
--   The CRC includes:
--
--       - Protocol version
--       - Status byte
--       - Remaining length
--       - Sequence number
--       - Integration count
--       - Command count
--       - Pixel count
--       - Every pixel byte
--
-- TRANSMITTER HANDSHAKE:
--
--   tx_ready:
--       Indicates that the downstream UART path can accept one byte.
--
--   tx_data:
--       Contains the byte to be transmitted.
--
--   tx_valid:
--       Pulses high when tx_data contains a new byte.
--
--   In spectrometer_top.vhd, the frame transmitter must receive the gated
--   ready signal:
--
--       frame_tx_ready <= tx_ready and not tx_valid;
--
--   This gating prevents the state machine from advancing twice before
--   uart_tx registers the current byte. Laboratory testing showed that using
--   the raw UART ready signal caused every alternate byte to be omitted.
-------------------------------------------------------------------------------

library IEEE;

use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Provides PIXEL_COUNT.
use work.hardware_config.all;

-- Provides synchronization bytes, protocol version, and FEC identifiers.
use work.protocol_config.all;

-- Provides CRC16_INITIAL and crc16_next.
use work.crc16_pkg.all;


-------------------------------------------------------------------------------
-- ENTITY
-------------------------------------------------------------------------------

entity frame_transmitter is
    port (
        -----------------------------------------------------------------------
        -- 60 MHz fast/readout clock.
        -----------------------------------------------------------------------

        clock :
            in std_logic;

        -----------------------------------------------------------------------
        -- Active-high synchronous reset.
        -----------------------------------------------------------------------

        reset :
            in std_logic;

        -----------------------------------------------------------------------
        -- One-clock pulse requesting transmission of one stored spectrum.
        -----------------------------------------------------------------------

        start :
            in std_logic;

        -----------------------------------------------------------------------
        -- Per-frame metadata.
        --
        -- spectrometer_top.vhd snapshots and holds these values stable before
        -- asserting start.
        -----------------------------------------------------------------------

        integration_counts :
            in unsigned(31 downto 0);

        command_count :
            in unsigned(31 downto 0);

        -----------------------------------------------------------------------
        -- Transmitter status.
        -----------------------------------------------------------------------

        -- High while a frame is being constructed and transmitted.
        busy :
            out std_logic;

        -- One-clock pulse after the final CRC byte has been accepted.
        done_pulse :
            out std_logic;

        -----------------------------------------------------------------------
        -- Spectrum RAM Port-B read interface.
        -----------------------------------------------------------------------

        ram_addr :
            out std_logic_vector(8 downto 0);

        ram_data :
            in std_logic_vector(15 downto 0);

        -----------------------------------------------------------------------
        -- Downstream byte-transmission interface.
        -----------------------------------------------------------------------

        tx_data :
            out std_logic_vector(7 downto 0);

        tx_valid :
            out std_logic;

        tx_ready :
            in std_logic
    );
end entity frame_transmitter;


-------------------------------------------------------------------------------
-- ARCHITECTURE
-------------------------------------------------------------------------------

architecture rtl of frame_transmitter is

    ---------------------------------------------------------------------------
    -- Frame-transmission state machine
    ---------------------------------------------------------------------------

    type state_type is (
        IDLE,
        META,
        SET_ADDR,
        WAIT_RAM,
        LATCH_RAM,
        PIXEL_HI,
        PIXEL_LO,
        CRC_HI,
        CRC_LO
    );

    signal state :
        state_type := IDLE;


    ---------------------------------------------------------------------------
    -- Metadata-byte index.
    --
    -- Values 0 through 21 select the complete pre-pixel header.
    ---------------------------------------------------------------------------

    signal meta_index :
        natural range 0 to 21 := 0;


    ---------------------------------------------------------------------------
    -- Current spectrum pixel.
    ---------------------------------------------------------------------------

    signal pixel_index :
        natural range 0 to PIXEL_COUNT - 1 := 0;


    ---------------------------------------------------------------------------
    -- Pixel value latched from synchronous block RAM.
    ---------------------------------------------------------------------------

    signal pixel_word :
        std_logic_vector(15 downto 0) := (others => '0');


    ---------------------------------------------------------------------------
    -- Frame sequence number.
    --
    -- Starts at zero after reset and increments after every transmitted frame.
    ---------------------------------------------------------------------------

    signal sequence_number :
        unsigned(31 downto 0) := (others => '0');


    ---------------------------------------------------------------------------
    -- Snapshot metadata registers.
    --
    -- These values are copied at frame start and held stable throughout
    -- transmission.
    ---------------------------------------------------------------------------

    signal frame_integration_counts :
        unsigned(31 downto 0) := (others => '0');

    signal frame_command_count :
        unsigned(31 downto 0) := (others => '0');


    ---------------------------------------------------------------------------
    -- Running CRC value.
    ---------------------------------------------------------------------------

    signal crc :
        unsigned(15 downto 0) := CRC16_INITIAL;


    ---------------------------------------------------------------------------
    -- Frame-length constants
    ---------------------------------------------------------------------------

    constant TOTAL_BYTES :
        natural := 22 + (PIXEL_COUNT * 2) + 2;

    constant REMAINING_BYTES :
        natural := TOTAL_BYTES - 4;

    ---------------------------------------------------------------------------
    -- Explicit 16-bit versions are used for VHDL-93 compatibility.
    --
    -- Older VHDL modes may not allow a direct slice of a function result such
    -- as:
    --
    --     to_unsigned(value, 16)(15 downto 8)
    ---------------------------------------------------------------------------

    constant REMAINING_BYTES_U16 :
        unsigned(15 downto 0) :=
            to_unsigned(REMAINING_BYTES, 16);

    constant PIXEL_COUNT_U16 :
        unsigned(15 downto 0) :=
            to_unsigned(PIXEL_COUNT, 16);


    ---------------------------------------------------------------------------
    -- Return one byte from the frame header.
    ---------------------------------------------------------------------------

    function metadata_byte (
        byte_number        : natural;
        sequence_value     : unsigned(31 downto 0);
        integration_value  : unsigned(31 downto 0);
        command_value      : unsigned(31 downto 0)
    ) return std_logic_vector is

        variable status :
            std_logic_vector(7 downto 0) := (others => '0');

    begin

        -----------------------------------------------------------------------
        -- Advertise the selected FEC mode in status bits 1 downto 0.
        --
        -- The current build uses FEC_NONE, so status remains 0x00.
        --
        -- Merely selecting FEC_HAMMING_SECDED does not implement encoding; the
        -- constant is reserved for a future encoder.
        -----------------------------------------------------------------------

        if FEC_MODE = FEC_HAMMING_SECDED then
            status(1 downto 0) := "01";
        end if;


        case byte_number is

            when 0 =>
                return SYNC_0;

            when 1 =>
                return SYNC_1;

            when 2 =>
                return SYNC_2;

            when 3 =>
                return SYNC_3;

            when 4 =>
                return PROTOCOL_VERSION;

            when 5 =>
                return status;

            when 6 =>
                return std_logic_vector(
                    REMAINING_BYTES_U16(15 downto 8)
                );

            when 7 =>
                return std_logic_vector(
                    REMAINING_BYTES_U16(7 downto 0)
                );

            when 8 =>
                return std_logic_vector(
                    sequence_value(31 downto 24)
                );

            when 9 =>
                return std_logic_vector(
                    sequence_value(23 downto 16)
                );

            when 10 =>
                return std_logic_vector(
                    sequence_value(15 downto 8)
                );

            when 11 =>
                return std_logic_vector(
                    sequence_value(7 downto 0)
                );

            when 12 =>
                return std_logic_vector(
                    integration_value(31 downto 24)
                );

            when 13 =>
                return std_logic_vector(
                    integration_value(23 downto 16)
                );

            when 14 =>
                return std_logic_vector(
                    integration_value(15 downto 8)
                );

            when 15 =>
                return std_logic_vector(
                    integration_value(7 downto 0)
                );

            when 16 =>
                return std_logic_vector(
                    command_value(31 downto 24)
                );

            when 17 =>
                return std_logic_vector(
                    command_value(23 downto 16)
                );

            when 18 =>
                return std_logic_vector(
                    command_value(15 downto 8)
                );

            when 19 =>
                return std_logic_vector(
                    command_value(7 downto 0)
                );

            when 20 =>
                return std_logic_vector(
                    PIXEL_COUNT_U16(15 downto 8)
                );

            when 21 =>
                return std_logic_vector(
                    PIXEL_COUNT_U16(7 downto 0)
                );

            when others =>
                return x"00";

        end case;

    end function metadata_byte;

begin

    ---------------------------------------------------------------------------
    -- FRAME TRANSMISSION PROCESS
    ---------------------------------------------------------------------------

    FRAME_TRANSMISSION_PROCESS : process(clock)

        -----------------------------------------------------------------------
        -- Temporary byte returned by metadata_byte.
        --
        -- A variable allows the same value to be assigned to tx_data and passed
        -- to crc16_next during the current clock cycle.
        -----------------------------------------------------------------------

        variable next_byte :
            std_logic_vector(7 downto 0);

    begin

        if rising_edge(clock) then

            -------------------------------------------------------------------
            -- Pulse outputs default low.
            -------------------------------------------------------------------

            tx_valid   <= '0';
            done_pulse <= '0';


            -------------------------------------------------------------------
            -- Synchronous reset
            -------------------------------------------------------------------

            if reset = '1' then

                state <= IDLE;

                busy <= '0';

                tx_data <=
                    (others => '0');

                ram_addr <=
                    (others => '0');

                sequence_number <=
                    (others => '0');

                frame_integration_counts <=
                    (others => '0');

                frame_command_count <=
                    (others => '0');

                crc <=
                    CRC16_INITIAL;

                meta_index <= 0;

                pixel_index <= 0;

                pixel_word <=
                    (others => '0');


            -------------------------------------------------------------------
            -- Normal frame transmission
            -------------------------------------------------------------------

            else

                case state is

                    -----------------------------------------------------------
                    -- IDLE
                    --
                    -- Wait for a completed spectrum.
                    -----------------------------------------------------------

                    when IDLE =>

                        busy <= '0';

                        if start = '1' then

                            busy <= '1';

                            ---------------------------------------------------
                            -- Snapshot metadata so that live command/config
                            -- changes cannot alter a frame during transmission.
                            ---------------------------------------------------

                            frame_integration_counts <=
                                integration_counts;

                            frame_command_count <=
                                command_count;

                            crc <=
                                CRC16_INITIAL;

                            meta_index <= 0;

                            pixel_index <= 0;

                            state <= META;

                        end if;


                    -----------------------------------------------------------
                    -- META
                    --
                    -- Transmit bytes 0 through 21.
                    -----------------------------------------------------------

                    when META =>

                        busy <= '1';

                        if tx_ready = '1' then

                            next_byte :=
                                metadata_byte(
                                    meta_index,
                                    sequence_number,
                                    frame_integration_counts,
                                    frame_command_count
                                );

                            tx_data <=
                                next_byte;

                            tx_valid <= '1';


                            ---------------------------------------------------
                            -- Metadata bytes 0 to 3 are the synchronization
                            -- marker and are excluded from CRC coverage.
                            ---------------------------------------------------

                            if meta_index >= 4 then

                                crc <=
                                    crc16_next(
                                        crc,
                                        next_byte
                                    );

                            end if;


                            if meta_index = 21 then

                                pixel_index <= 0;

                                state <= SET_ADDR;

                            else

                                meta_index <=
                                    meta_index + 1;

                            end if;

                        end if;


                    -----------------------------------------------------------
                    -- SET_ADDR
                    --
                    -- Apply the current pixel address to synchronous RAM.
                    -----------------------------------------------------------

                    when SET_ADDR =>

                        busy <= '1';

                        ram_addr <=
                            std_logic_vector(
                                to_unsigned(
                                    pixel_index,
                                    ram_addr'length
                                )
                            );

                        state <= WAIT_RAM;


                    -----------------------------------------------------------
                    -- WAIT_RAM
                    --
                    -- Allow one fast-clock cycle for synchronous BRAM output
                    -- to update after the address changes.
                    -----------------------------------------------------------

                    when WAIT_RAM =>

                        busy <= '1';

                        state <= LATCH_RAM;


                    -----------------------------------------------------------
                    -- LATCH_RAM
                    --
                    -- Copy the current BRAM output into a stable local register.
                    -----------------------------------------------------------

                    when LATCH_RAM =>

                        busy <= '1';

                        pixel_word <=
                            ram_data;

                        state <= PIXEL_HI;


                    -----------------------------------------------------------
                    -- PIXEL_HI
                    --
                    -- Transmit the most-significant pixel byte first.
                    -----------------------------------------------------------

                    when PIXEL_HI =>

                        busy <= '1';

                        if tx_ready = '1' then

                            tx_data <=
                                pixel_word(15 downto 8);

                            tx_valid <= '1';

                            crc <=
                                crc16_next(
                                    crc,
                                    pixel_word(15 downto 8)
                                );

                            state <= PIXEL_LO;

                        end if;


                    -----------------------------------------------------------
                    -- PIXEL_LO
                    --
                    -- Transmit the least-significant pixel byte.
                    -----------------------------------------------------------

                    when PIXEL_LO =>

                        busy <= '1';

                        if tx_ready = '1' then

                            tx_data <=
                                pixel_word(7 downto 0);

                            tx_valid <= '1';

                            crc <=
                                crc16_next(
                                    crc,
                                    pixel_word(7 downto 0)
                                );


                            if pixel_index = PIXEL_COUNT - 1 then

                                state <= CRC_HI;

                            else

                                pixel_index <=
                                    pixel_index + 1;

                                state <= SET_ADDR;

                            end if;

                        end if;


                    -----------------------------------------------------------
                    -- CRC_HI
                    --
                    -- Transmit CRC bits 15 downto 8.
                    --
                    -- CRC bytes are not fed back into the CRC calculation.
                    -----------------------------------------------------------

                    when CRC_HI =>

                        busy <= '1';

                        if tx_ready = '1' then

                            tx_data <=
                                std_logic_vector(
                                    crc(15 downto 8)
                                );

                            tx_valid <= '1';

                            state <= CRC_LO;

                        end if;


                    -----------------------------------------------------------
                    -- CRC_LO
                    --
                    -- Transmit CRC bits 7 downto 0 and complete the frame.
                    -----------------------------------------------------------

                    when CRC_LO =>

                        busy <= '1';

                        if tx_ready = '1' then

                            tx_data <=
                                std_logic_vector(
                                    crc(7 downto 0)
                                );

                            tx_valid <= '1';

                            sequence_number <=
                                sequence_number + 1;

                            busy <= '0';

                            done_pulse <= '1';

                            state <= IDLE;

                        end if;

                end case;

            end if;

        end if;

    end process FRAME_TRANSMISSION_PROCESS;

end architecture rtl;