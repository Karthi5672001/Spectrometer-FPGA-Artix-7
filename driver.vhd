-- Use IEEE library
library IEEE;
-- Allows use of std_logic
use IEEE.STD_LOGIC_1164.ALL;
-- Allows use of more arithmetic options, and signed and unsigned
use IEEE.NUMERIC_STD.ALL;
-- Import everything from the package named defs; imports all the constants, records, functions and types defined there
use work.defs.all; 

-- Interface to Spectrometer
entity driver is
    port (
        -- System Clock: System clock used to run the spectrometer acquisition logic
        sysClk : in std_logic;
        -- Trigger: Pulse that starts a new spectrum acquisition
        trig   : in std_logic;
        -- Parameters: User-configurable settings passed from the command handler to the acquisition engine
        parameter : in parameterList_type;
        -- Done: Indicates whether spectrum acquisition is complete
        done       : out std_logic;

        -- Readout Clock: High-speed clock used for spectrum memory readout
        readoutClk  : in  std_logic;
        -- Readout Address: Address of the requested spectrum sample
        readoutAddr : in  std_logic_vector(8 downto 0);
        -- Readout Data: Pixel intensity value returned from spectrum memory
        readoutData : out std_logic_vector(15 downto 0);

        -- Device Clock: Clock output supplied to the spectrometer detector
        devClk   : out std_logic;
        -- Device Start: Start signal used to initiate a detector acquisition sequence
        devStart : buffer std_logic;
        -- Data Clock: Timing signal received from the detector during readout
        dataClk  : in std_logic;
        -- EOS: End-of-scan indicator from the detector
        EOS      : in std_logic;

        -- ADC Clock: Sampling clock supplied to the ADC
        ADC_clock : out std_logic;
        -- ADC Data: 12-bit digitized intensity value received from the ADC
        ADC_data  : in  std_logic_vector(11 downto 0);
        -- Debug Bus: Internal diagnostic signals used to drive LEDs and aid debugging
        debug     : out std_logic_vector(7 downto 0)
    );
end entity driver;

architecture Behavioral of driver is
    -- Timing Constants
    -- Minimum detector start-pulse width
    constant T_ST_HIGH_MIN              : natural := 6;
    -- Delay between detector acquisition cycles
    constant START_LOW_TIME             : natural := 1000;
    -- Number of clock cycles waited before writing the first valid pixel sample
    constant FIRST_WRITE_SETUP_COUNT    : natural := 92;
    -- Corrects timing offsets introduced by synchronization logic
    constant DEV_START_SYNC_COMPENSATION: natural := 2;

    -- Spectrum Memory Write Interface
    -- BRAM write-enable signal.
    signal writeEnable : std_logic_vector(0 downto 0) := (others => '0');
    -- Address of the spectrum sample currently being stored
    signal writeAddr   : std_logic_vector(8 downto 0) := (others => '0');
    -- Pixel intensity value written into spectrum memory
    signal writeData   : std_logic_vector(15 downto 0) := (others => '0');
    -- Registered (delayed) copy of the ADC sample used for stable storage timing
    signal ADC_data_z  : std_logic_vector(11 downto 0) := (others => '0');
    
    -- devStart Synchronizer Signals
    -- Synchronization stages for detector timing signals crossing clock domains
    signal devStartDataMeta     : std_logic := '1';
    signal devStartDataSync     : std_logic := '1';
    
    -- Previous synchronized detector state used for edge detection
    signal devStartDataPrevious : std_logic := '1';
    -- One-clock pulse indicating that the detector start signal has transitioned high-to-low
    signal devStartFallingData  : std_logic := '0';

    -- Data Storage Completion Signals
    -- Indicates completion of spectrum storage into memory
    signal dataStorageDone     : std_logic := '1';
    -- Synchronizer stages used when transferring acquisition-completion status between clock domains
    signal dataStorageDoneMeta : std_logic := '1';
    signal dataStorageDoneSync : std_logic := '1';

    -- Informs Vivado that the associated registers form a clock-domain synchronizer
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of devStartDataMeta     : signal is "TRUE";
    attribute ASYNC_REG of devStartDataSync     : signal is "TRUE";
    attribute ASYNC_REG of dataStorageDoneMeta  : signal is "TRUE";
    attribute ASYNC_REG of dataStorageDoneSync  : signal is "TRUE";

    -- Prevents Vivado from optimizing away critical acquisition and memory-write signals
    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of ADC_data_z  : signal is "TRUE";
    attribute DONT_TOUCH of writeEnable : signal is "TRUE";
    attribute DONT_TOUCH of writeAddr   : signal is "TRUE";
    attribute DONT_TOUCH of writeData   : signal is "TRUE";
begin
    -- Routes the detector pixel clock directly to the ADC sampling clock input
    ADC_clock <= dataClk;
    -- Converts the 12-bit ADC sample into a 16-bit memory value by padding the upper four bits with zeros
    writeData <= "0000" & ADC_data_z;

    -- Synchronizes devStart into the detector clock domain and generates a one-clock pulse when devStart transitions from high to low
    DEV_START_TO_DATA_CLOCK: process(dataClk)
    begin
        if rising_edge(dataClk) then
            -- First synchronizer register
            devStartDataMeta <= devStart;
            -- Second synchronizer register
            devStartDataSync <= devStartDataMeta;
            -- Falling Edge Detection: Detects 1->0 transition
            devStartFallingData <= devStartDataPrevious and not devStartDataSync;
            devStartDataPrevious <= devStartDataSync;
        end if;
    end process;

    -- Synchronizes the data-storage-complete signal from the detector clock domain into the system clock domain
    DATA_DONE_TO_SYSTEM_CLOCK: process(sysClk)
    begin
        if rising_edge(sysClk) then
            -- Captures the signal
            dataStorageDoneMeta <= dataStorageDone;
            -- Produces a clean synchronized copy
            dataStorageDoneSync <= dataStorageDoneMeta;
        end if;
    end process;
    -- States of spectrometer aquisition logic
    DEVICE_DRIVER: process(sysClk)
        -- Defines the driver's three operating states
        -- DRIVER_IDLE: Waiting for a trigger
        -- DRIVER_TIMING: Generating detector timing signals
        -- DRIVER_WAIT_STORAGE_DONE: Detector readout finished, waiting for all pixel data to be stored
        type driver_state_type is (DRIVER_IDLE, DRIVER_TIMING, DRIVER_WAIT_STORAGE_DONE);
        -- Stores the current state.
        variable driverState    : driver_state_type := DRIVER_IDLE;
        -- Internal phase bit used to generate the detector clock by toggling every sysClk cycle
        variable clockPhase     : std_logic := '0';
        -- Stores the requested integration time used to derive detector timing parameters
        variable integrationCount : natural := MIN_INTEGRATION_TIME;
        -- Tracks the duration of the detector start pulse
        variable startHighTime  : natural := T_ST_HIGH_MIN;
        -- Internal counter used to sequence detector timing events
        variable timingCount    : natural := 0;
        -- Records whether the storage engine has transitioned from idle to busy during the current acquisition
        variable storageBusySeen: boolean := false;
        -- Records whether spectrum storage has completed after previously becoming busy
        variable storageDoneSeen: boolean := false;
        -- Records whether the detector timing sequence has completed
        variable timingFinished : boolean := false;
    -- Heart of the spectrometer acquisition logic
    begin
        -- Generates the detector clock by dividing the system clock by two
        if rising_edge(sysClk) then
            devClk <= clockPhase;
            clockPhase := not clockPhase;
            -- 
            case driverState is
                -- The spectrometer is waiting for a trigger
                when DRIVER_IDLE =>
                    -- Acquisition finished
                    done <= '1';
                    -- Keeps the detector start signal inactive
                    devStart <= '1';
                    -- Resets internal tracking variables
                    storageBusySeen := false;
                    storageDoneSeen := false;
                    timingFinished := false;
                    
                    -- The scheduler has requested a new acquisition
                    if trig = '1' then
                        -- Copies the user-configured integration time into an internal counter
                        integrationCount := parameter.driver.integrationTime;
                        -- Prevents invalid short integrations, by clamping the minimum
                        if integrationCount < MIN_INTEGRATION_TIME then
                            integrationCount := MIN_INTEGRATION_TIME;
                        end if;
                        -- Prevents excessively long integrations, by clamping the maximum
                        if integrationCount > MAX_INTEGRATION_TIME then
                            integrationCount := MAX_INTEGRATION_TIME;
                        end if;
                        -- Calculate Start Pulse Width
                        -- start pulse width is being derived from the requested integration time
                        if integrationCount > 48 then
                            startHighTime := integrationCount - 48;
                        else
                            startHighTime := T_ST_HIGH_MIN;
                        end if;
                        -- Enforce Minimum ST Width
                        -- guarantees the detector timing requirements are met
                        if startHighTime < T_ST_HIGH_MIN then
                            startHighTime := T_ST_HIGH_MIN;
                        end if;

                        -- Initialize Acquisition
                        -- Reset timing counter
                        timingCount := 0;
                        -- Resets internal tracking variables
                        storageBusySeen := false;
                        storageDoneSeen := false;
                        timingFinished := false;
                        -- Acquisition has started
                        done <= '0';
                        -- Move into acquisition mode
                        driverState := DRIVER_TIMING;
                    end if;
                -- Detector timing sequence is currently running
                when DRIVER_TIMING =>
                    -- Driver is busy
                    done <= '0';

                    -- Wait for storage logic to become active
                    if not storageBusySeen then
                        --
                        if dataStorageDoneSync = '0' then
                            storageBusySeen := true;
                        end if;
                    --
                    elsif dataStorageDoneSync = '1' then
                        -- storage completed
                        storageDoneSeen := true;
                    end if;

                    -- Only execute timing actions on half the clock edges
                    if clockPhase = '0' then
                        -- Start Pulse High
                        if timingCount < startHighTime then
                            devStart <= '1';
                        -- Start Pulse Low
                        elsif timingCount < startHighTime + START_LOW_TIME then
                            devStart <= '0';
                        -- End Of Timing
                        else
                            devStart <= '1';
                            timingFinished := true;
                        end if;
                        -- Advance Timing Counter by continuing stepping through the timing sequence
                        if not timingFinished then
                            timingCount := timingCount + 1;
                        end if;
                    end if;
                    
                    -- Detector driving sequence has finished
                    if timingFinished then
                        -- If Data Already Stored
                        if storageDoneSeen then
                            -- Everything is complete
                            done <= '1';
                            driverState := DRIVER_IDLE;
                        else
                            -- Detector timing finished but memory writes are still occurring
                            driverState := DRIVER_WAIT_STORAGE_DONE;
                        end if;
                    end if;

                -- State waits for the final ADC samples to be written
                when DRIVER_WAIT_STORAGE_DONE =>
                    -- Still Busy
                    done <= '0';
                    -- Detector Returned To Idle
                    devStart <= '1';
                    if not storageBusySeen then
                        if dataStorageDoneSync = '0' then
                            storageBusySeen := true;
                        end if;
                    -- 
                    elsif dataStorageDoneSync = '1' then
                        storageDoneSeen := true;
                    end if;
                    -- When Storage Completes
                    if storageDoneSeen then
                        done <= '1';
                        driverState := DRIVER_IDLE;
                    end if;
            end case;
            
            -- Debug Output to map the current state onto LEDs/debug signals
            -- Encodes the current driver state onto the debug bus for diagnostics
            case driverState is
                -- Idle
                when DRIVER_IDLE              => debug(3 downto 0) <= "0000";
                -- Timing Active
                when DRIVER_TIMING            => debug(3 downto 0) <= "0001";
                -- Waiting For Storage
                when DRIVER_WAIT_STORAGE_DONE => debug(3 downto 0) <= "0010";
            end case;
        end if;
    end process;
    
    -- Register the ADC sample on the falling edge of dataClk
    -- 
    DATA_LATCH: process(dataClk)
    begin
        if falling_edge(dataClk) then
            ADC_data_z <= ADC_data;
        end if;
    end process;
    
    -- Receives detector pixel stream and Stores pixels into memory
    STORE_DATA: process(dataClk)
        -- Storage States
        -- STORAGE_IDLE: Waiting for a new acquisition
        -- STORAGE_WAIT_PIXEL_WINDOW: A spectrum has started, but the first valid pixel has not yet arrived
        -- STORAGE_WRITE: Actively writing ADC samples into memory
        -- STORAGE_FINISH: Writing complete, clean up and return to idle
        type storage_state_type is (STORAGE_IDLE, STORAGE_WAIT_PIXEL_WINDOW, STORAGE_WRITE, STORAGE_FINISH);
        variable storageState : storage_state_type := STORAGE_IDLE;
        -- Tracks detector timing after the start pulse
        variable timingIndex  : natural := 0;
        -- Pixel number currently being stored
        variable sampleIndex  : natural range 0 to DATA_LEN - 1 := 0;
    begin
        -- Pixel handling occurs on the detector clock
        if rising_edge(dataClk) then
            -- Default behaviour: Don't write to memory
            writeEnable(0) <= '0';

            case storageState is
                -- No acquisition currently taking place
                when STORAGE_IDLE =>
                    -- Indicate that no spectrum storage operation is currently active
                    dataStorageDone <= '1';
                    -- Reset Counters
                    timingIndex := 0;
                    sampleIndex := 0;
                    -- Reset Address: Next acquisition starts at pixel 0
                    writeAddr <= (others => '0');
                    -- Wait For Start Of Readout: This marks the start of a detector readout sequence
                    if devStartFallingData = '1' then
                        -- Acquisition Starts: Storage now busy
                        dataStorageDone <= '0';
                        -- Synchronization Compensation: Account for synchronizer delays
                        timingIndex := 1 + DEV_START_SYNC_COMPENSATION;
                        -- Wait for a detector acquisition to begin
                        storageState := STORAGE_WAIT_PIXEL_WINDOW;
                    end if;

                -- The detector has started, but valid pixels are not available yet
                when STORAGE_WAIT_PIXEL_WINDOW =>
                    dataStorageDone <= '0';
                    -- Wait For First Valid Pixel: This delay is compensating for detector/ADC pipeline latency
                    if timingIndex >= FIRST_WRITE_SETUP_COUNT then
                        -- Start with pixel 0 once ready
                        sampleIndex := 0;
                        -- Write to address 0.
                        writeAddr <= (others => '0');
                        -- Perform first RAM write
                        writeEnable(0) <= '1';
                        -- Enter write mode
                        storageState := STORAGE_WRITE;
                    else
                        timingIndex := timingIndex + 1;
                    end if;
                -- where the actual spectrum gets stored
                -- Sequentially store ADC samples into spectrum memory
                when STORAGE_WRITE =>
                    dataStorageDone <= '0';
                    -- Check if Last Pixel
                    if sampleIndex = DATA_LEN - 1 then
                        -- Stop writing
                        writeEnable(0) <= '0';
                        storageState := STORAGE_FINISH;
                    else
                        -- Move to next pixel
                        sampleIndex := sampleIndex + 1;
                        -- Update Memory Address
                        writeAddr <= std_logic_vector(to_unsigned(sampleIndex, writeAddr'length));
                        -- Write Current Pixel
                        writeEnable(0) <= '1';
                    end if;

                -- Spectrum completely captured
                -- Signal that all spectrum samples have been written to memory
                when STORAGE_FINISH =>
                    -- Stop writing
                    writeEnable(0) <= '0';
                    -- Spectrum storage complete
                    dataStorageDone <= '1';
                    -- Ready for the next acquisition
                    storageState := STORAGE_IDLE;
            end case;
            
            -- Debug Outputs
            case storageState is
                -- Idle
                when STORAGE_IDLE             => debug(6 downto 4) <= "000";
                -- Waiting For First Pixel
                when STORAGE_WAIT_PIXEL_WINDOW => debug(6 downto 4) <= "001";
                -- Writing Pixels
                when STORAGE_WRITE            => debug(6 downto 4) <= "010";
                -- Finished
                when STORAGE_FINISH           => debug(6 downto 4) <= "011";
            end case;
            -- Write Activity Indicator
            -- Whenever memory is being written then debug(7) = 1
            debug(7) <= writeEnable(0);
        end if;
    end process;
    
    -- Xilinx/Vivado Block RAM IP generated by the Block Memory Generator
    -- Uses Vivado's optimized hardware RAM
    -- Dual port memory: Port A and Port B
    -- Write on Port A (16-bit ADC samples using the detector clock)
    -- Read on Port B (stored pixel values using the high-speed readout clock for transmission to PC)
    -- Without dual-port RAM Writing spectrum and Reading spectrum would interfere
    -- So each side has its own clock, address bus and data bus
    -- Now we can safely cross clock domains without manually synchronizing every pixel value
    MEM_MAP: blk_mem_gen_0
        port map (
            -- Writes occur in the detector clock domain
            clka  => dataClk,
            ena   => '1',
            -- When writeEnable = 1
            -- store a sample
            wea   => writeEnable,
            -- Current pixel location
            addra => writeAddr,
            -- Current pixel intensity value
            dina  => writeData,
            -- Design never reads from the write port
            douta => open,
            -- Reading occurs in the fast clock domain
            clkb  => readoutClk,
            enb   => '1',
            -- Write Enable = 0 always
            -- This side is read-only
            web   => (others => '0'),
            -- Address Input supplied by binaryReadout
            addrb => readoutAddr,
            dinb  => (others => '0'),
            -- Data Output returns Pixel Intensity
            doutb => readoutData
        );
end architecture Behavioral;
