library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_python_cosim is
end entity tb_python_cosim;

architecture sim of tb_python_cosim is

    ---------------------------------------------------------------------------
    -- Binary file type
    --
    -- A named file type is required by VHDL-93/2002.
    ---------------------------------------------------------------------------

    type character_file_type is file of character;

    ---------------------------------------------------------------------------
    -- Clock and UART timing
    ---------------------------------------------------------------------------

    constant GCLK_PERIOD : time := 83.333 ns;

    constant BAUD_RATE : positive := 1000000;

    constant UART_BIT_PERIOD : time :=
        (1000000000 / BAUD_RATE) * 1 ns;

    constant EXPECTED_FRAME_BYTES : positive := 600;

    ---------------------------------------------------------------------------
    -- Top-level DUT signals
    ---------------------------------------------------------------------------

    signal GCLK : std_logic := '0';

    signal RX_USB : std_logic := '1';
    signal TX_USB : std_logic;

    signal GPIO1 : std_logic;

    signal GPIO3  : std_logic := '0';
    signal GPIO4  : std_logic := '0';
    signal GPIO5  : std_logic := '0';
    signal GPIO6  : std_logic := '0';
    signal GPIO7  : std_logic := '0';
    signal GPIO8  : std_logic := '0';
    signal GPIO9  : std_logic := '0';
    signal GPIO10 : std_logic := '0';
    signal GPIO11 : std_logic := '0';
    signal GPIO12 : std_logic := '0';
    signal GPIO13 : std_logic := '0';
    signal GPIO14 : std_logic := '0';

    signal GPIO21 : std_logic;
    signal GPIO22 : std_logic;

    signal GPIO36 : std_logic := '0';

    signal LD0_R : std_logic;
    signal LD0_G : std_logic;
    signal LD0_B : std_logic;

    signal LD1 : std_logic;
    signal LD2 : std_logic;

    ---------------------------------------------------------------------------
    -- Mock ADC
    ---------------------------------------------------------------------------

    signal mock_adc_data :
        unsigned(11 downto 0) := to_unsigned(512, 12);

    ---------------------------------------------------------------------------
    -- Simulation status
    ---------------------------------------------------------------------------

    signal captured_byte_count :
        natural range 0 to EXPECTED_FRAME_BYTES := 0;

    signal frame_capture_complete :
        std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- Device under test
    ---------------------------------------------------------------------------

    UUT : entity work.spectrometer_top
        port map (
            GCLK   => GCLK,

            RX_USB => RX_USB,
            TX_USB => TX_USB,

            GPIO1  => GPIO1,

            GPIO3  => GPIO3,
            GPIO4  => GPIO4,
            GPIO5  => GPIO5,
            GPIO6  => GPIO6,
            GPIO7  => GPIO7,
            GPIO8  => GPIO8,
            GPIO9  => GPIO9,
            GPIO10 => GPIO10,
            GPIO11 => GPIO11,
            GPIO12 => GPIO12,
            GPIO13 => GPIO13,
            GPIO14 => GPIO14,

            GPIO21 => GPIO21,
            GPIO22 => GPIO22,

            GPIO36 => GPIO36,

            LD0_R  => LD0_R,
            LD0_G  => LD0_G,
            LD0_B  => LD0_B,

            LD1    => LD1,
            LD2    => LD2
        );

    ---------------------------------------------------------------------------
    -- 12 MHz Cmod A7 input clock
    ---------------------------------------------------------------------------

    GCLK_PROCESS : process
    begin
        GCLK <= '0';
        wait for GCLK_PERIOD / 2;

        GCLK <= '1';
        wait for GCLK_PERIOD / 2;
    end process GCLK_PROCESS;

    ---------------------------------------------------------------------------
    -- 5 MHz detector return/data clock
    ---------------------------------------------------------------------------

    DETECTOR_CLOCK_PROCESS : process
    begin
        GPIO36 <= '0';
        wait for 100 ns;

        GPIO36 <= '1';
        wait for 100 ns;
    end process DETECTOR_CLOCK_PROCESS;

    ---------------------------------------------------------------------------
    -- Mock ADC model
    --
    -- Generates changing 12-bit data. Test-pattern mode 1 in the FPGA does
    -- not use these values, but the model is available for real-data mode.
    ---------------------------------------------------------------------------

    ADC_MODEL_PROCESS : process(GPIO36)
    begin
        if rising_edge(GPIO36) then

            if mock_adc_data <= to_unsigned(3987, 12) then
                mock_adc_data <= mock_adc_data + 12;
            else
                mock_adc_data <= to_unsigned(200, 12);
            end if;

        end if;
    end process ADC_MODEL_PROCESS;

    ---------------------------------------------------------------------------
    -- Map the mock ADC bus onto GPIO3 through GPIO14
    ---------------------------------------------------------------------------

    GPIO3  <= mock_adc_data(0);
    GPIO4  <= mock_adc_data(1);
    GPIO5  <= mock_adc_data(2);
    GPIO6  <= mock_adc_data(3);
    GPIO7  <= mock_adc_data(4);
    GPIO8  <= mock_adc_data(5);
    GPIO9  <= mock_adc_data(6);
    GPIO10 <= mock_adc_data(7);
    GPIO11 <= mock_adc_data(8);
    GPIO12 <= mock_adc_data(9);
    GPIO13 <= mock_adc_data(10);
    GPIO14 <= mock_adc_data(11);

    ---------------------------------------------------------------------------
    -- UART command-file injector
    --
    -- Reads raw bytes from commands.bin and transmits them onto RX_USB using
    -- 1 Mbaud, 8 data bits, no parity, and one stop bit.
    ---------------------------------------------------------------------------

    UART_COMMAND_INJECTOR : process

        file command_file :
            character_file_type;

        variable open_status :
            file_open_status;

        variable command_character :
            character;

        variable command_byte :
            std_logic_vector(7 downto 0);

    begin

        file_open(
            open_status,
            command_file,
            "commands.bin",
            read_mode
        );

        assert open_status = open_ok
            report "Could not open commands.bin"
            severity failure;

        RX_USB <= '1';

        -----------------------------------------------------------------------
        -- Allow the simulated MMCM to lock and reset synchronizers to release.
        -----------------------------------------------------------------------

        wait for 100 us;

        while not endfile(command_file) loop

            read(
                command_file,
                command_character
            );

            command_byte :=
                std_logic_vector(
                    to_unsigned(
                        character'pos(command_character),
                        8
                    )
                );

            -------------------------------------------------------------------
            -- Start bit
            -------------------------------------------------------------------

            RX_USB <= '0';
            wait for UART_BIT_PERIOD;

            -------------------------------------------------------------------
            -- Eight data bits, least-significant bit first
            -------------------------------------------------------------------

            for bit_index in 0 to 7 loop

                RX_USB <= command_byte(bit_index);

                wait for UART_BIT_PERIOD;

            end loop;

            -------------------------------------------------------------------
            -- Stop bit
            -------------------------------------------------------------------

            RX_USB <= '1';
            wait for UART_BIT_PERIOD;

        end loop;

        file_close(command_file);

        RX_USB <= '1';

        report "All bytes from commands.bin were transmitted"
            severity note;

        wait;

    end process UART_COMMAND_INJECTOR;

    ---------------------------------------------------------------------------
    -- FPGA UART output monitor
    --
    -- Captures 1 Mbaud, 8-N-1 bytes from TX_USB and writes them directly to
    -- spectra.bin. The file is closed after one complete 600-byte frame.
    ---------------------------------------------------------------------------

    UART_OUTPUT_MONITOR : process

        file spectrum_file :
            character_file_type;

        variable open_status :
            file_open_status;

        variable received_byte :
            std_logic_vector(7 downto 0);

        variable output_character :
            character;

        variable local_byte_count :
            natural range 0 to EXPECTED_FRAME_BYTES := 0;

    begin

        file_open(
            open_status,
            spectrum_file,
            "spectra.bin",
            write_mode
        );

        assert open_status = open_ok
            report "Could not open spectra.bin for writing"
            severity failure;

        while local_byte_count < EXPECTED_FRAME_BYTES loop

            -------------------------------------------------------------------
            -- Detect the falling edge of the UART start bit.
            -------------------------------------------------------------------

            wait until falling_edge(TX_USB);

            -------------------------------------------------------------------
            -- Move to the centre of the start bit.
            -------------------------------------------------------------------

            wait for UART_BIT_PERIOD / 2;

            if TX_USB = '0' then

                ----------------------------------------------------------------
                -- Move from the centre of the start bit to the centre of each
                -- data bit. UART data is least-significant bit first.
                ----------------------------------------------------------------

                for bit_index in 0 to 7 loop

                    wait for UART_BIT_PERIOD;

                    received_byte(bit_index) := TX_USB;

                end loop;

                ----------------------------------------------------------------
                -- Move to the centre of the stop bit and verify that it is high.
                ----------------------------------------------------------------

                wait for UART_BIT_PERIOD;

                assert TX_USB = '1'
                    report "UART framing error: stop bit was not high"
                    severity failure;

                output_character :=
                    character'val(
                        to_integer(
                            unsigned(received_byte)
                        )
                    );

                write(
                    spectrum_file,
                    output_character
                );

                local_byte_count :=
                    local_byte_count + 1;

                captured_byte_count <=
                    local_byte_count;

            end if;

        end loop;

        file_close(spectrum_file);

        frame_capture_complete <= '1';

        report "Captured 600 UART bytes into spectra.bin"
            severity note;

        wait;

    end process UART_OUTPUT_MONITOR;

    ---------------------------------------------------------------------------
    -- Simulation completion and timeout
    ---------------------------------------------------------------------------

    END_SIMULATION : process
    begin

        wait until frame_capture_complete = '1';

        wait for 1 us;

        report "tb_python_cosim PASSED"
            severity note;

        assert false
            report "Simulation finished successfully"
            severity failure;

        wait;

    end process END_SIMULATION;

    ---------------------------------------------------------------------------
    -- Safety timeout
    --
    -- If no complete frame is received, stop after 25 ms rather than allowing
    -- the simulation to run indefinitely.
    ---------------------------------------------------------------------------

    SIMULATION_TIMEOUT : process
    begin

        wait for 25 ms;

        assert frame_capture_complete = '1'
            report "Simulation timed out before receiving 600 UART bytes"
            severity failure;

        wait;

    end process SIMULATION_TIMEOUT;

end architecture sim;
