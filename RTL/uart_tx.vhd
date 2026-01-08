-- =====================================================================
--  Module: uart_tx.vhd
--  Role: Simple UART transmitter
--
--  Author: Md Shahriar Dipto
--  Mat.Nr.: 5227587
--  Faculty: 4
--  Institution: Hochschule Bremen
--
--  Description:
--    Sends 8-bit data frames over a single TX line using standard
--    asynchronous serial format:
--
--        1 start bit  (low)
--        8 data bits  (LSB first)
--        1 stop bit   (high)
--
--    The design is clocked by the system clock (G_CLK_HZ) and uses an
--    internal counter to generate the required baud rate (G_BAUD).
--
--    Handshake:
--      * When 'send' is pulsed high for one clock cycle in S_IDLE,
--        the module latches 'data' and transmits it.
--      * While a byte is being transmitted, 'busy' = '1'.
--      * 'txd' idles high when no character is sent.
-- =====================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- =========================
-- Entity
-- =========================
entity uart_tx is
  generic(
    G_CLK_HZ : integer := 125_000_000;  -- system clock frequency in Hz
    G_BAUD   : integer := 115200        -- UART baud rate
  );
  port(
    clk  : in  std_logic;               -- system clock
    rst  : in  std_logic;               -- synchronous reset (active '1')
    txd  : out std_logic;               -- serial transmit line
    send : in  std_logic;               -- strobe: request to send 'data'
    data : in  std_logic_vector(7 downto 0); -- byte to send (LSB first)
    busy : out std_logic                -- '1' while a frame is in progress
  );
end entity uart_tx;

-- =========================
-- Architecture
-- =========================
architecture rtl of uart_tx is

  --------------------------------------------------------------------
  -- Number of system clock cycles per UART bit time.
  -- Example: 125 MHz / 115200 ≈ 1085 clocks per bit.
  --------------------------------------------------------------------
  constant DIV : integer := G_CLK_HZ / G_BAUD;

  --------------------------------------------------------------------
  -- Transmitter FSM states:
  --   S_IDLE  : line idle, waiting for send request
  --   S_START : transmitting start bit (0)
  --   S_DATA  : transmitting 8 data bits (LSB first)
  --   S_STOP  : transmitting stop bit (1)
  --------------------------------------------------------------------
  type st_t is (S_IDLE, S_START, S_DATA, S_STOP);
  signal st : st_t := S_IDLE;

  --------------------------------------------------------------------
  -- Internal registers
  --------------------------------------------------------------------
  signal sh   : std_logic_vector(7 downto 0) := (others => '0'); -- shift reg for data
  signal bitn : integer range 0 to 7 := 0;                       -- current bit index
  signal cnt  : integer range 0 to DIV-1 := 0;                   -- bit-time counter
  signal tx   : std_logic := '1';                                -- actual TX line (idle high)
  signal bsy  : std_logic := '0';                                -- internal busy flag

begin

  -- Drive outputs from internal signals
  txd  <= tx;
  busy <= bsy;

  --------------------------------------------------------------------
  -- Main UART transmit process
  --------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        ----------------------------------------------------------------
        -- Reset all internal state
        ----------------------------------------------------------------
        st   <= S_IDLE;
        tx   <= '1';     -- idle level on TX
        bsy  <= '0';
        cnt  <= 0;
        bitn <= 0;

      else
        ----------------------------------------------------------------
        -- State machine
        ----------------------------------------------------------------
        case st is

          --------------------------------------------------------------
          -- S_IDLE : line is idle (TX = '1'), waiting for send request
          --------------------------------------------------------------
          when S_IDLE =>
            bsy <= '0';         -- not busy
            tx  <= '1';         -- idle high

            if send = '1' then
              -- Latch data, prepare to send start bit
              sh   <= data;     -- copy input byte to shift register
              bitn <= 0;        -- start from bit 0 (LSB)
              st   <= S_START;
              bsy  <= '1';      -- transmitter now busy
              cnt  <= 0;        -- restart bit-time counter
            end if;

          --------------------------------------------------------------
          -- S_START : output start bit ('0') for one bit-time
          --------------------------------------------------------------
          when S_START =>
            tx <= '0';          -- start bit is logic low

            if cnt = DIV - 1 then
              -- One full bit time elapsed -> move to data bits
              cnt <= 0;
              st  <= S_DATA;
            else
              -- keep counting clocks inside this bit time
              cnt <= cnt + 1;
            end if;

          --------------------------------------------------------------
          -- S_DATA : transmit 8 data bits (LSB first)
          --------------------------------------------------------------
          when S_DATA =>
            -- At the *beginning* of each bit period (cnt = 0)
            -- put the next data bit onto TX and shift the register.
            if cnt = 0 then
              tx <= sh(0);                     -- output LSB
              sh <= '0' & sh(7 downto 1);      -- logical right shift
            end if;

            if cnt = DIV - 1 then
              -- End of current bit period
              cnt <= 0;

              if bitn = 7 then
                -- All 8 bits transmitted -> go send stop bit
                st <= S_STOP;
              else
                -- Go to next data bit
                bitn <= bitn + 1;
              end if;
            else
              -- Still inside this bit time
              cnt <= cnt + 1;
            end if;

          --------------------------------------------------------------
          -- S_STOP : output stop bit ('1') for one bit-time, then done.
          --------------------------------------------------------------
          when S_STOP =>
            tx <= '1';          -- stop bit and idle level are '1'

            if cnt = DIV - 1 then
              -- Stop bit finished -> back to idle
              st  <= S_IDLE;
              cnt <= 0;
            else
              cnt <= cnt + 1;
            end if;

        end case; -- st
      end if;     -- rst
    end if;       -- rising_edge(clk)
  end process;

end architecture rtl;
