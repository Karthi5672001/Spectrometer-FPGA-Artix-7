-------------------------------------------------------------------------------
-- FILE: 01_protocol_config.vhd
--
-- PURPOSE:
--   Defines the constants that describe the binary communication protocol used
--   when transmitting spectrum frames from the FPGA to the host computer.
--
-- ROLE IN THE SPECTROMETER FIRMWARE:
--   frame_transmitter.vhd imports this package and uses these constants when
--   constructing each binary spectrum frame.
--
--   The host-side Python software must use the same:
--
--     - synchronization marker;
--     - protocol version;
--     - error-correction mode interpretation.
--
-- CURRENT FRAME START:
--
--     Byte 0: 0xA5
--     Byte 1: 0x5A
--     Byte 2: 0xC3
--     Byte 3: 0x3C
--     Byte 4: protocol version
--     Byte 5: status and FEC mode
--
-- IMPORTANT:
--   FEC_MODE currently selects FEC_NONE. CRC-16/CCITT-FALSE is still applied
--   to every frame for error detection.
--
--   FEC_HAMMING_SECDED is reserved for a future optional error-correction
--   stage. Merely changing FEC_MODE to FEC_HAMMING_SECDED does not implement
--   Hamming encoding by itself. A matching FPGA encoder and Python decoder
--   must be added before enabling that mode.
-------------------------------------------------------------------------------

library IEEE;

-- Provides std_logic_vector, which is used for protocol bytes.
use IEEE.STD_LOGIC_1164.ALL;


-------------------------------------------------------------------------------
-- PROTOCOL CONFIGURATION PACKAGE
-------------------------------------------------------------------------------

package protocol_config is

    ---------------------------------------------------------------------------
    -- FORWARD ERROR-CORRECTION MODE IDENTIFIERS
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    -- No forward error correction.
    --
    -- Frames are protected only by CRC-16/CCITT-FALSE.
    --
    -- CRC can detect corrupted frames, but it cannot repair corrupted data.
    -- If the host finds a CRC mismatch, the complete frame must be discarded.
    ---------------------------------------------------------------------------

    constant FEC_NONE :
        natural := 0;

    ---------------------------------------------------------------------------
    -- Reserved identifier for Hamming SECDED error correction.
    --
    -- SECDED means:
    --
    --     Single-Error Correction,
    --     Double-Error Detection
    --
    -- A future Hamming encoder could use this mode to correct one bit error
    -- and detect two bit errors within each protected codeword.
    --
    -- This constant currently defines only the protocol identifier. The
    -- current firmware does not contain a complete Hamming SECDED encoder.
    ---------------------------------------------------------------------------

    constant FEC_HAMMING_SECDED :
        natural := 1;

    ---------------------------------------------------------------------------
    -- Selected forward error-correction mode for this firmware build.
    --
    -- Current setting:
    --
    --     FEC_NONE
    --
    -- frame_transmitter.vhd places the selected mode in the frame status byte,
    -- allowing the Python host to identify the frame encoding.
    --
    -- Do not change this to FEC_HAMMING_SECDED until:
    --
    --   1. An FPGA Hamming encoder has been implemented.
    --   2. Frame-length calculations include the encoded overhead.
    --   3. CRC coverage has been explicitly defined for encoded frames.
    --   4. A matching Python Hamming decoder has been implemented.
    --   5. Simulation fault-injection tests have passed.
    ---------------------------------------------------------------------------

    constant FEC_MODE :
        natural := FEC_NONE;


    ---------------------------------------------------------------------------
    -- PROTOCOL VERSION
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    -- Version number included in every transmitted binary frame.
    --
    -- Current value:
    --
    --     0x02
    --
    -- The Python host compares this byte against its expected protocol version.
    -- A mismatch normally indicates that the FPGA and host software use
    -- different frame layouts or feature definitions.
    --
    -- Increment this value whenever a change would prevent an older host
    -- decoder from interpreting the frame correctly, for example:
    --
    --   - adding or removing metadata fields;
    --   - changing field widths;
    --   - changing field byte order;
    --   - changing CRC coverage;
    --   - enabling an incompatible FEC frame format.
    --
    -- Changes to acquisition timing alone do not normally require a protocol
    -- version increment if the transmitted frame structure remains unchanged.
    ---------------------------------------------------------------------------

    constant PROTOCOL_VERSION :
        std_logic_vector(7 downto 0) := x"02";


    ---------------------------------------------------------------------------
    -- FRAME SYNCHRONIZATION MARKER
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    -- The host searches the incoming UART byte stream for these four bytes:
    --
    --     A5 5A C3 3C
    --
    -- This marker allows the Python software to:
    --
    --   - find the beginning of a spectrum frame;
    --   - recover after opening the serial port halfway through a frame;
    --   - recover after a corrupted or incomplete frame;
    --   - distinguish frame data from unrelated UART bytes.
    --
    -- The four sync bytes are deliberately excluded from the CRC calculation.
    -- CRC coverage begins with the protocol-version byte immediately following
    -- the synchronization marker.
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    -- First synchronization byte.
    ---------------------------------------------------------------------------

    constant SYNC_0 :
        std_logic_vector(7 downto 0) := x"A5";

    ---------------------------------------------------------------------------
    -- Second synchronization byte.
    ---------------------------------------------------------------------------

    constant SYNC_1 :
        std_logic_vector(7 downto 0) := x"5A";

    ---------------------------------------------------------------------------
    -- Third synchronization byte.
    ---------------------------------------------------------------------------

    constant SYNC_2 :
        std_logic_vector(7 downto 0) := x"C3";

    ---------------------------------------------------------------------------
    -- Fourth synchronization byte.
    ---------------------------------------------------------------------------

    constant SYNC_3 :
        std_logic_vector(7 downto 0) := x"3C";

end package protocol_config;