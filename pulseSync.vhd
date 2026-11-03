---------------------------------------------------------------------------------
-- FILE:         synchronizer.vhd
-- AUTHOR:       D. Greenshields
-- DATE:         Oct 2020
--
-- DESCRIPTION:  used to transfer valid signals from one clock domain to another
--                note that valid_in must not be high for two consecutive  
--                clock cycles
--
---------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use work.defs.all;


entity pulseSync is
   port (
      inClock	    : in std_logic;
		outClock     : in std_logic;
		din_valid	 : in	std_logic;       
      dout_valid   : out std_logic);
		
end pulseSync;

architecture vhdl of pulseSync is
   
   signal sync_latch : std_logic;
   signal sync_latch_z : std_logic;
   signal sync_reset : std_logic;
   signal valid_in_z : std_logic;
	
begin	


------------------------------------
--	DATA SYNCHRONIZER
------------------------------------


-- Purpose is to take a single 'data valid' pulse in from one clock domain,
-- and forward it to another clock domain also as a single pulse
--
-- assumptions
-- 1. Data in and valid in will arrive on rising edge of clock in
-- 2. data_in will remain unchanged until a new din valid appears
-- 3. there will never be two consecutive 1's on valid in


FALLING_EDGE_DETECT: process(inClock)
--latch valid_in on the falling edge of clock in
--
-- This gives a safeguard that there is some delay between valid in rising 
-- and the output clock clocking the data, thus ensuring the clock out
-- does not rise before the data is present at the input
begin
   if (falling_edge(inClock)) then
      valid_in_z <= din_valid;
   end if;
end process;


-- detect rising edge on valid in
RISING_EDGE_DETECT: process(valid_in_z, sync_reset)
begin
   if (sync_reset = '1') then 
      sync_latch <= '0';
   elsif (rising_edge(valid_in_z)) then
      sync_latch <= '1';  
   end if;
end process;


-- clock the data and valid out using the out clock
-- and reset the latch
VALID_DATA_OUT: process(outClock)
begin
   if (rising_Edge(OutClock)) then
      sync_latch_z <= sync_latch; 
   end if;
   if (falling_edge(OutClock)) then
      sync_reset <= sync_latch_z;
   end if;
end process;
   
dout_valid <= sync_latch_z; 
 
end vhdl;





