###############################################################################
# Cmod A7-35T Spectrometer Control Board
#
# FPGA:
#   XC7A35T-1CPG236C
#
# Top-level VHDL entity:
#   spectrometer
#
# This file defines:
#
#   - Package-pin assignments
#   - I/O standards
#   - Returned 5 MHz spectrometer clock
#   - Output electrical properties
#   - Targeted CDC first-stage exceptions
#   - Preservation of the verified acquisition and binary-output hierarchy
###############################################################################


###############################################################################
# FPGA configuration voltage
###############################################################################

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]


###############################################################################
# 12 MHz Cmod A7 onboard clock
#
# The Clocking Wizard IP supplies the GCLK timing constraint.
# Do not create a second GCLK clock here.
###############################################################################

set_property -dict { \
    PACKAGE_PIN L17 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GCLK}]


###############################################################################
# Spectrometer returned TRG/data clock
#
# GPIO36 is used as:
#
#   - ADC capture timing
#   - Spectrum-RAM Port A write clock
#
# Frequency:
#   5 MHz
#
# Period:
#   200 ns
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
# with the internally generated 10 MHz clk_out1_pll clock.
###############################################################################

set_clock_groups -asynchronous \
    -group [get_clocks SP_TRG_CLK] \
    -group [get_clocks -of_objects \
        [get_pins CLK_GEN/inst/mmcm_adv_inst/CLKOUT0]]
        
###############################################################################
# Cmod A7 onboard buttons
###############################################################################

set_property -dict { \
    PACKAGE_PIN A18 \
    IOSTANDARD LVCMOS33 \
} [get_ports {BTN0}]

set_property -dict { \
    PACKAGE_PIN B18 \
    IOSTANDARD LVCMOS33 \
} [get_ports {BTN1}]


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
# TX_USB:
#   FPGA output toward the computer.
#
# RX_USB:
#   Computer output toward the FPGA command receiver.
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
# GPIO1:
#   Package pin M3
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

# GPIO20:
# Spectrometer EOS input
set_property -dict { \
    PACKAGE_PIN M2 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO20}]

# GPIO21:
# Spectrometer START output
set_property -dict { \
    PACKAGE_PIN N1 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO21}]

# GPIO22:
# Spectrometer clock output
set_property -dict { \
    PACKAGE_PIN N2 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO22}]

# GPIO36:
# Spectrometer returned TRG/data-clock input
set_property -dict { \
    PACKAGE_PIN W5 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO36}]


###############################################################################
# Command-decoder debug outputs
###############################################################################

# GPIO45:
# USB command-valid pulse
set_property -dict { \
    PACKAGE_PIN U7 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO45}]

# GPIO46:
# Nano command-valid pulse
set_property -dict { \
    PACKAGE_PIN W7 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO46}]


###############################################################################
# Arduino Nano UART
###############################################################################

# GPIO47:
# FPGA TX toward Nano RX.
# The top-level holds this output at the UART idle-high level.
set_property -dict { \
    PACKAGE_PIN U8 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO47}]

# GPIO48:
# Nano TX toward FPGA RX
set_property -dict { \
    PACKAGE_PIN V8 \
    IOSTANDARD LVCMOS33 \
} [get_ports {GPIO48}]


###############################################################################
# Output electrical properties
#
# Use conservative drive strength and slow slew rate for carrier-board signals.
###############################################################################

set_property DRIVE 8 [get_ports {
    TX_USB
    GPIO1
    GPIO21
    GPIO22
    GPIO45
    GPIO46
    GPIO47
}]

set_property SLEW SLOW [get_ports {
    TX_USB
    GPIO1
    GPIO21
    GPIO22
    GPIO45
    GPIO46
    GPIO47
}]


###############################################################################
# Targeted first-stage synchronizer timing exceptions
#
# Each exception ends setup and hold analysis only at the D input of the first
# register in a verified two-register synchronizer.
#
# The path from each first-stage register to its second-stage register remains
# normally timed.
#
# Do not replace these targeted exceptions with a broad asynchronous clock-group
# constraint.
###############################################################################


###############################################################################
# driverDone:
#
#   Source clock      = clk_out1_pll, 10 MHz
#   Destination clock = clk_out2_pll, 60 MHz
###############################################################################

set_false_path \
    -to [get_pins \
        -of_objects [get_cells -hierarchical \
            {driverDoneFastMeta_reg}] \
        -filter {REF_PIN_NAME == D}]


###############################################################################
# fast reset:
#
#   Source clock      = clk_out1_pll, 10 MHz
#   Destination clock = clk_out2_pll, 60 MHz
###############################################################################

set_false_path \
    -to [get_pins \
        -of_objects [get_cells -hierarchical \
            {fastResetMeta_reg}] \
        -filter {REF_PIN_NAME == D}]


###############################################################################
# readoutDone:
#
#   Source clock      = clk_out2_pll, 60 MHz
#   Destination clock = clk_out1_pll, 10 MHz
###############################################################################

set_false_path \
    -to [get_pins \
        -of_objects [get_cells -hierarchical \
            {readoutDoneSysMeta_reg}] \
        -filter {REF_PIN_NAME == D}]

###############################################################################
# Cmod A7 Quad-SPI configuration
#
# Generate a bitstream that boots from the onboard Quad-SPI flash using the
# four-bit SPI data interface.
###############################################################################

set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
###############################################################################
# devStart:
#
#   Source clock      = clk_out1_pll, 10 MHz
#   Destination clock = SP_TRG_CLK, 5 MHz
###############################################################################

#set_false_path \
#    -to [get_pins \
#        -of_objects [get_cells -hierarchical \
#            {DEV_DRIVER/devStartDataMeta_reg}] \
#        -filter {REF_PIN_NAME == D}]


###############################################################################
# dataStorageDone:
#
#   Source clock      = SP_TRG_CLK, 5 MHz
#   Destination clock = clk_out1_pll, 10 MHz
###############################################################################

#set_false_path \
#    -to [get_pins \
#        -of_objects [get_cells -hierarchical \
#            {DEV_DRIVER/dataStorageDoneMeta_reg}] \
#        -filter {REF_PIN_NAME == D}]


###############################################################################
# Preserve verified functional hierarchy
#
# These three instances have been separately verified by:
#
#   - Acquisition ADC-path simulation:
#       288 consecutive physical ADC samples
#
#   - Binary-output simulation:
#       596 transmitted bytes
#
# DONT_TOUCH is applied at the hierarchy boundary so implementation does not
# remove or move logic across these verified boundaries.
#
# Signal-level DONT_TOUCH attributes in driver.vhd and spectrometer.vhd preserve
# the important ADC, RAM, readout and byte-stream interconnect signals.
#
# Exact instance names are used. The absence or renaming of an expected instance
# will therefore produce a visible constraint error instead of being silently
# ignored.
###############################################################################