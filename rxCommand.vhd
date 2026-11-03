library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.defs.all;


entity rxCommand is
    port (
        clock:     in  std_logic;
        din:       in  std_logic_vector(7 downto 0);
        din_valid: in  std_logic;
        cmd:       out cmd_type
    );
end rxCommand;


architecture Behavioral of rxCommand is
begin


RX_FRAME_DECODER: process(clock)
    variable i:    natural range 0 to 8 := 0;
    variable t:    natural range 0 to 10000001 := 0;
    variable data: std_logic_vector(47 downto 0) := (others => '0');

    constant HEADER: std_logic_vector(15 downto 0) := x"EF00";
begin
    if rising_edge(clock) then
        cmd.valid <= '0';

        if din_valid = '1' then
            t := 0;

            case i is
                when 0 =>
                    if din = HEADER(15 downto 8) then
                        i := 1;
                    end if;

                when 1 =>
                    if din = HEADER(7 downto 0) then
                        i := 2;
                        data := (others => '0');

                    elsif din = HEADER(15 downto 8) then
                        -- Treat this byte as a possible new first
                        -- header byte.
                        i := 1;

                    else
                        i := 0;
                    end if;

                when others =>
                    data := data(39 downto 0) & din;

                    if i >= 7 then
                        i := 0;

                        cmd.cmdType <= data(47 downto 32);
                        cmd.data    <= data(31 downto 0);
                        cmd.valid   <= '1';
                    else
                        i := i + 1;
                    end if;
            end case;

        elsif i /= 0 then
            if t >= 10000000 then
                i := 0;
                t := 0;
                data := (others => '0');
            else
                t := t + 1;
            end if;

        else
            t := 0;
        end if;
    end if;
end process;


end Behavioral;