-- =====================================================================
--  File: HDL/temp_payload_gen.vhd
--  Role: Build a small binary telemetry payload from SE95 data.
--
--  Simple 10-byte payload format (example):
--    Byte 0 : 0x54               -- 'T'
--    Byte 1 : raw MSB            -- temp_raw(15 downto 8)
--    Byte 2 : raw LSB            -- temp_raw(7 downto 0)
--    Byte 3 : sign/flags         -- bit0: error flag (i2c_error)
--    Byte 4 : reserved (0x00)
--    Byte 5..9 : reserved (0x00)
--
--  Handshake:
--    * When temp_valid = '1' the module captures temp_raw + i2c_error
--      and outputs a new payload.
--    * payload_valid is pulsed high for one clock.
--
--  Author: Md Shahriar Dipto
--  Mat.Nr.: 5227587
--  Faculty: 4
--  Institution: Hochschule Bremen
-- =====================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity temp_payload_gen is
  generic (
    G_MAX_PAYLOAD : integer := 32           -- width of payload bus in bytes
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;

    temp_raw     : in  std_logic_vector(15 downto 0);
    valid        : in  std_logic;          -- strobe from se95_controller
    i2c_error    : in  std_logic;          -- from se95_controller (led1)

    payload      : out std_logic_vector(G_MAX_PAYLOAD*8-1 downto 0);
    payload_valid: out std_logic;          -- 1-cycle strobe
    payload_len  : out std_logic_vector(7 downto 0)  -- number of bytes used
  );
end entity temp_payload_gen;

architecture rtl of temp_payload_gen is

  constant C_PAY_BYTES : integer := 10;     -- Currently use 10 bytes

  signal pay_reg   : std_logic_vector(G_MAX_PAYLOAD*8-1 downto 0):= (others => '0');
  signal pay_valid : std_logic := '0';

begin

  payload       <= pay_reg;
  payload_valid <= pay_valid;
  payload_len   <= std_logic_vector(to_unsigned(C_PAY_BYTES, 8));

  --------------------------------------------------------------------
  -- Build payload whenever a new temperature sample is valid.
  --------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      pay_valid <= '0';                     -- default

      if rst = '1' then
        pay_reg   <= (others => '0');
        pay_valid <= '0';

      else
        if valid = '1' then
          -- Clear whole buffer first
          pay_reg <= (others => '0');

          -- byte 0: 'T'
          pay_reg(7 downto 0)   <= x"54";

          -- byte 1: raw MSB
          pay_reg(15 downto 8)  <= temp_raw(15 downto 8);

          -- byte 2: raw LSB
          pay_reg(23 downto 16) <= temp_raw(7 downto 0);

          -- byte 3: status flags (bit0 = i2c_error)
          pay_reg(31 downto 24) <= "0000000" & i2c_error;

          -- bytes 4..9 are left at 0x00 (already cleared)

          pay_valid <= '1';                 -- one-cycle strobe
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
