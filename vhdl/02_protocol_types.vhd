-------------------------------------------------------------------------------
-- FILE: 02_protocol_types.vhd
--
-- PURPOSE:
--   Defines shared protocol-related data types and conversion functions used
--   by the FPGA command and acquisition-control modules.
--
-- ROLE IN THE SPECTROMETER FIRMWARE:
--
--   UART command bytes are processed through the following path:
--
--       uart_rx
--           |
--           v
--       command_decoder
--           |
--           | command_type
--           v
--       command_controller
--           |
--           v
--       integration and acquisition settings
--
--   This package defines the command_type record passed between
--   command_decoder.vhd and command_controller.vhd.
--
--   The package also provides functions that:
--
--     1. Clamp a requested integration time to the supported minimum and
--        maximum values.
--
--     2. Convert integration time from microseconds into 5 MHz detector-clock
--        counts.
--
-- EXAMPLE:
--
--   A host command requests:
--
--       200 microseconds
--
--   With a 5 MHz detector clock:
--
--       5 detector counts per microsecond
--
--   Therefore:
--
--       200 us * 5 counts/us = 1,000 detector-clock counts
-------------------------------------------------------------------------------

library IEEE;

-- Provides std_logic and std_logic_vector.
use IEEE.STD_LOGIC_1164.ALL;

-- Provides unsigned arithmetic, to_unsigned, and to_integer.
use IEEE.NUMERIC_STD.ALL;

-- Imports integration-time limits and detector-clock conversion constants.
use work.hardware_config.all;


-------------------------------------------------------------------------------
-- PACKAGE DECLARATION
-------------------------------------------------------------------------------

package protocol_types is

    ---------------------------------------------------------------------------
    -- DECODED COMMAND RECORD
    --
    -- Represents one complete command after the eight-byte UART command frame
    -- has been reconstructed by command_decoder.vhd.
    --
    -- Incoming command format:
    --
    --     Byte 0: 0xEF
    --     Byte 1: 0x00
    --     Byte 2: command ID bits 15 downto 8
    --     Byte 3: command ID bits 7 downto 0
    --     Byte 4: data bits 31 downto 24
    --     Byte 5: data bits 23 downto 16
    --     Byte 6: data bits 15 downto 8
    --     Byte 7: data bits 7 downto 0
    --
    -- command_id:
    --   Identifies the requested operation.
    --
    -- data:
    --   Contains the 32-bit command argument.
    --
    -- valid:
    --   Pulses high when command_id and data contain one complete decoded
    --   command. The receiving module processes the command only while valid
    --   is high.
    ---------------------------------------------------------------------------

    type command_type is record

        -----------------------------------------------------------------------
        -- Sixteen-bit command identifier.
        --
        -- Commands currently implemented by command_controller.vhd include:
        --
        --     0x1000  Set integration time in microseconds and enable running
        --     0x4000  Stop or resume continuous acquisition
        --     0x4001  Request one spectrum
        --     0x5000  Select real ADC or test-pattern mode
        -----------------------------------------------------------------------

        command_id :
            std_logic_vector(15 downto 0);

        -----------------------------------------------------------------------
        -- Thirty-two-bit command data field.
        --
        -- The interpretation depends on command_id.
        --
        -- Examples:
        --
        --     command 0x1000:
        --         data contains integration time in microseconds
        --
        --     command 0x4000:
        --         data bit 0 controls continuous acquisition
        --
        --     command 0x5000:
        --         data bits 1 downto 0 select the input-data mode
        -----------------------------------------------------------------------

        data :
            std_logic_vector(31 downto 0);

        -----------------------------------------------------------------------
        -- Command-valid indication.
        --
        -- The decoder asserts valid for one clock cycle after receiving all
        -- eight bytes of a valid command packet.
        -----------------------------------------------------------------------

        valid :
            std_logic;

    end record;


    ---------------------------------------------------------------------------
    -- IDLE COMMAND CONSTANT
    --
    -- Provides a known inactive value for a command_type record.
    --
    -- Used during:
    --
    --   - signal initialization;
    --   - reset handling;
    --   - cycles in which no command is available.
    --
    -- command_id and data are zero, while valid is low. Consequently, the
    -- command controller will not execute this value.
    ---------------------------------------------------------------------------

    constant COMMAND_IDLE :
        command_type := (
            command_id => (others => '0'),
            data       => (others => '0'),
            valid      => '0'
        );


    ---------------------------------------------------------------------------
    -- INTEGRATION-COUNT TYPE
    --
    -- Represents integration duration in 5 MHz detector-clock counts.
    --
    -- A 32-bit unsigned value supports counts from:
    --
    --     0 to 4,294,967,295
    --
    -- The configured maximum is smaller:
    --
    --     MAX_INTEGRATION_US = 20,000,000 us
    --     COUNTS_PER_US      = 5
    --
    --     Maximum count = 100,000,000
    ---------------------------------------------------------------------------

    subtype integration_count_type is
        unsigned(31 downto 0);


    ---------------------------------------------------------------------------
    -- CLAMP AN INTEGRATION-TIME REQUEST
    --
    -- Input:
    --   A 32-bit unsigned integration time expressed in microseconds.
    --
    -- Return:
    --   A natural value restricted to:
    --
    --       MIN_INTEGRATION_US <= result <= MAX_INTEGRATION_US
    --
    -- Examples using the current configuration:
    --
    --       Input 0          -> 20 us
    --       Input 10         -> 20 us
    --       Input 200        -> 200 us
    --       Input 20,000,001 -> 20,000,000 us
    --
    -- Clamping protects the detector-control state machine from invalid,
    -- excessively short, or excessively long host requests.
    ---------------------------------------------------------------------------

    function clamp_us (
        value : unsigned(31 downto 0)
    ) return natural;


    ---------------------------------------------------------------------------
    -- CONVERT MICROSECONDS TO DETECTOR-CLOCK COUNTS
    --
    -- Input:
    --   Integration time in microseconds.
    --
    -- Return:
    --   The equivalent number of 5 MHz detector-clock counts.
    --
    -- Current conversion:
    --
    --       COUNTS_PER_US = 5
    --
    -- Examples:
    --
    --       20 us  -> 100 counts
    --       200 us -> 1,000 counts
    --       1 ms   -> 5,000 counts
    --
    -- The input should normally be passed through clamp_us before this
    -- conversion is performed.
    ---------------------------------------------------------------------------

    function us_to_counts (
        value_us : natural
    ) return integration_count_type;

end package protocol_types;


-------------------------------------------------------------------------------
-- PACKAGE BODY
-------------------------------------------------------------------------------

package body protocol_types is

    ---------------------------------------------------------------------------
    -- CLAMP_US IMPLEMENTATION
    ---------------------------------------------------------------------------

    function clamp_us (
        value : unsigned(31 downto 0)
    ) return natural is

        -----------------------------------------------------------------------
        -- Temporary natural representation of the requested time.
        --
        -- Conversion is performed only after checking the upper limit. This
        -- avoids converting an unsigned value larger than the implementation's
        -- supported natural/integer range.
        -----------------------------------------------------------------------

        variable requested_us :
            natural;

    begin

        -----------------------------------------------------------------------
        -- Upper-limit check.
        --
        -- The comparison is performed while value is still unsigned. This is
        -- important because an arbitrary 32-bit value may be larger than the
        -- maximum VHDL natural value supported by the tool.
        -----------------------------------------------------------------------

        if value >
            to_unsigned(
                MAX_INTEGRATION_US,
                value'length
            )
        then

            return MAX_INTEGRATION_US;

        end if;


        -----------------------------------------------------------------------
        -- The upper limit is known to be safe, so convert the request into a
        -- natural value.
        -----------------------------------------------------------------------

        requested_us :=
            to_integer(value);


        -----------------------------------------------------------------------
        -- Lower-limit check.
        -----------------------------------------------------------------------

        if requested_us < MIN_INTEGRATION_US then

            return MIN_INTEGRATION_US;

        end if;


        -----------------------------------------------------------------------
        -- The requested value is already within the supported range.
        -----------------------------------------------------------------------

        return requested_us;

    end function clamp_us;


    ---------------------------------------------------------------------------
    -- US_TO_COUNTS IMPLEMENTATION
    ---------------------------------------------------------------------------

    function us_to_counts (
        value_us : natural
    ) return integration_count_type is
    begin

        -----------------------------------------------------------------------
        -- Convert microseconds into detector-clock counts.
        --
        -- With the current configuration:
        --
        --     DEVICE_CLOCK_HZ = 5,000,000
        --     COUNTS_PER_US   = 5
        --
        -- For a 200 us request:
        --
        --     200 * 5 = 1,000 counts
        -----------------------------------------------------------------------

        return to_unsigned(
            value_us * COUNTS_PER_US,
            integration_count_type'length
        );

    end function us_to_counts;

end package body protocol_types;
