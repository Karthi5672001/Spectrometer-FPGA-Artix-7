library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity fastSerialTx is
    generic (
        CLOCKS_PER_BIT : positive := 60;
        STOP_BITS      : positive := 1
    );

    port (
        clock : in std_logic;
        reset : in std_logic;

        data  : in std_logic_vector(7 downto 0);
        valid : in std_logic;

        ready : out std_logic;
        tx    : out std_logic
    );
end fastSerialTx;


architecture Behavioral of fastSerialTx is

    type state_type is (
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BITS_STATE
    );

    signal state : state_type := IDLE;

    signal clockCount :
        natural range 0 to CLOCKS_PER_BIT - 1 := 0;

    signal bitIndex :
        natural range 0 to 7 := 0;

    signal stopIndex :
        natural range 0 to STOP_BITS - 1 := 0;

    signal shiftRegister :
        std_logic_vector(7 downto 0) := (others => '0');

    signal txInternal :
        std_logic := '1';

    signal readyInternal :
        std_logic := '1';

begin

    tx    <= txInternal;
    ready <= readyInternal;


    TRANSMIT_PROCESS: process(clock)
    begin
        if rising_edge(clock) then

            if reset = '1' then
                state <= IDLE;

                clockCount <= 0;
                bitIndex   <= 0;
                stopIndex  <= 0;

                shiftRegister <= (others => '0');

                txInternal    <= '1';
                readyInternal <= '1';

            else
                case state is

                    -----------------------------------------------------------
                    -- Wait for valid data.
                    --
                    -- A byte is accepted when both ready and valid are high.
                    -----------------------------------------------------------

                    when IDLE =>
                        txInternal    <= '1';
                        readyInternal <= '1';

                        clockCount <= 0;
                        bitIndex   <= 0;
                        stopIndex  <= 0;

                        if valid = '1' then
                            shiftRegister <= data;

                            readyInternal <= '0';
                            state <= START_BIT;
                        end if;


                    -----------------------------------------------------------
                    -- Start bit: logic low for CLOCKS_PER_BIT clock cycles.
                    -----------------------------------------------------------

                    when START_BIT =>
                        txInternal    <= '0';
                        readyInternal <= '0';

                        if clockCount = CLOCKS_PER_BIT - 1 then
                            clockCount <= 0;
                            bitIndex   <= 0;

                            state <= DATA_BITS;
                        else
                            clockCount <= clockCount + 1;
                        end if;


                    -----------------------------------------------------------
                    -- Eight data bits, least-significant bit first.
                    -----------------------------------------------------------

                    when DATA_BITS =>
                        txInternal    <= shiftRegister(bitIndex);
                        readyInternal <= '0';

                        if clockCount = CLOCKS_PER_BIT - 1 then
                            clockCount <= 0;

                            if bitIndex = 7 then
                                stopIndex <= 0;
                                state <= STOP_BITS_STATE;
                            else
                                bitIndex <= bitIndex + 1;
                            end if;
                        else
                            clockCount <= clockCount + 1;
                        end if;


                    -----------------------------------------------------------
                    -- Stop bit or bits: logic high.
                    -----------------------------------------------------------

                    when STOP_BITS_STATE =>
                        txInternal    <= '1';
                        readyInternal <= '0';

                        if clockCount = CLOCKS_PER_BIT - 1 then
                            clockCount <= 0;

                            if stopIndex = STOP_BITS - 1 then
                                readyInternal <= '1';
                                state <= IDLE;
                            else
                                stopIndex <= stopIndex + 1;
                            end if;
                        else
                            clockCount <= clockCount + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end Behavioral;