library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.env.all;

use work.defs.all;

entity tb_ram_test is
end tb_ram_test;

architecture Simulation of tb_ram_test is

    ------------------------------------------------------------------------
    -- Clock
    ------------------------------------------------------------------------

    constant CLOCK_PERIOD : time := 10 ns;

    signal clka : std_logic := '0';
    signal clkb : std_logic := '0';

    ------------------------------------------------------------------------
    -- Port A
    ------------------------------------------------------------------------

    signal ena :
        std_logic := '0';

    signal wea :
        std_logic_vector(0 downto 0) := "0";

    signal addra :
        std_logic_vector(8 downto 0) := (others => '0');

    signal dina :
        std_logic_vector(15 downto 0) := (others => '0');

    signal douta :
        std_logic_vector(15 downto 0);

    ------------------------------------------------------------------------
    -- Port B
    ------------------------------------------------------------------------

    signal enb :
        std_logic := '0';

    signal web :
        std_logic_vector(0 downto 0) := "0";

    signal addrb :
        std_logic_vector(8 downto 0) := (others => '0');

    signal dinb :
        std_logic_vector(15 downto 0) := (others => '0');

    signal doutb :
        std_logic_vector(15 downto 0);

begin

    ------------------------------------------------------------------------
    -- Clock generation
    ------------------------------------------------------------------------

    clka <= not clka after CLOCK_PERIOD / 2;
    clkb <= not clkb after CLOCK_PERIOD / 2;

    ------------------------------------------------------------------------
    -- DUT
    ------------------------------------------------------------------------

    DUT : blk_mem_gen_0
        port map
        (
            clka  => clka,
            ena   => ena,
            wea   => wea,
            addra => addra,
            dina  => dina,
            douta => douta,

            clkb  => clkb,
            enb   => enb,
            web   => web,
            addrb => addrb,
            dinb  => dinb,
            doutb => doutb
        );

    ------------------------------------------------------------------------
    -- Test process
    ------------------------------------------------------------------------

    STIMULUS : process
    begin

        report
            "Starting BRAM test"
            severity note;

        --------------------------------------------------------------------
        -- Write pattern through Port A
        --------------------------------------------------------------------

        ena <= '1';
        wea <= "1";

        for i in 0 to 287 loop

            wait until rising_edge(clka);

            addra <= std_logic_vector(
                        to_unsigned(i, addra'length));

            dina <= std_logic_vector(
                       to_unsigned(i + 1000, dina'length));

        end loop;

        wait until rising_edge(clka);

        wea <= "0";

        --------------------------------------------------------------------
        -- Read pattern back through Port B
        --------------------------------------------------------------------

        enb <= '1';

        for i in 0 to 287 loop

            addrb <= std_logic_vector(
                        to_unsigned(i, addrb'length));

            ----------------------------------------------------------------
            -- Block RAM output is registered. Allow latency.
            ----------------------------------------------------------------

            wait until rising_edge(clkb);
            wait until rising_edge(clkb);

            assert unsigned(doutb) =
                   to_unsigned(i + 1000, 16)
                report
                    "RAM mismatch at address " &
                    integer'image(i) &
                    ". Expected " &
                    integer'image(i + 1000) &
                    ", received " &
                    integer'image(
                        to_integer(unsigned(doutb)))
                severity failure;

        end loop;

        report
            "PASS - Verified 288 RAM locations."
            severity note;

        stop;
        wait;

    end process;

end Simulation;
