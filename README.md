# Spectrometer-FPGA-Artix-7
VHDL code for a Hamamatsu UV spectrometer (polychromator) C16767MA, which is used by the FPGA to take the spectrometer readings and transfer to the Host PC to ensure minimal latency and maximum data throughput. FPGA communicate to PC via serial connection and then output the readings as 16-bit binary integers, and accept commands to control sensor functionality.

We are using a Cmod A7-35T, specifically the XC7A35T-1CPG236C
The Hamamatsu C16767MA sensor can be used to measure the UV spectrum of a source. The sensitivity of the spectrometer can be adjusted by increasing/decreasing the integration time of the measurement. The spectrometer combines a reflective grating and an linear CMOS image sensor in a fingertip-sized package.

The reason for changing this code from the original is that more data is needed to train the models used for the Physics-Informed Neural Network (PINN), which required substantially more data that we already have. Currently we can obtain 1 spectra every 2 seconds, and with our redesign we can expect up to 170 spectra/s. If we choose to optimise further with a different type of connection, then the sensor itself is limited to 7692 spectra/s for an integration time of 130 microseconds.
