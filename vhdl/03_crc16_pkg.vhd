-------------------------------------------------------------------------------
-- FILE: crc16_pkg.vhd
--
-- PURPOSE:
--   Provides the CRC-16/CCITT-FALSE calculation used to protect each binary
--   spectrum frame transmitted by the FPGA.
--
-- CRC CONFIGURATION:
--   Name:          CRC-16/CCITT-FALSE
--   Width:         16 bits
--   Polynomial:    0x1021
--   Initial value: 0xFFFF
--   Input reflect: false
--   Output reflect:false
--   Final XOR:     0x0000
--
-- ROLE IN THE SPECTROMETER FIRMWARE:
--   frame_transmitter.vhd calls crc16_next once for each byte included in the
--   protected portion of a spectrum frame.
--
--   The four synchronization bytes:
--
--       A5 5A C3 3C
--
--   are not included in the CRC calculation.
--
--   CRC calculation begins with the protocol-version byte and continues
--   through the final low byte of the final pixel.
--
--   After all protected bytes have been processed, the FPGA transmits:
--
--       CRC bits 15 downto 8
--       CRC bits 7 downto 0
--
--   The Python host software performs the same calculation and rejects a frame
--   if the received and calculated CRC values do not match.
--
-- OPERATION:
--   This is an incremental CRC function. The complete frame does not need to
--   be stored in a separate buffer before calculating the CRC.
--
--   For every transmitted protected byte:
--
--       crc <= crc16_next(crc, transmitted_byte);
--
--   Before starting a new frame:
--
--       crc <= CRC16_INITIAL;
-------------------------------------------------------------------------------

library IEEE;

-- Provides std_logic and std_logic_vector.
use IEEE.STD_LOGIC_1164.ALL;

-- Provides unsigned arithmetic, resize, conversion, XOR, and shift_left.
use IEEE.NUMERIC_STD.ALL;


-------------------------------------------------------------------------------
-- PACKAGE DECLARATION
--
-- The package declaration exposes the initial CRC value and update function
-- to other VHDL design units.
-------------------------------------------------------------------------------

package crc16_pkg is

    ---------------------------------------------------------------------------
    -- Initial CRC value.
    --
    -- At the beginning of every new spectrum frame, the frame transmitter
    -- loads its CRC register with 0xFFFF.
    ---------------------------------------------------------------------------

    constant CRC16_INITIAL :
        unsigned(15 downto 0) := x"FFFF";

    ---------------------------------------------------------------------------
    -- Calculate the CRC state after processing one byte.
    --
    -- Inputs:
    --   current_crc
    --       The CRC value calculated from all previously processed bytes.
    --
    --   next_byte
    --       The next eight-bit frame byte to include in the CRC.
    --
    -- Return:
    --   The updated 16-bit CRC value.
    --
    -- The function is combinational. It does not contain registers or retain
    -- state between calls. The calling module stores the returned result.
    ---------------------------------------------------------------------------

    function crc16_next (
        current_crc : unsigned(15 downto 0);
        next_byte   : std_logic_vector(7 downto 0)
    ) return unsigned;

end package crc16_pkg;


-------------------------------------------------------------------------------
-- PACKAGE BODY
--
-- Contains the implementation of crc16_next.
-------------------------------------------------------------------------------

package body crc16_pkg is

    function crc16_next (
        current_crc : unsigned(15 downto 0);
        next_byte   : std_logic_vector(7 downto 0)
    ) return unsigned is

        -----------------------------------------------------------------------
        -- Working CRC value.
        --
        -- The calculation modifies this variable eight times, once for each
        -- bit in next_byte.
        -----------------------------------------------------------------------

        variable result :
            unsigned(15 downto 0);

    begin

        -----------------------------------------------------------------------
        -- XOR the new byte into the upper eight bits of the current CRC.
        --
        -- next_byte is first converted from std_logic_vector to unsigned,
        -- resized to 16 bits, and shifted left by eight positions:
        --
        --     ABCD EFGH
        --
        -- becomes:
        --
        --     ABCD EFGH 0000 0000
        --
        -- This is then XORed with the current CRC state.
        -----------------------------------------------------------------------

        result :=
            current_crc xor
            shift_left(
                resize(
                    unsigned(next_byte),
                    16
                ),
                8
            );

        -----------------------------------------------------------------------
        -- Process all eight bits of the input byte.
        --
        -- CRC-16/CCITT-FALSE is a most-significant-bit-first CRC, so the
        -- feedback decision is based on bit 15 of the current working value.
        -----------------------------------------------------------------------

        for bit_number in 0 to 7 loop

            -------------------------------------------------------------------
            -- If the current most-significant bit is one, shift left and XOR
            -- with the CRC polynomial 0x1021.
            -------------------------------------------------------------------

            if result(15) = '1' then

                result :=
                    shift_left(result, 1) xor
                    to_unsigned(16#1021#, 16);

            -------------------------------------------------------------------
            -- If the current most-significant bit is zero, only shift left.
            -------------------------------------------------------------------

            else

                result :=
                    shift_left(result, 1);

            end if;

        end loop;

        -----------------------------------------------------------------------
        -- Return the CRC value after processing next_byte.
        -----------------------------------------------------------------------

        return result;

    end function crc16_next;

end package body crc16_pkg;