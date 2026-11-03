# Spectrometer-FPGA-Artix-7
VHDL code for a Hamamatsu UV spectrometer C16767MA, which is used by the FPGA to take the spectrometer readings and transfer to the Host PC to ensure minimal latency and maximum data throughput. FPGA communicate to PC via serial connection and then output the readings as 16-bit binary integers, and accept commands to control sensor functionality
