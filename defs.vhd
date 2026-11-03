library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


package defs is

    ---------------------------------------------------------------------------
    -- Spectrometer constants
    ---------------------------------------------------------------------------

    constant DATA_LEN : natural := 288;

    -- Integration time is expressed in 5 MHz spectrometer-clock counts.
    constant MIN_INTEGRATION_TIME : natural := 100;
    constant MAX_INTEGRATION_TIME : natural := 100000000;

    constant DEVICE_CLOCK_HZ : natural := 5000000;


    ---------------------------------------------------------------------------
    -- FPGA clock frequencies
    ---------------------------------------------------------------------------

    -- Compatibility and acquisition-control clock.
    constant SYSTEM_CLOCK_HZ : natural := 10000000;

    -- Binary-readout and high-speed-transmission clock.
    constant FAST_CLOCK_HZ : natural := 60000000;


    ---------------------------------------------------------------------------
    -- Existing command UART configuration
    ---------------------------------------------------------------------------

    -- 10 MHz / 43 = approximately 232558 baud.
    -- Configure the corresponding serial connection for 230400 baud.
    constant SERIAL_CLK_DIV : natural := 43;


    ---------------------------------------------------------------------------
    -- High-speed USB UART configuration
    ---------------------------------------------------------------------------

    -- Initial rate:
    --
    -- 60 MHz / 60 = 1 Mbaud.
    --
    -- Possible later settings:
    --
    -- 60 = 1 Mbaud
    -- 30 = 2 Mbaud
    -- 20 = 3 Mbaud
    -- 12 = 5 Mbaud
    --  6 = 10 Mbaud
    constant FAST_UART_CLK_DIV : positive := 60;

    constant FAST_UART_STOP_BITS : positive := 1;


    ---------------------------------------------------------------------------
    -- Binary frame constants
    ---------------------------------------------------------------------------

    constant BINARY_SYNC_0 :
        std_logic_vector(7 downto 0) := x"A5";

    constant BINARY_SYNC_1 :
        std_logic_vector(7 downto 0) := x"5A";

    constant BINARY_SYNC_2 :
        std_logic_vector(7 downto 0) := x"C3";

    constant BINARY_SYNC_3 :
        std_logic_vector(7 downto 0) := x"3C";

    constant BINARY_PROTOCOL_VERSION :
        std_logic_vector(7 downto 0) := x"01";

    constant BINARY_STATUS_OK :
        std_logic_vector(7 downto 0) := x"00";


    ---------------------------------------------------------------------------
    -- Binary frame sizes
    ---------------------------------------------------------------------------

    constant BINARY_SYNC_BYTES : natural := 4;

    -- Metadata following the synchronization marker:
    --
    -- Protocol version       1 byte
    -- Status                 1 byte
    -- Remaining length       2 bytes
    -- Frame sequence         4 bytes
    -- Integration count      4 bytes
    -- Pixel count            2 bytes
    --
    -- Total                 14 bytes
    constant BINARY_METADATA_BYTES : natural := 14;

    -- 288 pixels, with two bytes for each pixel.
    constant BINARY_PIXEL_BYTES : natural := DATA_LEN * 2;

    constant BINARY_CRC_BYTES : natural := 2;

    -- Total:
    --
    -- Sync       4
    -- Metadata  14
    -- Pixels   576
    -- CRC        2
    -- ------------
    -- Total    596 bytes
    constant BINARY_FRAME_BYTES : natural :=
        BINARY_SYNC_BYTES +
        BINARY_METADATA_BYTES +
        BINARY_PIXEL_BYTES +
        BINARY_CRC_BYTES;

    -- Number of bytes after the synchronization marker:
    --
    -- 596 - 4 = 592 = 0x0250
    constant BINARY_REMAINING_BYTES : natural :=
        BINARY_FRAME_BYTES - BINARY_SYNC_BYTES;


    ---------------------------------------------------------------------------
    -- CRC-16/CCITT-FALSE constants
    ---------------------------------------------------------------------------

    constant CRC16_INITIAL :
        unsigned(15 downto 0) := x"FFFF";

    constant CRC16_POLYNOMIAL :
        unsigned(15 downto 0) := x"1021";


    ---------------------------------------------------------------------------
    -- ASCII conversion functions
    ---------------------------------------------------------------------------

    function toAsciiHex (
        nibble : std_logic_vector(3 downto 0)
    ) return std_logic_vector;

    function asciiHexValue (
        x : std_logic_vector(7 downto 0)
    ) return std_logic_vector;


    ---------------------------------------------------------------------------
    -- Command type
    ---------------------------------------------------------------------------

    type cmd_type is record
        cmdType : std_logic_vector(15 downto 0);
        data    : std_logic_vector(31 downto 0);
        valid   : std_logic;
    end record;

    constant CMD_RESET : cmd_type := (
        cmdType => (others => '0'),
        data    => (others => '0'),
        valid   => '0'
    );


    ---------------------------------------------------------------------------
    -- Configuration parameter types
    ---------------------------------------------------------------------------

    type readoutParameter_type is record
        useTestData : std_logic;
    end record;

    type driverParameter_type is record
        integrationTime : natural;
        useTestData     : std_logic;
    end record;

    type parameterList_type is record
        driver    : driverParameter_type;
        readout   : readoutParameter_type;
        repPeriod : natural;
    end record;


    ---------------------------------------------------------------------------
    -- Default configuration
    ---------------------------------------------------------------------------

    constant defaultParameter : parameterList_type := (
        driver => (
            integrationTime => 100000,
            useTestData     => '0'
        ),

        readout => (
            useTestData => '0'
        ),

        -- The original value was 20,000,000, which produced a two-second
        -- repetition delay at 10 MHz.
        --
        -- The new scheduler uses explicit driver/readout completion handshakes,
        -- so no additional repetition delay is required.
        repPeriod => 0
    );


    ---------------------------------------------------------------------------
    -- Existing serial communication record
    ---------------------------------------------------------------------------

    type serialComms_type is record
        txValid : std_logic;
        txData  : std_logic_vector(7 downto 0);
        txWait  : std_logic;
        rxCmd   : cmd_type;
    end record;


    ---------------------------------------------------------------------------
    -- Legacy readout record
    ---------------------------------------------------------------------------

    type readout_type is record
        txValid : std_logic;
        txByte  : std_logic_vector(7 downto 0);
        txWait  : std_logic;

        addr : std_logic_vector(8 downto 0);
        data : std_logic_vector(15 downto 0);

        reset : std_logic;
        clock : std_logic;
        done  : std_logic;
    end record;


    ---------------------------------------------------------------------------
    -- Command handler
    ---------------------------------------------------------------------------

    component commandHandler is
        port (
            clock     : in  std_logic;
            reset     : in  std_logic;
            nanoCmd   : in  cmd_type;
            usbCmd    : in  cmd_type;
            parameter : out parameterList_type
        );
    end component;


    ---------------------------------------------------------------------------
    -- Command receiver
    ---------------------------------------------------------------------------

    component rxCommand is
        port (
            clock     : in  std_logic;
            din       : in  std_logic_vector(7 downto 0);
            din_valid : in  std_logic;
            cmd       : out cmd_type
        );
    end component;


    ---------------------------------------------------------------------------
    -- Spectrometer and ADC driver
    ---------------------------------------------------------------------------

    component driver is
        port (
            -- Control signals
            sysClk    : in  std_logic;
            trig      : in  std_logic;
            parameter : in  parameterList_type;
            done      : out std_logic;

            -- Spectrum RAM read interface
            readoutClk  : in  std_logic;
            readoutAddr : in  std_logic_vector(8 downto 0);
            readoutData : out std_logic_vector(15 downto 0);

            -- Spectrometer signals
            devClk   : out    std_logic;
            devStart : buffer std_logic;
            dataClk  : in     std_logic;
            EOS      : in     std_logic;

            -- ADC signals
            ADC_clock : out std_logic;
            ADC_data  : in  std_logic_vector(11 downto 0);

            -- Debug
            debug : out std_logic_vector(7 downto 0)
        );
    end component;


    ---------------------------------------------------------------------------
    -- Original ASCII readout
    ---------------------------------------------------------------------------

    component dataReadout is
        port (
            sysClk    : in std_logic;
            trig      : in std_logic;
            parameter : in parameterList_type;

            txByte  : out std_logic_vector(7 downto 0);
            txValid : out std_logic;
            txWait  : in  std_logic;

            done : out std_logic;
            addr : out std_logic_vector(8 downto 0);
            data : in  std_logic_vector(15 downto 0)
        );
    end component;


    ---------------------------------------------------------------------------
    -- Compact binary readout
    ---------------------------------------------------------------------------

    component binaryReadout is
        port (
            clock           : in std_logic;
            reset           : in std_logic;
            trig            : in std_logic;
            integrationTime : in natural;

            txByte  : out std_logic_vector(7 downto 0);
            txValid : out std_logic;
            txWait  : in  std_logic;

            done : out std_logic;
            addr : out std_logic_vector(8 downto 0);
            data : in  std_logic_vector(15 downto 0)
        );
    end component;


    ---------------------------------------------------------------------------
    -- Dual-port spectrum RAM
    ---------------------------------------------------------------------------

    component blk_mem_gen_0 is
        port (
            -- Port A
            clka  : in  std_logic;
            ena   : in  std_logic;
            wea   : in  std_logic_vector(0 downto 0);
            addra : in  std_logic_vector(8 downto 0);
            dina  : in  std_logic_vector(15 downto 0);
            douta : out std_logic_vector(15 downto 0);

            -- Port B
            clkb  : in  std_logic;
            enb   : in  std_logic;
            web   : in  std_logic_vector(0 downto 0);
            addrb : in  std_logic_vector(8 downto 0);
            dinb  : in  std_logic_vector(15 downto 0);
            doutb : out std_logic_vector(15 downto 0)
        );
    end component;


    ---------------------------------------------------------------------------
    -- Clocking Wizard
    --
    -- clk_out1 = 10 MHz
    -- clk_out2 = 60 MHz
    -- clk_in1  = 12 MHz
    ---------------------------------------------------------------------------

    component pll is
        port (
            clk_out1 : out std_logic;
            clk_out2 : out std_logic;
            reset    : in  std_logic;
            clk_in1  : in  std_logic
        );
    end component;


    ---------------------------------------------------------------------------
    -- Existing bidirectional UART
    ---------------------------------------------------------------------------

    component uart is
        generic (
            data_len  : integer := 8;
            stop_bits : integer := 1;
            clk_div   : integer := 520
        );

        port (
            clock : in std_logic;
            reset : in std_logic;

            txData  : in  std_logic_vector(data_len - 1 downto 0);
            txValid : in  std_logic;
            txReady : out std_logic;
            txOut   : out std_logic;

            rxData  : out std_logic_vector(data_len - 1 downto 0);
            rxValid : out std_logic;
            rxError : out std_logic;
            rxIn    : in  std_logic
        );
    end component;


    ---------------------------------------------------------------------------
    -- High-speed transmit-only UART
    ---------------------------------------------------------------------------

    component fastSerialTx is
        generic (
            CLOCKS_PER_BIT : positive := FAST_UART_CLK_DIV;
            STOP_BITS      : positive := FAST_UART_STOP_BITS
        );

        port (
            clock : in std_logic;
            reset : in std_logic;

            data  : in std_logic_vector(7 downto 0);
            valid : in std_logic;

            ready : out std_logic;
            tx    : out std_logic
        );
    end component;


    ---------------------------------------------------------------------------
    -- Existing pulse synchronization component
    ---------------------------------------------------------------------------

    component pulseSync is
        port (
            inClock    : in  std_logic;
            outClock   : in  std_logic;
            din_valid  : in  std_logic;
            dout_valid : out std_logic
        );
    end component;


    ---------------------------------------------------------------------------
    -- Generated serial transmit FIFO
    ---------------------------------------------------------------------------

    component serialTxFifo is
        port (
            clk       : in  std_logic;
            srst      : in  std_logic;
            din       : in  std_logic_vector(7 downto 0);
            wr_en     : in  std_logic;
            rd_en     : in  std_logic;
            dout      : out std_logic_vector(7 downto 0);
            full      : out std_logic;
            empty     : out std_logic;
            prog_full : out std_logic
        );
    end component;


    ---------------------------------------------------------------------------
    -- Existing serial command interface
    ---------------------------------------------------------------------------

    component serialComms is
        port (
            clock    : in  std_logic;
            reset    : in  std_logic;
            txSerial : out std_logic;
            rxSerial : in  std_logic;

            txData  : in  std_logic_vector(7 downto 0);
            txValid : in  std_logic;
            txWait  : out std_logic;

            rxCmd : out cmd_type
        );
    end component;

end defs;


package body defs is

    ---------------------------------------------------------------------------
    -- Convert one four-bit value to an uppercase hexadecimal ASCII character.
    ---------------------------------------------------------------------------

    function toAsciiHex (
        nibble : std_logic_vector(3 downto 0)
    ) return std_logic_vector is

        variable i : integer;

    begin
        i := to_integer(unsigned(nibble));

        if i >= 10 then
            i := i + 55;
        else
            i := i + 48;
        end if;

        return std_logic_vector(to_unsigned(i, 8));
    end function toAsciiHex;


    ---------------------------------------------------------------------------
    -- Convert an ASCII hexadecimal character to a four-bit value.
    ---------------------------------------------------------------------------

    function asciiHexValue (
        x : std_logic_vector(7 downto 0)
    ) return std_logic_vector is

        variable i : integer;

    begin
        i := to_integer(unsigned(x));

        if i >= 48 and i <= 57 then
            i := i - 48;

        elsif i >= 65 and i <= 70 then
            i := i - 55;

        elsif i >= 97 and i <= 102 then
            i := i - 87;

        else
            i := 0;
        end if;

        return std_logic_vector(to_unsigned(i, 4));
    end function asciiHexValue;

end defs;