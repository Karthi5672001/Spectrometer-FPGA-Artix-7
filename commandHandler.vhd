library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.defs.all;


entity commandHandler is
    port (
        clock:     in  std_logic;
        reset:     in  std_logic;
        nanoCmd:   in  cmd_type;
        usbCmd:    in  cmd_type;
        parameter: out parameterList_type
    );
end commandHandler;


architecture Behavioral of commandHandler is
begin


CMD_DECODER: process(clock)
    variable nanoCmdPending: cmd_type := CMD_RESET;
    variable usbCmdPending:  cmd_type := CMD_RESET;
    variable cmd:            cmd_type := CMD_RESET;
    variable newPeriod:      natural;
begin
    if rising_edge(clock) then
        if reset = '1' then
            parameter <= defaultParameter;

            nanoCmdPending := CMD_RESET;
            usbCmdPending  := CMD_RESET;
            cmd            := CMD_RESET;

        else
            cmd.valid := '0';

            -- Store incoming commands until they can be processed.
            if nanoCmd.valid = '1' then
                nanoCmdPending := nanoCmd;
            end if;

            if usbCmd.valid = '1' then
                usbCmdPending := usbCmd;
            end if;

            -- Process one command per clock. Nano retains priority.
            if nanoCmdPending.valid = '1' then
                cmd := nanoCmdPending;
                nanoCmdPending.valid := '0';

            elsif usbCmdPending.valid = '1' then
                cmd := usbCmdPending;
                usbCmdPending.valid := '0';
            end if;

            if cmd.valid = '1' then
                case cmd.cmdType is

                    -- Driver integration time
                    when x"1000" =>
                        parameter.driver.integrationTime <=
                            to_integer(unsigned(cmd.data));

                    -- Driver-generated test data
                    when x"1F00" =>
                        parameter.driver.useTestData <= cmd.data(0);

                    -- Readout-generated test data
                    when x"2F00" =>
                        parameter.readout.useTestData <= cmd.data(0);

                    -- Repetition period in system-clock cycles
                    when x"3000" =>
                        newPeriod := to_integer(unsigned(cmd.data));

                        if newPeriod = 0 then
                            parameter.repPeriod <= 1;
                        else
                            parameter.repPeriod <= newPeriod;
                        end if;

                    when others =>
                        null;

                end case;
            end if;
        end if;
    end if;
end process;


end Behavioral;