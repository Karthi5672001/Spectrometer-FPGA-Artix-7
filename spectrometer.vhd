library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.defs.all;

entity spectrometer is
    port (
        GCLK : in std_logic;
        BTN0 : in std_logic;
        BTN1 : in std_logic;
        LD0_R : out std_logic;
        LD0_G : out std_logic;
        LD0_B : out std_logic;
        LD1 : out std_logic;
        LD2 : out std_logic;
        TX_USB : out std_logic;
        RX_USB : in std_logic;
        GPIO1 : out std_logic;
        GPIO3 : in std_logic;
        GPIO4 : in std_logic;
        GPIO5 : in std_logic;
        GPIO6 : in std_logic;
        GPIO7 : in std_logic;
        GPIO8 : in std_logic;
        GPIO9 : in std_logic;
        GPIO10 : in std_logic;
        GPIO11 : in std_logic;
        GPIO12 : in std_logic;
        GPIO13 : in std_logic;
        GPIO14 : in std_logic;
        GPIO20 : in std_logic;
        GPIO21 : out std_logic;
        GPIO22 : out std_logic;
        GPIO36 : in std_logic;
        GPIO45 : out std_logic;
        GPIO46 : out std_logic;
        GPIO47 : out std_logic;
        GPIO48 : in std_logic
    );
end entity spectrometer;

architecture Behavioral of spectrometer is
    signal devClk   : std_logic := '0';
    signal devStart : std_logic := '1';
    signal eos      : std_logic;
    signal dataClk  : std_logic;
    signal adcClock : std_logic := '0';
    signal adcData  : std_logic_vector(11 downto 0);
    signal sysClk   : std_logic;
    signal fastClk  : std_logic;

    signal reset         : std_logic := '1';
    signal fastResetMeta : std_logic := '1';
    signal fastReset     : std_logic := '1';

    signal acquisitionTrigger : std_logic := '0';
    signal driverDone          : std_logic := '1';
    signal driverDoneFastMeta     : std_logic := '1';
    signal driverDoneFastSync     : std_logic := '1';
    signal driverDoneFastPrevious : std_logic := '1';
    signal driverDoneFastRising   : std_logic := '0';

    signal readoutDone        : std_logic := '1';
    signal readoutDoneSysMeta : std_logic := '1';
    signal readoutDoneSys     : std_logic := '1';
    signal readoutAddress     : std_logic_vector(8 downto 0) := (others => '0');
    signal readoutData        : std_logic_vector(15 downto 0);

    signal binaryTxByte  : std_logic_vector(7 downto 0) := (others => '0');
    signal binaryTxValid : std_logic := '0';
    signal binaryTxWait  : std_logic := '1';
    signal fastTxReady   : std_logic := '0';

    signal parameters : parameterList_type := defaultParameter;
    signal usb  : serialComms_type;
    signal nano : serialComms_type;
    signal debug  : std_logic_vector(7 downto 0);
    signal ledRgb : std_logic_vector(2 downto 0);
    signal integrationTimeReg : integer := defaultParameter.driver.integrationTime;
    
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of fastResetMeta         : signal is "TRUE";
    attribute ASYNC_REG of fastReset             : signal is "TRUE";
    attribute ASYNC_REG of driverDoneFastMeta    : signal is "TRUE";
    attribute ASYNC_REG of driverDoneFastSync    : signal is "TRUE";
    attribute ASYNC_REG of readoutDoneSysMeta    : signal is "TRUE";
    attribute ASYNC_REG of readoutDoneSys        : signal is "TRUE";

    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of readoutAddress : signal is "TRUE";
    attribute DONT_TOUCH of readoutData    : signal is "TRUE";
    attribute DONT_TOUCH of binaryTxByte   : signal is "TRUE";
    attribute DONT_TOUCH of binaryTxValid  : signal is "TRUE";
    attribute DONT_TOUCH of binaryTxWait   : signal is "TRUE";
    attribute DONT_TOUCH of fastTxReady    : signal is "TRUE";
begin
    GPIO22 <= devClk;
    GPIO21 <= devStart;
    eos <= GPIO20;
    dataClk <= GPIO36;
    GPIO1 <= adcClock;

    adcData(11) <= GPIO14;
    adcData(10) <= GPIO13;
    adcData(9)  <= GPIO12;
    adcData(8)  <= GPIO11;
    adcData(7)  <= GPIO10;
    adcData(6)  <= GPIO9;
    adcData(5)  <= GPIO8;
    adcData(4)  <= GPIO7;
    adcData(3)  <= GPIO6;
    adcData(2)  <= GPIO5;
    adcData(1)  <= GPIO4;
    adcData(0)  <= GPIO3;

    GPIO47 <= '1';
    GPIO45 <= usb.rxCmd.valid;
    GPIO46 <= nano.rxCmd.valid;

    CLK_GEN: pll
        port map (
            clk_out1 => sysClk,
            clk_out2 => fastClk,
            reset    => '0',
            clk_in1  => GCLK
        );

    ledRgb <= debug(6 downto 4);
    LD0_R <= not ledRgb(0);
    LD0_G <= not ledRgb(1);
    LD0_B <= not ledRgb(2);
    LD1 <= debug(0);
    LD2 <= debug(1);

    -- Positional association keeps this top level compatible with the existing
    -- driver component declaration in defs.vhd while the entity formal is
    -- renamed to the VHDL-2008-safe identifier parameters.
    DEV_DRIVER: driver
        port map (
            sysClk,
            acquisitionTrigger,
            parameters,
            driverDone,
            fastClk,
            readoutAddress,
            readoutData,
            devClk,
            devStart,
            dataClk,
            eos,
            adcClock,
            adcData,
            debug
        );

    DRIVER_DONE_TO_FAST_CLOCK: process(fastClk)
    begin
        if rising_edge(fastClk) then
            if fastReset = '1' then
                driverDoneFastMeta <= '1';
                driverDoneFastSync <= '1';
                driverDoneFastPrevious <= '1';
                driverDoneFastRising <= '0';
            else
                driverDoneFastMeta <= driverDone;
                driverDoneFastSync <= driverDoneFastMeta;
                driverDoneFastRising <= driverDoneFastSync and not driverDoneFastPrevious;
                driverDoneFastPrevious <= driverDoneFastSync;
            end if;
        end if;
    end process;

    BINARY_READOUT_INST: binaryReadout
        port map (
            clock => fastClk,
            reset => fastReset,
            trig  => driverDoneFastRising,
            integrationTime => integrationTimeReg,
            txByte  => binaryTxByte,
            txValid => binaryTxValid,
            txWait  => binaryTxWait,
            done => readoutDone,
            addr => readoutAddress,
            data => readoutData
        );

    FAST_USB_TX: fastSerialTx
        generic map (
            CLOCKS_PER_BIT => FAST_UART_CLK_DIV,
            STOP_BITS      => FAST_UART_STOP_BITS
        )
        port map (
            clock => fastClk,
            reset => fastReset,
            data  => binaryTxByte,
            valid => binaryTxValid,
            ready => fastTxReady,
            tx    => TX_USB
        );

    binaryTxWait <= (not fastTxReady) or binaryTxValid;

    -- Positional association avoids the VHDL-2008 reserved identifier used by
    -- the existing commandHandler formal port.
    CMD_HANDLER: commandHandler
        port map (
            sysClk,
            reset,
            nano.rxCmd,
            usb.rxCmd,
            parameters
        );
        
    INTEGRATION_TIME_UPDATE: process(sysClk)
    begin
        if rising_edge(sysClk) then
            integrationTimeReg <= parameters.driver.integrationTime;
        end if;
    end process;
    
    SERIAL_COMMS_USB: serialComms
        port map (
            clock    => sysClk,
            reset    => reset,
            txSerial => open,
            rxSerial => RX_USB,
            txData   => (others => '0'),
            txValid  => '0',
            txWait   => usb.txWait,
            rxCmd    => usb.rxCmd
        );

    SERIAL_COMMS_NANO: serialComms
        port map (
            clock    => sysClk,
            reset    => reset,
            txSerial => open,
            rxSerial => GPIO48,
            txData   => (others => '0'),
            txValid  => '0',
            txWait   => nano.txWait,
            rxCmd    => nano.rxCmd
        );

    READOUT_DONE_TO_SYSTEM_CLOCK: process(sysClk)
    begin
        if rising_edge(sysClk) then
            if reset = '1' then
                readoutDoneSysMeta <= '1';
                readoutDoneSys <= '1';
            else
                readoutDoneSysMeta <= readoutDone;
                readoutDoneSys <= readoutDoneSysMeta;
            end if;
        end if;
    end process;

    ACQUISITION_SCHEDULER: process(sysClk)
        type scheduler_state_type is (
            WAIT_UNTIL_READY,
            START_ACQUISITION,
            WAIT_FOR_DRIVER_BUSY,
            WAIT_FOR_DRIVER_DONE,
            WAIT_FOR_READOUT_BUSY,
            WAIT_FOR_READOUT_DONE
        );
        variable schedulerState : scheduler_state_type := WAIT_UNTIL_READY;
    begin
        if rising_edge(sysClk) then
            acquisitionTrigger <= '0';
            if reset = '1' then
                schedulerState := WAIT_UNTIL_READY;
            else
                case schedulerState is
                    when WAIT_UNTIL_READY =>
                        if driverDone = '1' and readoutDoneSys = '1' then
                            schedulerState := START_ACQUISITION;
                        end if;
                    when START_ACQUISITION =>
                        acquisitionTrigger <= '1';
                        schedulerState := WAIT_FOR_DRIVER_BUSY;
                    when WAIT_FOR_DRIVER_BUSY =>
                        if driverDone = '0' then
                            schedulerState := WAIT_FOR_DRIVER_DONE;
                        end if;
                    when WAIT_FOR_DRIVER_DONE =>
                        if driverDone = '1' then
                            schedulerState := WAIT_FOR_READOUT_BUSY;
                        end if;
                    when WAIT_FOR_READOUT_BUSY =>
                        if readoutDoneSys = '0' then
                            schedulerState := WAIT_FOR_READOUT_DONE;
                        end if;
                    when WAIT_FOR_READOUT_DONE =>
                        if readoutDoneSys = '1' then
                            schedulerState := WAIT_UNTIL_READY;
                        end if;
                end case;
            end if;
        end if;
    end process;

    FAST_RESET_SYNCHRONIZER: process(fastClk)
    begin
        if rising_edge(fastClk) then
            fastResetMeta <= reset;
            fastReset <= fastResetMeta;
        end if;
    end process;

    RESET_GENERATOR: process(sysClk)
        variable resetCount : natural range 0 to 1000000 := 0;
    begin
        if rising_edge(sysClk) then
            if resetCount < 1000000 then
                reset <= '1';
                resetCount := resetCount + 1;
            else
                reset <= '0';
            end if;
        end if;
    end process;
end architecture Behavioral;
