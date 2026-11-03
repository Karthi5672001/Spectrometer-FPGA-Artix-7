----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 13.05.2025 13:23:16
-- Design Name: 
-- Module Name: readout - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.defs.all;



entity dataReadout is port(
    sysClk:         in std_logic;
    trig:           in std_logic;
    parameter:      in parameterList_type;

    txByte:         out std_logic_vector(7 downto 0);
    txValid:        out std_logic;
    txWait:         in std_logic;       -- signal from the fifo to say it is nearly full - don't transmit anything until it goes low again

 -- data readout signals 
    done:           out std_logic;
    addr:           out std_logic_vector(8 downto 0);          
    data:           in std_logic_vector(15 downto 0));


end dataReadout;

architecture Behavioral of dataReadout is



constant frameHeader: std_logic_vector(31 downto 0):= x"abcdef00";      -- a unique pattern to identify start of frame

signal asciiHex: std_logic_vector(15 downto 0);
signal binData: std_logic_vector(7 downto 0);
signal trig_z: std_logic;



begin








DATA_READOUT: process(sysClk)
variable state: natural:=0;
variable sampleNum: natural:= 0;
variable i: natural;
constant numberOfSamples: natural:= DATA_LEN;
variable txWord: std_logic_vector(15 downto 0);
variable testData: natural;
begin
    if (rising_edge(sysClk)) then
        
        trig_z <= trig;
        
        
        
        case state is
        
            when 0 =>               -- done
                txValid <= '0';
                if (trig = '1' and trig_z = '0') then   -- rising edge detect
                    done <= '0';
                    state := 1;
                else
                    done <= '1';
                end if;
              
                
                
            -- send header                
                
            when 1 =>
                i := 3;         -- init. start with byte 3
                state := 2;
                
            when 2 =>                        
                binData <= frameHeader(i*8+7 downto i*8);
                state := 3;                                                                
                
            when 3 =>       -- send ascii high byte            
                txValid <= '1';
                txByte <= toAsciiHex(binData(7 downto 4));            
                state := 4;                                
                
            when 4 =>       -- send ascii low byte    
                txValid <= '1';
                txByte <= toAsciiHex(binData(3 downto 0));            
                state := 5;                
                
            when 5 =>
                txValid <= '0';
                if (i = 0) then 
                    state := 6; 
                else
                    i := i - 1;
                    state := 2;
                end if;
            
            when 6 =>                   -- send line feed
                txValid <= '1';
                txByte <= x"0A";            
                state := 8;--7;               
                
          --  when 7 =>                   -- send carriage return
            --    txValid <= '1';
            --    txByte <= x"0D";                    
           --     state := 8;               
                
            when 8 =>
                txValid <= '0';
                state := 10;
                
                
                
                
                
            -- send data                
                
            when 10 =>
                sampleNum := 0;     -- initialize. Start at address 0
                testData := 0;
                state := 11;
                
            when 11 =>                  -- wait for data to be available on next clock after address is applied         
                state := 12;                
                            
            when 12 =>                  -- select data (test or actual)       
                if (parameter.readout.useTestData = '0') then
                    txWord := data;
                else
                    if (sampleNum = 144) then
                        txWord := x"0fff";
                    else
                        txWord := std_logic_vector(to_unsigned(testData,16));
                    end if;
                end if;
                testData := testData + 10;
                if (testData > 4095) then testData := 4095;  end if;
                
                if (txWait = '0') then      -- wait until serial tx fifo is clear to send
                    state := 13;                
                end if;
                
            when 13 =>
                txValid <= '1';
                txByte <= toAsciiHex(txWord(15 downto 12));  
                state := 14;
                
            when 14 =>
                txValid <= '1';
                txByte <= toAsciiHex(txWord(11 downto 8));
                state := 16;
                
            when 16 =>
                txValid <= '1';
                txByte <= toAsciiHex(txWord(7 downto 4));
                state := 17;
                
            when 17 =>
                txValid <= '1';
                txByte <= toAsciiHex(txWord(3 downto 0));
                state := 20;                                
                
            when 20 =>                   -- send line feed
                txValid <= '1';
                txByte <= x"0A";            
                state := 22;--21;               
                
         --   when 21 =>                   -- send carriage return
          --      txValid <= '1';
          --      txByte <= x"0D";                    
          --      state := 22;               
                
            when 22 =>
                txValid <= '0';
                state := 23;

            when 23 =>
                txValid <= '0';
                sampleNum := sampleNum + 1;
                if (sampleNum >= numberOfSamples) then
                    state := 0;
                else
                    state := 11;
                end if;
            
                 
            when others =>
            
                null;            
                    
        
        end case;
        
        

        addr <= std_logic_vector(to_unsigned(sampleNum,9));

    end if;
end process;




end Behavioral;
