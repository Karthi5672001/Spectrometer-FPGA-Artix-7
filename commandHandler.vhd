-- Use IEEE library
library IEEE;
-- Allows use of std_logic
use IEEE.STD_LOGIC_1164.ALL;
-- Allows use of more arithmetic options, and signed and unsigned
use IEEE.NUMERIC_STD.ALL;
-- Import everything from the package named defs; imports all the constants, records, functions and types defined there
use work.defs.all; 

-- Decodes received commands and updates the FPGA configuration parameters
entity commandHandler is
    port (
        -- System clock used to process incoming commands
        clock:     in  std_logic;
        -- Restores all parameters to their default values
        reset:     in  std_logic;
        -- Command received from the Nano serial interface
        nanoCmd:   in  cmd_type;
        -- Command received from the USB serial interface
        usbCmd:    in  cmd_type;
        -- Shared configuration structure used by the acquisition and readout logic
        parameter: out parameterList_type
    );
end commandHandler;

-- Command Flow
--
-- nanoCmd / usbCmd
--          ↓
--     commandHandler
--          ↓
--     parameter structure
--          ↓
--   driver / binaryReadout
--
-- Supported Commands:
--   0x1000 : Set integration time
--   0x1F00 : Driver test-data enable
--   0x2F00 : Readout test-data enable
--   0x3000 : Acquisition repetition period

architecture Behavioral of commandHandler is
begin


CMD_DECODER: process(clock)
    -- Stores the most recently received Nano command awaiting execution
    variable nanoCmdPending: cmd_type := CMD_RESET;
    -- Stores the most recently received USB command awaiting execution
    variable usbCmdPending:  cmd_type := CMD_RESET;
    -- Command currently being executed
    variable cmd:            cmd_type := CMD_RESET;
    -- Temporary storage used when updating the acquisition repetition period
    variable newPeriod:      natural;
begin
    if rising_edge(clock) then
        -- Temporary storage used when updating the acquisition repetition period
        if reset = '1' then
            parameter <= defaultParameter;
            nanoCmdPending := CMD_RESET;
            usbCmdPending  := CMD_RESET;
            cmd            := CMD_RESET;

        else
            -- Default assumption: No command is currently being processed
            cmd.valid := '0';

            -- Store incoming commands until they can be processed
            if nanoCmd.valid = '1' then
                nanoCmdPending := nanoCmd;
            end if;

            if usbCmd.valid = '1' then
                usbCmdPending := usbCmd;
            end if;

            -- Process one command per clock
            -- Nano retains priority
            if nanoCmdPending.valid = '1' then
                cmd := nanoCmdPending;
                nanoCmdPending.valid := '0';
            
            -- Execute pending USB command if no Nano command is waiting
            elsif usbCmdPending.valid = '1' then
                cmd := usbCmdPending;
                usbCmdPending.valid := '0';
            end if;

            -- Only run the command decoder when a complete command is available
            if cmd.valid = '1' then
                case cmd.cmdType is

                    -- Update detector integration time
                    when x"1000" =>
                        parameter.driver.integrationTime <=
                            to_integer(unsigned(cmd.data));

                    -- Enable or disable internally generated test data for the acquisition driver
                    when x"1F00" =>
                        parameter.driver.useTestData <= cmd.data(0);

                    -- Enable or disable test-pattern generation within the readout path
                    when x"2F00" =>
                        parameter.readout.useTestData <= cmd.data(0);

                    -- Repetition period in system-clock cycles
                    when x"3000" =>
                        newPeriod := to_integer(unsigned(cmd.data));
                        
                        -- Prevent an invalid zero-period configuration
                        if newPeriod = 0 then
                            parameter.repPeriod <= 1;
                        else
                            -- Update automatic acquisition repetition period
                            parameter.repPeriod <= newPeriod;
                        end if;
                        
                    -- Ignore unsupported command identifiers
                    when others =>
                        null;

                end case;
            end if;
        end if;
    end if;
end process;


end Behavioral;