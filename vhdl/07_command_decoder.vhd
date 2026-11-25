-------------------------------------------------------------------------------
-- FILE: 07_command_decoder.vhd
--
-- PURPOSE:
--   Reconstruct one complete command from the individual UART bytes produced
--   by uart_rx.vhd.
--
-- COMMAND-PACKET FORMAT:
--
--   Every command contains eight bytes:
--
--       Byte 0: 0xEF
--       Byte 1: 0x00
--       Byte 2: command ID bits 15 downto 8
--       Byte 3: command ID bits 7 downto 0
--       Byte 4: command data bits 31 downto 24
--       Byte 5: command data bits 23 downto 16
--       Byte 6: command data bits 15 downto 8
--       Byte 7: command data bits 7 downto 0
--
--   Example command:
--
--       EF 00 10 00 00 00 00 C8
--
--   Decodes as:
--
--       command_id = 0x1000
--       data       = 0x000000C8 = 200
--
--   In the current firmware, command 0x1000 interprets the data value as an
--   integration time in microseconds.
--
-- ROLE IN THE SPECTROMETER FIRMWARE:
--
--   The command path is:
--
--       Python host
--           |
--           v
--       USB-UART bridge
--           |
--           v
--       uart_rx
--           |
--           | byte_in and byte_valid
--           v
--       command_decoder
--           |
--           | command_out
--           v
--       command_controller
--
--   uart_rx handles UART bit timing and outputs individual bytes.
--
--   command_decoder:
--
--       - finds the EF 00 packet header;
--       - collects the remaining six bytes;
--       - separates the command ID from the command data;
--       - pulses command_out.valid for one clock cycle.
--
--   command_controller.vhd then interprets the decoded command.
--
-- TIMEOUT:
--
--   If a command begins but the remaining bytes do not arrive within
--   TIMEOUT_CYCLES, the partial packet is discarded.
--
--   With the current 10 MHz system clock and default value of 100,000:
--
--       100,000 cycles / 10,000,000 cycles/s = 0.01 s = 10 ms
--
--   A complete eight-byte command at 1 Mbaud requires approximately 80 us,
--   so the 10 ms timeout provides substantial margin while still allowing
--   recovery from incomplete packets.
-------------------------------------------------------------------------------

library IEEE;

-- Provides std_logic and std_logic_vector.
use IEEE.STD_LOGIC_1164.ALL;

-- Imports command_type and COMMAND_IDLE.
use work.protocol_types.all;


-------------------------------------------------------------------------------
-- ENTITY
-------------------------------------------------------------------------------

entity command_decoder is

    generic (

        -----------------------------------------------------------------------
        -- Maximum number of clock cycles permitted between bytes while a
        -- command packet is being assembled.
        --
        -- If the timeout expires, the decoder discards the incomplete packet
        -- and returns to searching for the 0xEF header byte.
        -----------------------------------------------------------------------

        TIMEOUT_CYCLES :
            positive := 100000
    );

    port (

        -----------------------------------------------------------------------
        -- Command-decoder clock.
        --
        -- In spectrometer_top.vhd this is the 10 MHz system clock.
        -----------------------------------------------------------------------

        clock :
            in std_logic;

        -----------------------------------------------------------------------
        -- Active-high synchronous reset.
        --
        -- Clears any partially received command and returns the decoder to its
        -- initial header-search state.
        -----------------------------------------------------------------------

        reset :
            in std_logic;

        -----------------------------------------------------------------------
        -- Latest eight-bit byte produced by uart_rx.
        -----------------------------------------------------------------------

        byte_in :
            in std_logic_vector(7 downto 0);

        -----------------------------------------------------------------------
        -- One-clock pulse indicating that byte_in contains a newly received
        -- UART byte.
        -----------------------------------------------------------------------

        byte_valid :
            in std_logic;

        -----------------------------------------------------------------------
        -- Complete decoded command.
        --
        -- command_out.valid pulses high for one clock cycle when command_id
        -- and data contain a newly completed command packet.
        -----------------------------------------------------------------------

        command_out :
            out command_type
    );

end entity command_decoder;


-------------------------------------------------------------------------------
-- ARCHITECTURE
-------------------------------------------------------------------------------

architecture rtl of command_decoder is

    ---------------------------------------------------------------------------
    -- Current packet-byte index.
    --
    -- Index 0:
    --   Waiting for 0xEF.
    --
    -- Index 1:
    --   Waiting for 0x00.
    --
    -- Indices 2 to 7:
    --   Receiving the command ID and 32-bit data field.
    ---------------------------------------------------------------------------

    signal byte_index :
        natural range 0 to 7 := 0;


    ---------------------------------------------------------------------------
    -- Counts system-clock cycles since the most recent byte of an incomplete
    -- packet.
    --
    -- The range includes TIMEOUT_CYCLES so that the counter remains explicitly
    -- bounded for synthesis.
    ---------------------------------------------------------------------------

    signal timeout_count :
        natural range 0 to TIMEOUT_CYCLES := 0;


    ---------------------------------------------------------------------------
    -- Stores the six bytes following the EF 00 header.
    --
    -- The 48-bit payload contains:
    --
    --     bits 47 downto 32: command ID
    --     bits 31 downto 0:  command data
    ---------------------------------------------------------------------------

    signal payload :
        std_logic_vector(47 downto 0) := (others => '0');

begin

    ---------------------------------------------------------------------------
    -- COMMAND DECODER
    ---------------------------------------------------------------------------

    COMMAND_DECODER_PROCESS : process(clock)

        -----------------------------------------------------------------------
        -- Temporary payload value after appending the newest byte.
        --
        -- A variable is used because signal assignments do not take effect
        -- until the process suspends. The variable allows the final received
        -- byte to be included immediately when extracting command_id and data.
        -----------------------------------------------------------------------

        variable next_payload :
            std_logic_vector(47 downto 0);

    begin

        if rising_edge(clock) then

            -------------------------------------------------------------------
            -- command_out.valid is a one-clock pulse.
            --
            -- It defaults low on every clock and is asserted only when the
            -- eighth byte of a complete packet is received.
            -------------------------------------------------------------------

            command_out.valid <= '0';


            -------------------------------------------------------------------
            -- Synchronous reset
            -------------------------------------------------------------------

            if reset = '1' then

                byte_index <= 0;

                timeout_count <= 0;

                payload <=
                    (others => '0');

                command_out <=
                    COMMAND_IDLE;


            -------------------------------------------------------------------
            -- Process a newly received UART byte
            -------------------------------------------------------------------

            elsif byte_valid = '1' then

                ----------------------------------------------------------------
                -- A byte arrived, so restart the inter-byte timeout counter.
                ----------------------------------------------------------------

                timeout_count <= 0;


                case byte_index is

                    -----------------------------------------------------------
                    -- BYTE 0: first synchronization/header byte
                    --
                    -- Ignore all bytes until 0xEF is received.
                    -----------------------------------------------------------

                    when 0 =>

                        if byte_in = x"EF" then

                            byte_index <= 1;

                        end if;


                    -----------------------------------------------------------
                    -- BYTE 1: second synchronization/header byte
                    --
                    -- Expected value: 0x00
                    --
                    -- If another 0xEF is received, retain it as a possible new
                    -- first header byte. This improves recovery from streams
                    -- such as:
                    --
                    --     ... EF EF 00 ...
                    -----------------------------------------------------------

                    when 1 =>

                        if byte_in = x"00" then

                            byte_index <= 2;

                            payload <=
                                (others => '0');

                        elsif byte_in = x"EF" then

                            byte_index <= 1;

                        else

                            byte_index <= 0;

                        end if;


                    -----------------------------------------------------------
                    -- BYTES 2 TO 7:
                    --
                    -- Append command-ID and command-data bytes to payload.
                    --
                    -- Existing payload bits 39 downto 0 are shifted toward the
                    -- most-significant end, and byte_in is appended at the
                    -- least-significant end.
                    -----------------------------------------------------------

                    when others =>

                        next_payload :=
                            payload(39 downto 0) &
                            byte_in;

                        payload <=
                            next_payload;


                        -------------------------------------------------------
                        -- Byte index 7 is the final command byte.
                        -------------------------------------------------------

                        if byte_index = 7 then

                            command_out.command_id <=
                                next_payload(47 downto 32);

                            command_out.data <=
                                next_payload(31 downto 0);

                            command_out.valid <= '1';

                            ---------------------------------------------------
                            -- Return immediately to header search so the next
                            -- command can begin with the next received byte.
                            ---------------------------------------------------

                            byte_index <= 0;

                        else

                            byte_index <=
                                byte_index + 1;

                        end if;

                end case;


            -------------------------------------------------------------------
            -- No new byte arrived while a packet is incomplete
            -------------------------------------------------------------------

            elsif byte_index /= 0 then

                ----------------------------------------------------------------
                -- Discard the partial packet if the timeout expires.
                ----------------------------------------------------------------

                if timeout_count = TIMEOUT_CYCLES - 1 then

                    byte_index <= 0;

                    timeout_count <= 0;

                    payload <=
                        (others => '0');

                else

                    timeout_count <=
                        timeout_count + 1;

                end if;


            -------------------------------------------------------------------
            -- Decoder is idle and not assembling a packet.
            -------------------------------------------------------------------

            else

                timeout_count <= 0;

            end if;

        end if;

    end process COMMAND_DECODER_PROCESS;

end architecture rtl;
