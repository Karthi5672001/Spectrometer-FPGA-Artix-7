-- Use IEEE library
library IEEE;
-- Allows use of std_logic
use IEEE.STD_LOGIC_1164.ALL;
-- Allows use of more arithmetic options, and signed and unsigned
use IEEE.NUMERIC_STD.ALL;
-- Import everything from the package named defs; imports all the constants, records, functions and types defined there
use work.defs.all; 

-- Declaration is top-level interface of FPGA board, corresponding to the physical pins on the XC7A35T FPGA
-- Inputs are in; FPGA can read these but cannot drive them
-- Outputs are out; FPGA writes these values
-- Used in conjunction with constraints file
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

-- Architecture declaration area
-- Defines Internal wires, State, Modules and Logic
architecture Behavioral of spectrometer is
    -- CCD pixel clock
    signal devClk   : std_logic := '0';
    -- Start integration/readout
    signal devStart : std_logic := '1';
    -- End Of Scan
    signal eos      : std_logic;
    -- Data sampling clock
    signal dataClk  : std_logic;
    -- Board samples a 12-bit ADC
    signal adcClock : std_logic := '0';
    signal adcData  : std_logic_vector(11 downto 0);
    -- Clock Signals
    signal sysClk   : std_logic;
    signal fastClk  : std_logic;
    -- Reset signals for startup and clock-domain synchronisation
    signal reset         : std_logic := '1';
    signal fastResetMeta : std_logic := '1';
    signal fastReset     : std_logic := '1';
    -- Signal for taking spectrum
    signal acquisitionTrigger : std_logic := '0';
    
    signal driverDone          : std_logic := '1';
    signal driverDoneFastMeta     : std_logic := '1';
    signal driverDoneFastSync     : std_logic := '1';
    signal driverDoneFastPrevious : std_logic := '1';
    signal driverDoneFastRising   : std_logic := '0';

    signal readoutDone        : std_logic := '1';
    signal readoutDoneSysMeta : std_logic := '1';
    signal readoutDoneSys     : std_logic := '1';
    -- Pixel address/number (smallest number above 288)
    signal readoutAddress     : std_logic_vector(8 downto 0) := (others => '0');
    -- Pixel Intensity (16 bit)
    signal readoutData        : std_logic_vector(15 downto 0);
    -- UART Transmit to feed fastSerialTx:
    -- data byte
    signal binaryTxByte  : std_logic_vector(7 downto 0) := (others => '0');
    -- send now
    signal binaryTxValid : std_logic := '0';
    -- transmitter busy
    signal binaryTxWait  : std_logic := '1';
    -- transmitter ready
    signal fastTxReady   : std_logic := '0';
    
    -- Creates a parameter storage structure
    signal parameters : parameterList_type := defaultParameter;
    -- Serial Communications Structures
    -- USB
    signal usb  : serialComms_type;
    -- Microcontroller interface
    signal nano : serialComms_type;
    signal debug  : std_logic_vector(7 downto 0);
    signal ledRgb : std_logic_vector(2 downto 0);
    -- Integration Time Register, which starts with a default value from defs.vhd, and can be changed with commands from PC
    signal integrationTimeReg : integer := defaultParameter.driver.integrationTime;
    
    -- Used for synchronizers
    attribute ASYNC_REG : string;
    -- This tells Vivado that this signal intentionally crosses clock domains. Do not optimize it away
    attribute ASYNC_REG of fastResetMeta         : signal is "TRUE";
    attribute ASYNC_REG of fastReset             : signal is "TRUE";
    attribute ASYNC_REG of driverDoneFastMeta    : signal is "TRUE";
    attribute ASYNC_REG of driverDoneFastSync    : signal is "TRUE";
    attribute ASYNC_REG of readoutDoneSysMeta    : signal is "TRUE";
    attribute ASYNC_REG of readoutDoneSys        : signal is "TRUE";
    -- This tells Vivado not remove or merge this signal even if you think it is unnecessary
    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of readoutAddress : signal is "TRUE";
    attribute DONT_TOUCH of readoutData    : signal is "TRUE";
    attribute DONT_TOUCH of binaryTxByte   : signal is "TRUE";
    attribute DONT_TOUCH of binaryTxValid  : signal is "TRUE";
    attribute DONT_TOUCH of binaryTxWait   : signal is "TRUE";
    attribute DONT_TOUCH of fastTxReady    : signal is "TRUE";
-- Start of actual hardware logic; connection of the internal wires
begin
    -- Drives internal signals out to FPGA pins
    -- CCD clock
    GPIO22 <= devClk;
    -- Start/trigger pulse
    GPIO21 <= devStart;
    -- CCD Status Inputs
    -- End Of Scan
    eos <= GPIO20;
    -- Pixel clock generated by CCD readout
    dataClk <= GPIO36;
    -- ADC Clock Output
    -- The ADC uses this clock to determine when to present conversion data
    GPIO1 <= adcClock;
    -- Parallel ADC bus
    -- 12 pins, since ADC is 12-bit, so all 12 wires become adcData
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
    -- Debug Outputs
    -- Permanent High: forces GPIO47 high at all times
    GPIO47 <= '1';
    -- USB Command Activity
    -- Whenever a command arrives via USB, GPIO45 goes high.
    GPIO45 <= usb.rxCmd.valid;
    -- Whenever a command arrives via the Nano interface, GPIO46 goes high
    GPIO46 <= nano.rxCmd.valid;
    -- Clock Generation
    -- Instantiates pll, which takes GCLK as input to output sysClk and fastClk
    CLK_GEN: pll
        port map (
            clk_out1 => sysClk,
            clk_out2 => fastClk,
            reset    => '0',
            clk_in1  => GCLK
        );
    -- LED Debug Display
    -- For the aiding of troubleshooting
    ledRgb <= debug(6 downto 4);
    LD0_R <= not ledRgb(0);
    LD0_G <= not ledRgb(1);
    LD0_B <= not ledRgb(2);
    LD1 <= debug(0);
    LD2 <= debug(1);

    -- Connects the top-level FPGA design to the driver module
    -- Left side is port inside the driver module
    -- Right side is signal in spectrometer top level
    DEV_DRIVER: driver
        port map (
            -- sysClk input receives the FPGA system clock
            sysClk      => sysClk,
            -- Trigger connection for beginning aquisition 
            trig        => acquisitionTrigger,
            -- Passes the entire parameter structure into the driver; e.g. parameters.driver.integrationTime
            parameter   => parameters,
            -- When aquisition is completed, driver generates done
            done        => driverDone,
            
            -- Readout
            -- fastClk is used for memory readout
            readoutClk  => fastClk,
            
            -- Readout Memory Interface
            -- readoutAddr is pixel address and readoutData is pixel data
            readoutAddr => readoutAddress,
            readoutData => readoutData,
            
            -- Spectrometer Control Signals
            -- Controls the detector timing
            devClk      => devClk,
            devStart    => devStart,
            -- Spectrometer Feedback
            -- Driver reads these to know where it is in the acquisition cycle
            dataClk     => dataClk,
            EOS         => eos,
            
            -- ADC Interface
            -- Generates ADC clock
            ADC_clock   => adcClock,
            -- Receives ADC samples; where the intensity data enters the FPGA from the ADC
            ADC_data    => adcData,
            -- driver outputs debug signals, which later drive LEDs
            debug       => debug
        );
    
    -- Clock-domain crossing synchroniser and edge detector
    -- Because cannot safely use a signal generated by one clock directly inside another clock domain without synchronisation
    DRIVER_DONE_TO_FAST_CLOCK: process(fastClk)
    begin
        -- Process executes on the rising edge of each clock of fastClk
        if rising_edge(fastClk) then
            -- Reset selection
            if fastReset = '1' then
                -- Initialise everything so that the synchroniser starts in a known state.
                driverDoneFastMeta <= '1';
                driverDoneFastSync <= '1';
                driverDoneFastPrevious <= '1';
                driverDoneFastRising <= '0';
            else
                -- Metastability Filter
                -- Gives any unstable state time to settle before the signal is used 
                driverDoneFastMeta <= driverDone;
                -- Synchronizer
                driverDoneFastSync <= driverDoneFastMeta;
                -- Rising Edge Detection
                -- Generates a one-clock pulse when the signal changes
                driverDoneFastRising <= driverDoneFastSync and not driverDoneFastPrevious;
                -- Saving Previous State
                -- Stores the signal value from the previous fast clock cycle
                driverDoneFastPrevious <= driverDoneFastSync;
            end if;
        end if;
    end process;
    
    -- Instantiates the binaryReadout module
    -- Responsible for taking the completed spectrum from memory and converting it into a stream of bytes for transmission to the PC.
    BINARY_READOUT_INST: binaryReadout
        port map (
            -- Clock is in high speed domain for fast transmission
            clock => fastClk,
            -- Reset
            reset => fastReset,
            -- Tells binaryReadout that new spectrum is ready and to start reading
            trig  => driverDoneFastRising,
            -- Integration Time is passed from binaryReadout to spectrometer
            integrationTime => integrationTimeReg,
            -- Current data byte to send
            txByte  => binaryTxByte,
            -- Valid tells if current byte is ready
            txValid => binaryTxValid,
            -- Wait tells if UART is busy
            txWait  => binaryTxWait,
            -- Tells if spectrum has finished transmitting
            done => readoutDone,
            -- how binaryReadout selects which pixel address to read
            addr => readoutAddress,
            -- pixel value returned from memory.
            data => readoutData
        );
    -- The UART transmitter
    -- Takes parallel bytes and converts them into serial bits and sends them to PC
    FAST_USB_TX: fastSerialTx
        generic map (
            -- Determines baud rate
            CLOCKS_PER_BIT => FAST_UART_CLK_DIV,
            -- Determines the UART frame format
            -- e.g. Start + 8 Data + Stop = 10 bits transmitted for every data byte
            STOP_BITS      => FAST_UART_STOP_BITS
        )
        port map (
            -- UART transmission runs from the fastClk
            clock => fastClk,
            -- Clears the transmitter when resetting
            reset => fastReset,
            -- Data Input byte to transmit
            data  => binaryTxByte,
            -- If a byte is ready to send
            valid => binaryTxValid,
            -- Handshake signal.
            -- The transmitter responds if it is ready for another byte
            ready => fastTxReady,
            -- Physical Output
            -- The serial bitstream leaves the FPGA here
            tx    => TX_USB
        );
    -- binaryTxWait is asserted whenever the UART is busy or a byte is currently being handed to the UART
    -- Preventing binaryReadout from sending the next byte too early
    -- Only true when UART ready AND No byte currently being submitted are true
    binaryTxWait <= (not fastTxReady) or binaryTxValid;

    -- CMD_HANDLER instantiates the command parser module, which receives commands from the USB and Nano 
    -- serial interfaces and updates the FPGA parameter structure
    CMD_HANDLER: commandHandler
        port map (
            -- Runs from the system clock
            clock     => sysClk,
            -- Reset
            reset     => reset,
            -- Connects commands arriving from the Nano interface
            nanoCmd   => nano.rxCmd,
            -- Connects commands arriving from PC
            usbCmd    => usb.rxCmd,
            -- Updates parameter changes from the PC
            parameter => parameters
    );
    
    -- Keeps integrationTimeReg updated with whatever value is currently stored in the parameter structure
    INTEGRATION_TIME_UPDATE: process(sysClk)
    begin
        -- Every rising edge of sysClk
        if rising_edge(sysClk) then
            -- parameters.driver.integrationTime is copied into integrationTimeReg
            integrationTimeReg <= parameters.driver.integrationTime;
        end if;
    end process;
    
    -- Spectrum Data is transmitted through the separate high-speed fastSerialTx
    -- Command traffic and spectrum transmission are separated logically, making it easier to increase throughput without changing the command parser
    
    -- Receives UART commands from the PC through RX_USB and converts them into structured command packets
    SERIAL_COMMS_USB: serialComms
        port map (
            -- Runs on the system clock
            clock    => sysClk,
            -- Resets the UART receiver
            reset    => reset,
            -- Transmitter portion of this module is not being used
            txSerial => open,
            -- Receive Pin where UART commands from python enter
            rxSerial => RX_USB,
            txData   => (others => '0'),
            txValid  => '0',
            txWait   => usb.txWait,
            -- Received Command Output
            rxCmd    => usb.rxCmd
        );
        
    -- Receives UART commands from the Nano interface through GPIO48 and converts them into structured command packets
    SERIAL_COMMS_NANO: serialComms
        port map (
            -- Runs on the system clock
            clock    => sysClk,
            reset    => reset,
            -- Transmitter portion of this module is not being used
            txSerial => open,
            -- Recieve pin
            rxSerial => GPIO48,
            txData   => (others => '0'),
            txValid  => '0',
            txWait   => nano.txWait,
            -- Command Output
            rxCmd    => nano.rxCmd
        );
    -- two-flip-flop synchronizer that safely transfers the readoutDone signal from the fastClk into the sysClk
    READOUT_DONE_TO_SYSTEM_CLOCK: process(sysClk)
    begin
        if rising_edge(sysClk) then
            -- Reset condition
            -- When the FPGA is reset, both synchronizer registers are initialized to '1', to match the default readout complete state
            if reset = '1' then
                readoutDoneSysMeta <= '1';
                readoutDoneSys <= '1';
            else
                -- Metastability filter
                -- Copies the signal coming from the fastClk domain into a register clocked by sysClk
                readoutDoneSysMeta <= readoutDone;
                -- One clock later, the value is sampled again
                -- Giving it one extra clock cycle before the second register samples it dramatically reduces the probability of metastability propagating into the rest of the design
                readoutDoneSys <= readoutDoneSysMeta;
            end if;
        end if;
    end process;
    
    -- Controls acquisition cycle of the spectrometer
    -- top-level state machine that automatically sequences the spectrometer through spectrum acquisition, memory readout, data transmission, and preparation for the next capture
    ACQUISITION_SCHEDULER: process(sysClk)
        type scheduler_state_type is (
        -- Defines all possible states the scheduler can be in
            -- Idle
            WAIT_UNTIL_READY,
            -- Generate acquisition trigger
            START_ACQUISITION,
            -- Checks if driver has started
            WAIT_FOR_DRIVER_BUSY,
            -- Spectrum being acquired
            WAIT_FOR_DRIVER_DONE,
            -- Readout has started
            WAIT_FOR_READOUT_BUSY,
            -- Waits for all bytes transmitted
            WAIT_FOR_READOUT_DONE
        );
        -- This stores the current state
        variable schedulerState : scheduler_state_type := WAIT_UNTIL_READY;
    begin
        -- The scheduler updates once every sysClk cycle
        if rising_edge(sysClk) then
            -- Every clock cycle the trigger is forced low
            acquisitionTrigger <= '0';
            -- 
            if reset = '1' then
                schedulerState := WAIT_UNTIL_READY;
            else
                case schedulerState is
                    -- Start a new acquisition
                    when WAIT_UNTIL_READY =>
                        if driverDone = '1' and readoutDoneSys = '1' then
                            schedulerState := START_ACQUISITION;
                        end if;
                    -- Start taking spectrum
                    when START_ACQUISITION =>
                        acquisitionTrigger <= '1';
                        schedulerState := WAIT_FOR_DRIVER_BUSY;
                    -- Checks if driver has started
                    when WAIT_FOR_DRIVER_BUSY =>
                        if driverDone = '0' then
                            schedulerState := WAIT_FOR_DRIVER_DONE;
                        end if;
                    -- Wait until spectrum is fully captured
                    when WAIT_FOR_DRIVER_DONE =>
                        if driverDone = '1' then
                            schedulerState := WAIT_FOR_READOUT_BUSY;
                        end if;
                    -- Checks if UART readout has started
                    when WAIT_FOR_READOUT_BUSY =>
                        if readoutDoneSys = '0' then
                            schedulerState := WAIT_FOR_READOUT_DONE;
                        end if;
                    -- Wait until the entire spectrum has been sent to the PC
                    when WAIT_FOR_READOUT_DONE =>
                        if readoutDoneSys = '1' then
                            schedulerState := WAIT_UNTIL_READY;
                        end if;
                end case;
            end if;
        end if;
    end process;
    
    -- FAST_RESET_SYNCHRONIZER safely transfers that reset signal into the fast clock domain.
    FAST_RESET_SYNCHRONIZER: process(fastClk)
    begin
        if rising_edge(fastClk) then
            fastResetMeta <= reset;
            fastReset <= fastResetMeta;
        end if;
    end process;

    -- RESET_GENERATOR holds the entire FPGA in reset for the first million system clock cycles after power-up
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
