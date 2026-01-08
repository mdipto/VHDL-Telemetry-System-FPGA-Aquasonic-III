-- =====================================================================
--  Module: bin_to_bcd.vhd
--  Role: Convert an unsigned binary number into BCD digits using
--      the "Double-Dabble" (Shift-Add-3) algorithm.
--
--  Author: Md Shahriar Dipto
--  Mat.Nr.: 5227587
--  Faculty: 4
--  Institution: Hochschule Bremen
--
--  Description:
--      Converts a binary input |din| into BCD format. Designed for
--      fixed, synchronous pipelined operation. 
--
--      Input width      = G_IN_WIDTH bits   (default 24-bit)
--      Output BCD digits = G_DIGITS digits  (default 8 digits)
--
--      Handshake:
--         start = '1'  → begin conversion
--         busy  = '1'  → algorithm running
--         valid = '1'  → conversion complete (one clock pulse)
--
--      Algorithm steps per clock:
--        1) For each BCD digit:
--             if digit >= 5 then digit += 3   (decimal adjust)
--        2) Shift the entire BCD+binary register left by 1 bit
--
--      After G_IN_WIDTH cycles → BCD result ready.
-- =====================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ===========================
-- Entity Definition
-- ===========================
entity bin_to_bcd is
  generic(
    G_IN_WIDTH : integer := 24;   -- number of binary input bits
    G_DIGITS   : integer := 8     -- number of BCD digits to produce
  );
  port(
    clk, rst, start : in  std_logic;                 -- handshake
    din             : in  unsigned(G_IN_WIDTH-1 downto 0); -- binary input
    busy, valid     : out std_logic;                 -- status flags
    bcd             : out std_logic_vector(G_DIGITS*4-1 downto 0)
  );
end entity bin_to_bcd;

-- ===========================
-- Architecture
-- ===========================
architecture rtl of bin_to_bcd is

  -- A vector of BCD digits (4-bit each)
  type bcd_vec_t is array (natural range <>) of unsigned(3 downto 0);

  -- BCD digit storage: digits(0) = least significant BCD digit
  signal bin    : unsigned(G_IN_WIDTH-1 downto 0) := (others => '0'); -- shifting binary input
  signal digits : bcd_vec_t(0 to G_DIGITS-1)      := (others => (others => '0'));

  signal n      : integer range 0 to G_IN_WIDTH   := 0;  -- cycle counter
  signal s_busy : std_logic                       := '0';
  signal s_valid: std_logic                       := '0';

begin

  -- expose internal status signals
  busy  <= s_busy;
  valid <= s_valid;

  -- --------------------------------------------------------------
  -- Export BCD digits as a packed std_logic_vector
  -- digits(7) (MS digit) → bcd[31:28]
  -- digits(0) (LS digit) → bcd[3:0]
  -- --------------------------------------------------------------
  bcd <= std_logic_vector(digits(7)) &
         std_logic_vector(digits(6)) &
         std_logic_vector(digits(5)) &
         std_logic_vector(digits(4)) &
         std_logic_vector(digits(3)) &
         std_logic_vector(digits(2)) &
         std_logic_vector(digits(1)) &
         std_logic_vector(digits(0));

  -- ===========================
  -- Main sequential process
  -- ===========================
  process(clk)
  begin
    if rising_edge(clk) then

      -- valid output is a 1-clock pulse
      s_valid <= '0';

      if rst = '1' then
        ---------------------------------------------------------
        -- Reset state
        ---------------------------------------------------------
        s_busy <= '0';
        n      <= 0;
        digits <= (others => (others => '0'));
        bin    <= (others => '0');

      else
        ---------------------------------------------------------
        -- If not busy, wait for start strobe
        ---------------------------------------------------------
        if s_busy = '0' then
          if start = '1' then
            -- Initialize everything for new conversion
            digits <= (others => (others => '0')); -- clear output digits
            bin    <= din;                         -- load binary input
            n      <= G_IN_WIDTH;                  -- number of shifts to run
            s_busy <= '1';
          end if;

        else
          ---------------------------------------------------------
          -- 1) "Add 3" step for each BCD digit
          --    If a digit is 5..9 and we left-shift, decimal adjust required.
          ---------------------------------------------------------
          for d in 0 to G_DIGITS-1 loop
            if digits(d) >= 5 then
              digits(d) <= digits(d) + 3;          -- add-3 correction
            end if;
          end loop;

          ---------------------------------------------------------
          -- 2) Shift everything LEFT by 1:
          --      - MSB of binary input enters BCD digit 0
          --      - each digit's MSB shifts into next digit up
          ---------------------------------------------------------
          for d in G_DIGITS-1 downto 1 loop
            digits(d) <= digits(d)(2 downto 0) & digits(d-1)(3);
          end loop;

          -- New bit entering BCD(0)
          digits(0) <= digits(0)(2 downto 0) & bin(G_IN_WIDTH-1);

          -- Shift binary input left by 1
          bin <= bin(G_IN_WIDTH-2 downto 0) & '0';

          ---------------------------------------------------------
          -- Decrement iteration counter
          ---------------------------------------------------------
          n <= n - 1;

          -- When one cycle remains, this shift completes all input bits
          if n = 1 then
            s_busy  <= '0'; -- finished
            s_valid <= '1'; -- output ready
          end if;

        end if; -- busy
      end if; -- rst

    end if; -- rising_edge

  end process;

end architecture rtl;
