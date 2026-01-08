-- =====================================================================
--  File: HDL/crc16_x25.vhd
--  Role: CRC-16/X.25 calculator for AX.25 frames.
--
--  Polynomial : 0x1021 (reflected form 0x8408)
--  Init value : 0xFFFF
--  Output     : crc_out = internal_crc XOR 0xFFFF
--  Bit order  : LSB-first per byte (as in AX.25)
-- =====================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity crc16_x25 is
  port(
    clk     : in  std_logic;
    rst     : in  std_logic;
    init    : in  std_logic;             -- '1' to (re)init CRC to 0xFFFF
    data_in : in  std_logic_vector(7 downto 0);
    data_we : in  std_logic;             -- strobe for this input byte
    crc_out : out std_logic_vector(15 downto 0)
  );
end entity crc16_x25;

architecture rtl of crc16_x25 is
  signal crc : unsigned(15 downto 0) := (others => '1'); -- 0xFFFF
begin
  -- AX.25 transmits 1's-complement of CRC
  crc_out <= std_logic_vector(crc xor x"FFFF");

   process(clk)
    variable c : unsigned(15 downto 0);
    variable d : unsigned(7 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' or init = '1' then
        crc <= (others => '1');                  -- 0xFFFF
      elsif data_we = '1' then
        c := crc;
        d := unsigned(data_in);

        -- Process 8 bits, LSB-first
        for i in 0 to 7 loop
          if (c(0) xor d(0)) = '1' then
            c := (c(15 downto 1) & '0') xor x"8408";  -- reflected poly
          else
            c := (c(15 downto 1) & '0');
          end if;
          d := ('0' & d(7 downto 1));
        end loop;

        crc <= c;
      end if;
    end if;
  end process;
end architecture rtl;
