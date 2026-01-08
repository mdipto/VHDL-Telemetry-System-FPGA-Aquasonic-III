-- =====================================================================
-- Testbench: tb_spi_master_loopback
-- Purpose  : Verify spi_master timing by looping MOSI back to MISO.
--
--  Author: Md Shahriar Dipto
--  Mat.Nr.: 5227587
--  Faculty: 4
--  Institution: Hochschule Bremen
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_spi_master_loopback is
end entity tb_spi_master_loopback;

architecture sim of tb_spi_master_loopback is

  constant C_CLK_HZ : integer := 125_000_000;
  constant C_SPI_HZ : integer := 10_000_000;

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';

  signal start : std_logic := '0';
  signal tx    : std_logic_vector(7 downto 0) := (others => '0');
  signal rx    : std_logic_vector(7 downto 0);
  signal busy  : std_logic;
  signal done  : std_logic;

  signal sclk  : std_logic;
  signal mosi  : std_logic;
  signal miso  : std_logic;
  signal cs_n  : std_logic;

begin

  clk <= not clk after 4 ns;

  -- loopback
  miso <= mosi;

  DUT : entity work.spi_master
    generic map(
      G_CLK_HZ => C_CLK_HZ,
      G_SPI_HZ => C_SPI_HZ,
      G_CPOL   => '0',
      G_CPHA   => '0'
    )
    port map(
      clk     => clk,
      rst     => rst,
      start   => start,
      tx_byte => tx,
      rx_byte => rx,
      busy    => busy,
      done    => done,
      sclk    => sclk,
      mosi    => mosi,
      miso    => miso,
      cs_n    => cs_n
    );

  stim : process
    variable v_int : integer;
  begin
    wait for 200 ns;
    rst <= '0';

    for val in 0 to 3 loop
      v_int := (val * 16) + 5;
      tx    <= std_logic_vector(to_unsigned(v_int, 8));
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';

      wait until done = '1';

      report "TX=" &
             integer'image(to_integer(unsigned(tx))) &
             " RX=" &
             integer'image(to_integer(unsigned(rx)));

      wait until rising_edge(clk);
    end loop;

    wait for 1 us;
    report "spi_master loopback finished" severity failure;
  end process;

end architecture sim;

