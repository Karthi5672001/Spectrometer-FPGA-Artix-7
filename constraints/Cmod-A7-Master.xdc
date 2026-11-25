###############################################################################
# Cmod A7-35T Spectrometer Control Board
#
# FPGA:
#   XC7A35T-1CPG236C
#
# Top-level VHDL entity:
#   spectrometer_top
#
# This file defines:
#   - Package-pin assignments
#   - I/O standards
#   - 12 MHz onboard input-clock constraint
#   - External 5 MHz spectrometer data clock
#   - Output electrical properties
#   - Quad-SPI configuration properties
###############################################################################

###############################################################################
# FPGA configuration voltage
###############################################################################

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

###############################################################################
# 12 MHz Cmod A7 onboard clock
#
# GCLK is the board-level primary clock input. The Clocking Wizard derives its
# generated output clocks from this primary clock.
# Frequency: 12 MHz
# Period:    83.333 ns
###############################################################################

set_property -dict { \
    PACKAGE_PIN L17 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GCLK}]

create_clock \
    -name GCLK \
    -period 83.333 \
    -waveform {0.000 41.667} \
    [get_ports {GCLK}]

###############################################################################
# Spectrometer returned TRG/data clock
#
# GPIO36 is used as:
#   - ADC capture timing
#   - Spectrum-RAM Port A write clock
#
# Frequency: 5 MHz
# Period:    200 ns
###############################################################################

create_clock \
    -name SP_TRG_CLK \
    -period 200.000 \
    -waveform {0.000 100.000} \
    [get_ports {GPIO36}]

###############################################################################
# Asynchronous clock relationship
#
# SP_TRG_CLK enters through GPIO36 and has no guaranteed phase relationship
# with GCLK or clocks generated from GCLK by the PLL. Both clock groups are now
# explicitly defined, so the exception does not contain an empty group.
###############################################################################

set_clock_groups -asynchronous \
    -group [get_clocks SP_TRG_CLK] \
    -group [get_clocks -include_generated_clocks GCLK]

###############################################################################
# Cmod A7 RGB LED
###############################################################################

set_property -dict { \
    PACKAGE_PIN C17 \
    IOSTANDARD LVCMOS33 \
} [get_ports {LD0_R}]

set_property -dict { \
    PACKAGE_PIN B16 \
    IOSTANDARD LVCMOS33 \
} [get_ports {LD0_G}]

set_property -dict { \
    PACKAGE_PIN B17 \
    IOSTANDARD LVCMOS33 \
} [get_ports {LD0_B}]

###############################################################################
# Cmod A7 green LEDs
###############################################################################

set_property -dict { \
    PACKAGE_PIN A17 \
    IOSTANDARD LVCMOS33 \
} [get_ports {LD1}]

set_property -dict { \
    PACKAGE_PIN C16 \
    IOSTANDARD LVCMOS33 \
} [get_ports {LD2}]

###############################################################################
# Cmod A7 USB-UART bridge
#
# TX_USB: FPGA output toward the computer.
# RX_USB: Computer output toward the FPGA command receiver.
###############################################################################

set_property -dict { \
    PACKAGE_PIN J18 \
    IOSTANDARD LVCMOS33 \
} [get_ports {TX_USB}]

set_property -dict { \
    PACKAGE_PIN J17 \
    IOSTANDARD LVCMOS33 \
} [get_ports {RX_USB}]

###############################################################################
# AD9220 ADC clock output
#
# GPIO1: Package pin M3
###############################################################################

set_property -dict { \
    PACKAGE_PIN M3 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO1}]

###############################################################################
# AD9220 12-bit parallel data bus
#
# GPIO3 through GPIO14 correspond to ADC D0 through ADC D11.
###############################################################################

# ADC D0
set_property -dict { \
    PACKAGE_PIN A16 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO3}]

# ADC D1
set_property -dict { \
    PACKAGE_PIN K3 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO4}]

# ADC D2
set_property -dict { \
    PACKAGE_PIN C15 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO5}]

# ADC D3
set_property -dict { \
    PACKAGE_PIN H1 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO6}]

# ADC D4
set_property -dict { \
    PACKAGE_PIN A15 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO7}]

# ADC D5
set_property -dict { \
    PACKAGE_PIN B15 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO8}]

# ADC D6
set_property -dict { \
    PACKAGE_PIN A14 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO9}]

# ADC D7
set_property -dict { \
    PACKAGE_PIN J3 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO10}]

# ADC D8
set_property -dict { \
    PACKAGE_PIN J1 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO11}]

# ADC D9
set_property -dict { \
    PACKAGE_PIN K2 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO12}]

# ADC D10
set_property -dict { \
    PACKAGE_PIN L1 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO13}]

# ADC D11
set_property -dict { \
    PACKAGE_PIN L2 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO14}]

###############################################################################
# Spectrometer digital interface
###############################################################################

# GPIO21: Spectrometer START output
set_property -dict { \
    PACKAGE_PIN N1 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO21}]

# GPIO22: Spectrometer clock output
set_property -dict { \
    PACKAGE_PIN N2 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO22}]

# GPIO36: Spectrometer returned TRG/data-clock input
set_property -dict { \
    PACKAGE_PIN W5 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO36}]

###############################################################################
# Output electrical properties
#
# Conservative drive strength and slow slew rate are used for carrier-board
# outputs. Only ports present in spectrometer_top are included.
###############################################################################

set_property DRIVE 8 [get_ports {
    TX_USB
    GPIO1
    GPIO21
    GPIO22
}]

set_property SLEW SLOW [get_ports {
    TX_USB
    GPIO1
    GPIO21
    GPIO22
}]

###############################################################################
# Cmod A7 Quad-SPI configuration
###############################################################################

set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]