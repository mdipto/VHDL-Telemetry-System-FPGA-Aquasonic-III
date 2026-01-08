-- =====================================================================
-- Testbench: tb_top_pynq_se95
-- Purpose  : Full-system simulation:
--            SE95 I2C controller + AX.25 + UART + SPI/SD top level.
--
--  Author: Md Shahriar Dipto
--  Mat.Nr.: 5227587
--  Faculty: 4
--  Institution: Hochschule Bremen
-- =====================================================================

library ieee;
use ieee.std_logic_1164.all;

entity tb_top_pynq_se95 is
end entity tb_top_pynq_se95;

architecture test of tb_top_pynq_se95 is

  signal clk_125mhz : std_logic := '0';
  signal rst_tb     : std_logic := '1';

  -- I2C
  signal i2c_sda_w  : std_logic := 'Z';
  signal i2c_scl_w  : std_logic := 'Z';

  -- UART + LEDs
  signal uart_tx    : std_logic := '1';
  signal led0, led1 : std_logic := '0';
  signal led2, led3 : std_logic := '0';

  -- SPI
  signal sd_mosi    : std_logic := '0';
  signal sd_miso    : std_logic := '1';  -- idle high
  signal sd_sclk    : std_logic := '0';
  signal sd_cs_n    : std_logic := '1';

begin
  --------------------------------------------------------------------
  -- 125 MHz clock
  --------------------------------------------------------------------
  clk_125mhz <= not clk_125mhz after 4 ns;

  --------------------------------------------------------------------
  -- Pull-ups for I2C
  --------------------------------------------------------------------
  PU_SDA : entity work.pullup
    port map ( line => i2c_sda_w );

  PU_SCL : entity work.pullup
    port map ( line => i2c_scl_w );

  --------------------------------------------------------------------
  -- DUT: top_pynq_se95  (new port list incl. SPI + LEDs)
  --------------------------------------------------------------------
  DUT : entity work.top_pynq_se95
    port map(
      clk_125mhz => clk_125mhz,
      rst        => rst_tb,
      i2c_sda    => i2c_sda_w,
      i2c_scl    => i2c_scl_w,
      uart_tx    => uart_tx,
      led0       => led0,
      led1       => led1,
      led2       => led2,
      led3       => led3,
      sd_mosi    => sd_mosi,
      sd_miso    => sd_miso,
      sd_sclk    => sd_sclk,
      sd_cs_n    => sd_cs_n
    );

  --------------------------------------------------------------------
  -- SE95 I2C slave model
  --------------------------------------------------------------------
  SE95 : entity work.se95_slave_model
    port map(
      sda => i2c_sda_w,
      scl => i2c_scl_w
    );

  --------------------------------------------------------------------
  -- Reset
  --------------------------------------------------------------------
  process
  begin
    wait until rising_edge(clk_125mhz); -- 1st
    wait until rising_edge(clk_125mhz); -- 2nd
    rst_tb <= '0';
    wait;
  end process;

end architecture test;

