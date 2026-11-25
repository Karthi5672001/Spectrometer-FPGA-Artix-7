-------------------------------------------------------------------------------
-- FILE: reset_sync.vhd
--
-- PURPOSE:
--   Safely distribute an asynchronous reset into one FPGA clock domain.
--
--   Reset assertion is asynchronous:
--     If async_reset becomes '1', reset_out becomes '1' immediately,
--     without waiting for a clock edge.
--
--   Reset release is synchronous:
--     When async_reset returns to '0', reset_out remains asserted until
--     the reset release has passed through two flip-flops clocked by clock.
--
--   This structure is commonly described as:
--
--       asynchronous assertion, synchronous deassertion
--
-- ROLE IN THE SPECTROMETER FIRMWARE:
--
--   The Clocking Wizard produces a locked signal. Until the Clocking Wizard
--   has locked onto the 12 MHz board oscillator, its generated 10 MHz and
--   60 MHz clocks must not be trusted.
--
--   spectrometer_top.vhd creates:
--
--       pll_reset <= not pll_locked;
--
--   Therefore:
--
--       pll_locked = '0'  -> pll_reset = '1' -> logic held in reset
--       pll_locked = '1'  -> pll_reset = '0' -> reset released safely
--
--   One reset_sync instance generates sys_reset for the 10 MHz system-clock
--   domain. A second instance generates fast_reset for the 60 MHz readout
--   and UART-transmission domain.
--
--   Each clock domain requires a separate reset synchronizer because the
--   reset must be released using edges of the destination clock.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-------------------------------------------------------------------------------
-- ENTITY
-------------------------------------------------------------------------------

entity reset_sync is
    port (
        -----------------------------------------------------------------------
        -- Destination clock.
        --
        -- reset_out will be released synchronously relative to this clock.
        -----------------------------------------------------------------------
        clock : in std_logic;

        -----------------------------------------------------------------------
        -- Asynchronous, active-high reset input.
        --
        -- In this design, async_reset is normally driven from:
        --
        --     not pll_locked
        --
        -- Reset assertion does not depend on clock activity.
        -----------------------------------------------------------------------
        async_reset : in std_logic;

        -----------------------------------------------------------------------
        -- Active-high reset output for the destination clock domain.
        --
        -- Assertion is asynchronous.
        -- Deassertion is synchronized through two clocked registers.
        -----------------------------------------------------------------------
        reset_out : out std_logic
    );
end entity reset_sync;


-------------------------------------------------------------------------------
-- ARCHITECTURE
-------------------------------------------------------------------------------

architecture rtl of reset_sync is

    ---------------------------------------------------------------------------
    -- First reset-release synchronization stage.
    --
    -- This is the register most likely to experience a recovery/removal timing
    -- violation or metastability when async_reset is released near a rising
    -- clock edge.
    --
    -- Downstream logic does not use r1 directly.
    ---------------------------------------------------------------------------

    signal r1 : std_logic := '1';

    ---------------------------------------------------------------------------
    -- Second reset-release synchronization stage.
    --
    -- This register receives the output of r1 one clock later. The extra clock
    -- period gives any metastability in r1 time to settle before reset_out is
    -- released to the rest of the clock domain.
    ---------------------------------------------------------------------------

    signal r2 : std_logic := '1';


    ---------------------------------------------------------------------------
    -- Vivado synchronization-chain attributes.
    --
    -- These attributes tell Vivado that r1 and r2 form an intentional
    -- asynchronous synchronization chain.
    --
    -- Vivado can then:
    --   - keep the two registers physically close together;
    --   - avoid merging or restructuring the synchronization chain;
    --   - account for the chain during CDC and methodology analysis;
    --   - maximize the available metastability settling time.
    ---------------------------------------------------------------------------

    attribute ASYNC_REG : string;

    attribute ASYNC_REG of r1 : signal is "TRUE";
    attribute ASYNC_REG of r2 : signal is "TRUE";

begin

    ---------------------------------------------------------------------------
    -- RESET SYNCHRONIZER
    --
    -- async_reset is included in the sensitivity list so that reset assertion
    -- occurs immediately.
    --
    -- Reset release occurs only inside rising_edge(clock), so the output reset
    -- cannot be removed at an arbitrary point in the destination clock cycle.
    ---------------------------------------------------------------------------

    RESET_SYNCHRONIZER : process(clock, async_reset)
    begin

        -----------------------------------------------------------------------
        -- Asynchronous reset assertion.
        --
        -- Both synchronization registers are immediately set to '1'.
        -- Because reset_out is driven by r2, reset_out is also asserted.
        --
        -- This branch works even if clock has stopped or the PLL has not yet
        -- produced a stable clock.
        -----------------------------------------------------------------------

        if async_reset = '1' then

            r1 <= '1';
            r2 <= '1';

        -----------------------------------------------------------------------
        -- Synchronous reset release.
        --
        -- On the first rising clock edge after async_reset becomes '0':
        --
        --     r1 becomes '0'
        --     r2 remains '1' because it receives the previous value of r1
        --
        -- On the second rising clock edge:
        --
        --     r1 remains '0'
        --     r2 becomes '0'
        --
        -- reset_out therefore remains asserted for two destination-clock
        -- edges after asynchronous reset is removed.
        -----------------------------------------------------------------------

        elsif rising_edge(clock) then

            r1 <= '0';
            r2 <= r1;

        end if;

    end process RESET_SYNCHRONIZER;


    ---------------------------------------------------------------------------
    -- The second synchronization stage drives the reset used by the rest of
    -- the destination clock domain.
    ---------------------------------------------------------------------------

    reset_out <= r2;

end architecture rtl;
