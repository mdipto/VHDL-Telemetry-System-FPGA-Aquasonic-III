-- =====================================================================
--  File: rtl/spi_master.vhd (extended with SPI/SD logging)
--  Role: Simple mode-0 SPI master (byte-wide transfers)
--
--  Author: Md Shahriar Dipto
--  Mat.Nr.: 5227587
--  Faculty: 4
--  Institution: Hochschule Bremen
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_master is
  generic(
    G_CLK_HZ : integer := 125_000_000;
    G_SPI_HZ : integer := 20_000_000; -- SCLK frequency
    G_CPOL   : std_logic := '0';
    G_CPHA   : std_logic := '0'
  );
  port(
    clk     : in  std_logic;
    rst     : in  std_logic;

    start   : in  std_logic;                      -- strobe: start transfer
    tx_byte : in  std_logic_vector(7 downto 0);   -- byte to send
    rx_byte : out std_logic_vector(7 downto 0);   -- byte received
    busy    : out std_logic;                      -- '1' while active
    done    : out std_logic;                      -- 1-cycle pulse when finished

    sclk    : out std_logic;
    mosi    : out std_logic;
    miso    : in  std_logic;
    cs_n    : out std_logic
  );
end entity spi_master;

architecture rtl of spi_master is

  constant DIV : integer := G_CLK_HZ / (2 * G_SPI_HZ); -- 2 edges per bit

  type st_t is (S_IDLE, S_ASSERT, S_BIT, S_DEASSERT);
  signal st   : st_t := S_IDLE;

  signal cnt  : integer range 0 to DIV-1 := 0;
  signal bitn : integer range 0 to 7 := 7;

  signal sclk_i  : std_logic := G_CPOL;
  signal cs_n_i  : std_logic := '1';
  signal mosi_i  : std_logic := '0';
  signal rx_reg  : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_reg  : std_logic_vector(7 downto 0) := (others => '0');
  signal busy_i  : std_logic := '0';
  signal done_i  : std_logic := '0';

begin
  sclk   <= sclk_i;
  cs_n   <= cs_n_i;
  mosi   <= mosi_i;
  rx_byte <= rx_reg;
  busy   <= busy_i;
  done   <= done_i;

  process(clk)
  begin
    if rising_edge(clk) then
      done_i <= '0';

      if rst = '1' then
        st      <= S_IDLE;
        sclk_i  <= G_CPOL;
        cs_n_i  <= '1';
        busy_i  <= '0';
        cnt     <= 0;
        bitn    <= 7;
        mosi_i  <= '0';
      else
        case st is

          when S_IDLE =>
            busy_i <= '0';
            cs_n_i <= '1';
            sclk_i <= G_CPOL;
            if start = '1' then
              tx_reg <= tx_byte;
              rx_reg <= (others => '0');
              bitn   <= 7;
              cnt    <= 0;
              cs_n_i <= '0';     -- select slave
              busy_i <= '1';
              st     <= S_ASSERT;
            end if;

          when S_ASSERT =>
            -- prepare initial MOSI value
            mosi_i <= tx_reg(7);
            st     <= S_BIT;

          when S_BIT =>
            if cnt = DIV-1 then
              cnt    <= 0;
              sclk_i <= not sclk_i;

              -- sample / shift on appropriate edges (Mode 0)
              if sclk_i = '0' then
                -- rising edge just happened
                rx_reg(bitn) <= miso;
              else
                -- falling edge just happened: shift next bit out
                if bitn = 0 then
                  st <= S_DEASSERT;
                else
                  bitn   <= bitn - 1;
                  tx_reg <= tx_reg(6 downto 0) & '0';
                  mosi_i <= tx_reg(6);  -- next bit
                end if;
              end if;
            else
              cnt <= cnt + 1;
            end if;

          when S_DEASSERT =>
            cs_n_i  <= '1';
            sclk_i  <= G_CPOL;
            busy_i  <= '0';
            done_i  <= '1';
            st      <= S_IDLE;

        end case;
      end if;
    end if;
  end process;

end architecture rtl;
