-- Use IEEE library
library IEEE;
-- Allows use of std_logic
use IEEE.STD_LOGIC_1164.ALL;
-- Import everything from the package named defs; imports all the constants, records, functions and types defined there
use work.defs.all;

-- UART command frame decoder
-- takes a stream of received bytes and reconstructs them into a structured command (cmd_type)

-- UART Command Frame Format
--
-- Byte 0 : 0xEF Header
-- Byte 1 : 0x00 Header
-- Byte 2 : Command Type[15:8]
-- Byte 3 : Command Type[7:0]
-- Byte 4 : Data[31:24]
-- Byte 5 : Data[23:16]
-- Byte 6 : Data[15:8]
-- Byte 7 : Data[7:0]
--
-- Total Frame Length = 8 Bytes
--
-- Example:
-- EF 00 10 00 20 A1 07 00

entity rxCommand is
    port (
        clock:     in  std_logic;
        din:       in  std_logic_vector(7 downto 0);
        din_valid: in  std_logic;
        cmd:       out cmd_type
    );
end rxCommand;


architecture Behavioral of rxCommand is
begin


RX_FRAME_DECODER: process(clock)
    -- Packet position/state counter:
    -- 0 = waiting for header byte EF
    -- 1 = waiting for header byte 00
    -- 2-7 = receiving command payload bytes
    variable i:    natural range 0 to 8 := 0;
    -- Timeout counter used to discard incomplete packets
    variable t:    natural range 0 to 10000001 := 0;
    
    -- Packet buffer:
    -- [47:32] = Command Type (16 bits)
    -- [31:0]  = Command Data (32 bits)
    variable data: std_logic_vector(47 downto 0) := (others => '0');

    -- Packet header identifying the start of a valid command frame
    constant HEADER: std_logic_vector(15 downto 0) := x"EF00";
begin
    if rising_edge(clock) then
        -- cmd.valid is a single-clock pulse asserted only when a
        -- complete command frame has been successfully received
        cmd.valid <= '0';

        if din_valid = '1' then
            -- Reset timeout counter whenever a byte is received.
            t := 0;

            case i is
                when 0 =>
                    -- Waiting for first header byte (EF)
                    if din = HEADER(15 downto 8) then
                        i := 1;
                    end if;

                when 1 =>
                    -- Waiting for second header byte (00)
                    if din = HEADER(7 downto 0) then
                        -- Valid header detected
                        -- Clear packet buffer and begin payload collection
                        i := 2;
                        data := (others => '0');

                    elsif din = HEADER(15 downto 8) then
                        -- Another EF received
                        -- Treat as a potential new frame start
                        i := 1;

                    else
                        -- Invalid header sequence
                        -- Return to idle and search for the next frame
                        i := 0;
                    end if;

                when others =>
                    -- Shift received byte into 48-bit payload register
                    data := data(39 downto 0) & din;

                    if i >= 7 then
                        -- Entire payload received:
                        --
                        -- EF 00
                        -- CMD[15:8]
                        -- CMD[7:0]
                        -- DATA[31:24]
                        -- DATA[23:16]
                        -- DATA[15:8]
                        -- DATA[7:0]
                        -- Return to idle and wait for the next packet
                        i := 0;

                        -- Extract command type field
                        cmd.cmdType <= data(47 downto 32);
                        -- Extract 32-bit command data value
                        cmd.data    <= data(31 downto 0);
                        -- Signal that a complete command is available
                        cmd.valid   <= '1';
                    else
                        -- Continue receiving payload bytes
                        i := i + 1;
                    end if;
            end case;

        elsif i /= 0 then
            -- A packet is currently being received
            -- Abort if the remaining bytes do not arrive within the timeout period
            if t >= 10000000 then
                -- Timeout occurred
                -- Discard partial packet and return to idle
                i := 0;
                t := 0;
                data := (others => '0');
            else
                -- Continue waiting for the next byte
                t := t + 1;
            end if;

        else
            -- No frame currently being received
            -- Keep timeout counter cleared
            t := 0;
        end if;
    end if;
end process;

end Behavioral;