library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_python_cosim is
end entity;

architecture sim of tb_python_cosim is

    ---------------------------------------------------------------------------
    -- Timing
    ---------------------------------------------------------------------------

    constant CLK_PERIOD : time := 83.333 ns;

    constant BAUD_RATE : integer := 1000000;

    constant BIT_PERIOD : time :=
        (1000000000 / BAUD_RATE) * 1 ns;

    ---------------------------------------------------------------------------
    -- DUT Signals
    ---------------------------------------------------------------------------

    signal GCLK : std_logic := '0';

    signal RX_USB : std_logic := '1';
    signal TX_USB : std_logic;

    signal GPIO1  : std_logic;

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
    -- ADC model
    ---------------------------------------------------------------------------

    signal mock_adc_data :
        unsigned(11 downto 0)
            := to_unsigned(512, 12);

begin

    ---------------------------------------------------------------------------
    -- DUT
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
    -- 12 MHz board clock
    ---------------------------------------------------------------------------

    CLOCK_GEN : process
    begin
        GCLK <= '0';
        wait for CLK_PERIOD / 2;

        GCLK <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    ---------------------------------------------------------------------------
    -- Mock detector return clock
    --
    -- 5 MHz on GPIO36
    ---------------------------------------------------------------------------

    DETECTOR_CLOCK : process
    begin
        GPIO36 <= '0';
        wait for 100 ns;

        GPIO36 <= '1';
        wait for 100 ns;
    end process;

    ---------------------------------------------------------------------------
    -- Mock ADC ramp
    ---------------------------------------------------------------------------

    ADC_MODEL : process(GPIO36)
    begin
        if rising_edge(GPIO36) then

            if mock_adc_data < 4000 then
                mock_adc_data <= mock_adc_data + 12;
            else
                mock_adc_data <= to_unsigned(200, 12);
            end if;

        end if;
    end process;

    ---------------------------------------------------------------------------
    -- ADC bus mapping
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

end architecture;


