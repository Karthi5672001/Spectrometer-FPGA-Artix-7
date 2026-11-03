library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.defs.all;

entity driver is
    port (
        sysClk : in std_logic;
        trig   : in std_logic;
        parameter : in parameterList_type;
        done       : out std_logic;

        readoutClk  : in  std_logic;
        readoutAddr : in  std_logic_vector(8 downto 0);
        readoutData : out std_logic_vector(15 downto 0);

        devClk   : out std_logic;
        devStart : buffer std_logic;
        dataClk  : in std_logic;
        EOS      : in std_logic;

        ADC_clock : out std_logic;
        ADC_data  : in  std_logic_vector(11 downto 0);
        debug     : out std_logic_vector(7 downto 0)
    );
end entity driver;

architecture Behavioral of driver is
    constant T_ST_HIGH_MIN              : natural := 6;
    constant START_LOW_TIME             : natural := 1000;
    constant FIRST_WRITE_SETUP_COUNT    : natural := 92;
    constant DEV_START_SYNC_COMPENSATION: natural := 2;

    signal writeEnable : std_logic_vector(0 downto 0) := (others => '0');
    signal writeAddr   : std_logic_vector(8 downto 0) := (others => '0');
    signal writeData   : std_logic_vector(15 downto 0) := (others => '0');
    signal ADC_data_z  : std_logic_vector(11 downto 0) := (others => '0');

    signal devStartDataMeta     : std_logic := '1';
    signal devStartDataSync     : std_logic := '1';
    signal devStartDataPrevious : std_logic := '1';
    signal devStartFallingData  : std_logic := '0';

    signal dataStorageDone     : std_logic := '1';
    signal dataStorageDoneMeta : std_logic := '1';
    signal dataStorageDoneSync : std_logic := '1';

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of devStartDataMeta     : signal is "TRUE";
    attribute ASYNC_REG of devStartDataSync     : signal is "TRUE";
    attribute ASYNC_REG of dataStorageDoneMeta  : signal is "TRUE";
    attribute ASYNC_REG of dataStorageDoneSync  : signal is "TRUE";

    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of ADC_data_z  : signal is "TRUE";
    attribute DONT_TOUCH of writeEnable : signal is "TRUE";
    attribute DONT_TOUCH of writeAddr   : signal is "TRUE";
    attribute DONT_TOUCH of writeData   : signal is "TRUE";
begin
    ADC_clock <= dataClk;
    writeData <= "0000" & ADC_data_z;

    DEV_START_TO_DATA_CLOCK: process(dataClk)
    begin
        if rising_edge(dataClk) then
            devStartDataMeta <= devStart;
            devStartDataSync <= devStartDataMeta;
            devStartFallingData <= devStartDataPrevious and not devStartDataSync;
            devStartDataPrevious <= devStartDataSync;
        end if;
    end process;

    DATA_DONE_TO_SYSTEM_CLOCK: process(sysClk)
    begin
        if rising_edge(sysClk) then
            dataStorageDoneMeta <= dataStorageDone;
            dataStorageDoneSync <= dataStorageDoneMeta;
        end if;
    end process;

    DEVICE_DRIVER: process(sysClk)
        type driver_state_type is (DRIVER_IDLE, DRIVER_TIMING, DRIVER_WAIT_STORAGE_DONE);
        variable driverState    : driver_state_type := DRIVER_IDLE;
        variable clockPhase     : std_logic := '0';
        variable integrationCount : natural := MIN_INTEGRATION_TIME;
        variable startHighTime  : natural := T_ST_HIGH_MIN;
        variable timingCount    : natural := 0;
        variable storageBusySeen: boolean := false;
        variable storageDoneSeen: boolean := false;
        variable timingFinished : boolean := false;
    begin
        if rising_edge(sysClk) then
            devClk <= clockPhase;
            clockPhase := not clockPhase;

            case driverState is
                when DRIVER_IDLE =>
                    done <= '1';
                    devStart <= '1';
                    storageBusySeen := false;
                    storageDoneSeen := false;
                    timingFinished := false;

                    if trig = '1' then
                        integrationCount := parameter.driver.integrationTime;
                        if integrationCount < MIN_INTEGRATION_TIME then
                            integrationCount := MIN_INTEGRATION_TIME;
                        end if;
                        if integrationCount > MAX_INTEGRATION_TIME then
                            integrationCount := MAX_INTEGRATION_TIME;
                        end if;
                        if integrationCount > 48 then
                            startHighTime := integrationCount - 48;
                        else
                            startHighTime := T_ST_HIGH_MIN;
                        end if;
                        if startHighTime < T_ST_HIGH_MIN then
                            startHighTime := T_ST_HIGH_MIN;
                        end if;

                        timingCount := 0;
                        storageBusySeen := false;
                        storageDoneSeen := false;
                        timingFinished := false;
                        done <= '0';
                        driverState := DRIVER_TIMING;
                    end if;

                when DRIVER_TIMING =>
                    done <= '0';

                    if not storageBusySeen then
                        if dataStorageDoneSync = '0' then
                            storageBusySeen := true;
                        end if;
                    elsif dataStorageDoneSync = '1' then
                        storageDoneSeen := true;
                    end if;

                    if clockPhase = '0' then
                        if timingCount < startHighTime then
                            devStart <= '1';
                        elsif timingCount < startHighTime + START_LOW_TIME then
                            devStart <= '0';
                        else
                            devStart <= '1';
                            timingFinished := true;
                        end if;
                        if not timingFinished then
                            timingCount := timingCount + 1;
                        end if;
                    end if;

                    if timingFinished then
                        if storageDoneSeen then
                            done <= '1';
                            driverState := DRIVER_IDLE;
                        else
                            driverState := DRIVER_WAIT_STORAGE_DONE;
                        end if;
                    end if;

                when DRIVER_WAIT_STORAGE_DONE =>
                    done <= '0';
                    devStart <= '1';
                    if not storageBusySeen then
                        if dataStorageDoneSync = '0' then
                            storageBusySeen := true;
                        end if;
                    elsif dataStorageDoneSync = '1' then
                        storageDoneSeen := true;
                    end if;
                    if storageDoneSeen then
                        done <= '1';
                        driverState := DRIVER_IDLE;
                    end if;
            end case;

            case driverState is
                when DRIVER_IDLE              => debug(3 downto 0) <= "0000";
                when DRIVER_TIMING            => debug(3 downto 0) <= "0001";
                when DRIVER_WAIT_STORAGE_DONE => debug(3 downto 0) <= "0010";
            end case;
        end if;
    end process;

    DATA_LATCH: process(dataClk)
    begin
        if falling_edge(dataClk) then
            ADC_data_z <= ADC_data;
        end if;
    end process;

    STORE_DATA: process(dataClk)
        type storage_state_type is (STORAGE_IDLE, STORAGE_WAIT_PIXEL_WINDOW, STORAGE_WRITE, STORAGE_FINISH);
        variable storageState : storage_state_type := STORAGE_IDLE;
        variable timingIndex  : natural := 0;
        variable sampleIndex  : natural range 0 to DATA_LEN - 1 := 0;
    begin
        if rising_edge(dataClk) then
            writeEnable(0) <= '0';

            case storageState is
                when STORAGE_IDLE =>
                    dataStorageDone <= '1';
                    timingIndex := 0;
                    sampleIndex := 0;
                    writeAddr <= (others => '0');
                    if devStartFallingData = '1' then
                        dataStorageDone <= '0';
                        timingIndex := 1 + DEV_START_SYNC_COMPENSATION;
                        storageState := STORAGE_WAIT_PIXEL_WINDOW;
                    end if;

                when STORAGE_WAIT_PIXEL_WINDOW =>
                    dataStorageDone <= '0';
                    if timingIndex >= FIRST_WRITE_SETUP_COUNT then
                        sampleIndex := 0;
                        writeAddr <= (others => '0');
                        writeEnable(0) <= '1';
                        storageState := STORAGE_WRITE;
                    else
                        timingIndex := timingIndex + 1;
                    end if;

                when STORAGE_WRITE =>
                    dataStorageDone <= '0';
                    if sampleIndex = DATA_LEN - 1 then
                        writeEnable(0) <= '0';
                        storageState := STORAGE_FINISH;
                    else
                        sampleIndex := sampleIndex + 1;
                        writeAddr <= std_logic_vector(to_unsigned(sampleIndex, writeAddr'length));
                        writeEnable(0) <= '1';
                    end if;

                when STORAGE_FINISH =>
                    writeEnable(0) <= '0';
                    dataStorageDone <= '1';
                    storageState := STORAGE_IDLE;
            end case;

            case storageState is
                when STORAGE_IDLE             => debug(6 downto 4) <= "000";
                when STORAGE_WAIT_PIXEL_WINDOW => debug(6 downto 4) <= "001";
                when STORAGE_WRITE            => debug(6 downto 4) <= "010";
                when STORAGE_FINISH           => debug(6 downto 4) <= "011";
            end case;
            debug(7) <= writeEnable(0);
        end if;
    end process;

    MEM_MAP: blk_mem_gen_0
        port map (
            clka  => dataClk,
            ena   => '1',
            wea   => writeEnable,
            addra => writeAddr,
            dina  => writeData,
            douta => open,
            clkb  => readoutClk,
            enb   => '1',
            web   => (others => '0'),
            addrb => readoutAddr,
            dinb  => (others => '0'),
            doutb => readoutData
        );
end architecture Behavioral;
