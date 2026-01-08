-- =====================================================================
--  File: HDL/hex_uart_encoder.vhd (extended with SPI/SD logging)
--
--  Author: Md Shahriar Dipto
--  Mat.Nr.: 5227587
--  Faculty: 4
--  Institution: Hochschule Bremen
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hex_uart_encoder is
  port(
    clk        : in  std_logic;
    rst        : in  std_logic;

    -- from AX.25 framer
    byte_in    : in  std_logic_vector(7 downto 0);
    send_in    : in  std_logic;   -- 1-cycle strobe per raw frame byte

    -- from real UART transmitter
    uart_busy  : in  std_logic;   -- busy flag from uart_tx

    -- back-pressure to framer
    fr_busy    : out std_logic;   -- '1' = encoder is still busy

    -- to real UART transmitter
    uart_send  : out std_logic;
    uart_data  : out std_logic_vector(7 downto 0)
  );
end entity hex_uart_encoder;

architecture rtl of hex_uart_encoder is

  type st_t is (S_IDLE, S_HI, S_LO, S_SPACE);
  signal st : st_t := S_IDLE;

  signal b_reg  : std_logic_vector(7 downto 0) := (others => '0');

  signal s_send : std_logic := '0';
  signal s_data : std_logic_vector(7 downto 0) := x"00";

  -- nibble → ASCII hex
  function nibble_to_ascii(n : std_logic_vector(3 downto 0))
    return std_logic_vector is
    variable r : std_logic_vector(7 downto 0);
  begin
    case n is
      when "0000" => r := x"30"; -- '0'
      when "0001" => r := x"31"; -- '1'
      when "0010" => r := x"32"; -- '2'
      when "0011" => r := x"33"; -- '3'
      when "0100" => r := x"34"; -- '4'
      when "0101" => r := x"35"; -- '5'
      when "0110" => r := x"36"; -- '6'
      when "0111" => r := x"37"; -- '7'
      when "1000" => r := x"38"; -- '8'
      when "1001" => r := x"39"; -- '9'
      when "1010" => r := x"41"; -- 'A'
      when "1011" => r := x"42"; -- 'B'
      when "1100" => r := x"43"; -- 'C'
      when "1101" => r := x"44"; -- 'D'
      when "1110" => r := x"45"; -- 'E'
      when others => r := x"46"; -- 'F'
    end case;
    return r;
  end function;

begin
  uart_send <= s_send;
  uart_data <= s_data;

  -- encoder is busy whenever it is not in IDLE
  fr_busy <= '1' when st /= S_IDLE else '0';

  process(clk)
  begin
    if rising_edge(clk) then
      s_send <= '0';  -- default

      if rst = '1' then
        st     <= S_IDLE;
        b_reg  <= (others => '0');
        s_data <= x"00";

      else
        case st is

          ------------------------------------------------------------
          -- Wait for a new frame byte
          ------------------------------------------------------------
          when S_IDLE =>
            if send_in = '1' then
              b_reg <= byte_in;
              st    <= S_HI;
            end if;

          ------------------------------------------------------------
          -- Send high nibble
          ------------------------------------------------------------
          when S_HI =>
            if uart_busy = '0' then
              s_data <= nibble_to_ascii(b_reg(7 downto 4));
              s_send <= '1';
              st     <= S_LO;
            end if;

          ------------------------------------------------------------
          -- Send low nibble
          ------------------------------------------------------------
          when S_LO =>
            if uart_busy = '0' then
              s_data <= nibble_to_ascii(b_reg(3 downto 0));
              s_send <= '1';
              st     <= S_SPACE;
            end if;

          ------------------------------------------------------------
          -- Send separating space
          ------------------------------------------------------------
          when S_SPACE =>
            if uart_busy = '0' then
              s_data <= x"20";   -- ' '
              s_send <= '1';
              st     <= S_IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;

end architecture rtl;
