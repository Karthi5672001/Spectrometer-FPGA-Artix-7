# Artix-7 UV Spectrometer FPGA Firmware

VHDL code for a Hamamatsu UV spectrometer (polychromator) C16767MA, which is used by the FPGA to take the spectrometer readings and transfer to the Host PC to ensure minimal latency and maximum data throughput. 
FPGA communicate to PC via serial connection and then output the readings as 16-bit binary integers, and accept commands to control sensor functionality.
We are using a Digilent Cmod A7-35T, specifically the XC7A35T-1CPG236C.
The Hamamatsu C16767MA sensor can be used to measure the UV spectrum of a source. 
The sensitivity of the spectrometer can be adjusted by increasing/decreasing the integration time of the measurement. 
The spectrometer combines a reflective grating and an linear CMOS image sensor in a fingertip-sized package.
Before the reworked software we can obtain 1 spectra every 2 seconds, and with our redesign we can expect up to 170 spectra/s. 
We did lose some functionality with a small display that displayed the spectrum on as distribution, but it was acceptable, as it was not necessary for our purpose.
If we choose to optimise further with a different type of connection, then the sensor itself is limited to 7692 spectra/s for an integration time of 130 microseconds.
The firmware controls detector integration, captures 12-bit ADC samples, stores spectra in dual-port block RAM, and transmits CRC-protected binary frames to a host computer over USB-UART.

## Current Status

The following functionality has been tested:

- FPGA programming with `openFPGALoader`
- Binary command transmission from Python
- 200 µs integration-time configuration
- Acquisition of 288-pixel spectra
- 1 Mbaud UART communication
- Version 2 binary frame transmission
- CRC-16/CCITT-FALSE validation
- Python decoding of complete frames
- Continuous acquisition
- Deterministic FPGA test-pattern modes
- Module-level VHDL simulation

Example validated host output:

```text
seq=0 pixels=288 integration=1000 counts (200.0 us) commands=1 fec=0 crc=ok min=525 max=545
