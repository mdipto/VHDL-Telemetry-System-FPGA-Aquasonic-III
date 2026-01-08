-- ===================================================================== 
-- File: HDL/top_pynq_se95.vhd (extended with SPI/SD logging) 
-- Role: Top-level design for PYNQ-Z2 board with AX.25 framing 
-- and ASCII hex dump on UART (for PuTTY). 
-- 
-- Author: Md Shahriar Dipto 
-- Mat.Nr.: 5227587 
-- Faculty: 4 
-- Institution: Hochschule Bremen 
-- ===================================================================== 
library ieee; 
use ieee.std_logic_1164.all; 
use ieee.numeric_std.all; 

entity top_pynq_se95 is 
    port( clk_125mhz : in std_logic; 
          rst : in std_logic; 
          -- I2C 
          i2c_sda : inout std_logic; 
          i2c_scl : inout std_logic; 
          -- UART 
          uart_tx : out std_logic; 
          -- LEDs 
          led0 : out std_logic; 
          led1 : out std_logic; 
          led2 : out std_logic; -- NEW: SD init/status 
          led3 : out std_logic; -- NEW: SD write activity 
          -- SPI to microSD (mode 0) 
          sd_mosi : out std_logic; 
          sd_miso : in std_logic; 
          sd_sclk : out std_logic; 
          sd_cs_n : out std_logic 
          ); 
end entity top_pynq_se95; 
architecture rtl of top_pynq_se95 is

  -- ===================================================================
  -- Existing signals
  -- ===================================================================
  signal temp_raw        : std_logic_vector(15 downto 0);
  signal temp_valid      : std_logic;
  signal i2c_error_s     : std_logic;

  signal led0_reg        : std_logic := '0';

  signal t_payload       : std_logic_vector(79 downto 0); -- 10 bytes
  signal t_payload_valid : std_logic;
  signal t_payload_len   : std_logic_vector(7 downto 0);

  signal fr_data         : std_logic_vector(7 downto 0);
  signal fr_send         : std_logic;
  signal fr_busy         : std_logic;
  signal frame_active    : std_logic;

  signal uart_busy       : std_logic;
  signal uart_send       : std_logic;
  signal uart_data       : std_logic_vector(7 downto 0);

  -- ===================================================================
  -- NEW: SPI / SD logging signals
  -- ===================================================================
  signal spi_sclk        : std_logic;
  signal spi_mosi        : std_logic;
  signal spi_cs_n        : std_logic;

  -- handshake between sd_spi_controller and spi_master
  signal sd_spi_start    : std_logic;
  signal sd_spi_tx       : std_logic_vector(7 downto 0);
  signal sd_spi_rx       : std_logic_vector(7 downto 0);
  signal sd_spi_busy     : std_logic;
  signal sd_spi_done     : std_logic;

  -- handshake between logger and sd controller
  signal log_wr_req      : std_logic;
  signal log_wr_sector   : std_logic_vector(31 downto 0);
  signal log_wr_data     : std_logic_vector(7 downto 0);
  signal log_wr_idx      : std_logic_vector(8 downto 0);

  signal sd_init_done    : std_logic;
  signal sd_error        : std_logic;
  signal sd_wr_busy      : std_logic;

begin
  ----------------------------------------------------------------------
  -- LED0 toggles on each new temperature sample
  ----------------------------------------------------------------------
  process(clk_125mhz)
  begin
    if rising_edge(clk_125mhz) then
      if rst = '1' then
        led0_reg <= '0';
      elsif temp_valid = '1' then
        led0_reg <= not led0_reg;
      end if;
    end if;
  end process;

  led0 <= led0_reg;
  led1 <= i2c_error_s;

  -- LED2 = SD init OK, LED3 = SD write busy
  led2 <= sd_init_done and not sd_error;
  led3 <= sd_wr_busy;

  -- Map internal SPI signals to pins
  sd_sclk <= spi_sclk;
  sd_mosi <= spi_mosi;
  sd_cs_n <= spi_cs_n;

  ----------------------------------------------------------------------
  -- SE95 I2C controller
  ----------------------------------------------------------------------
  U_CTRL : entity work.se95_controller
    generic map(
      CLK_HZ   => 125_000_000,
      I2C_FREQ => 100_000
    )
    port map(
      clk        => clk_125mhz,
      rst        => rst,
      sda        => i2c_sda,
      scl        => i2c_scl,
      temp_data  => temp_raw,
      temp_valid => temp_valid,
      error_led  => i2c_error_s
    );

  ----------------------------------------------------------------------
  -- Telemetry payload generator (10 bytes)
  ----------------------------------------------------------------------
  U_PAYLOAD : entity work.temp_payload_gen
    generic map(
      G_MAX_PAYLOAD => 10
    )
    port map(
      clk           => clk_125mhz,
      rst           => rst,
      temp_raw      => temp_raw,
      valid         => temp_valid,
      i2c_error     => i2c_error_s,
      payload       => t_payload,
      payload_valid => t_payload_valid,
      payload_len   => t_payload_len
    );

  ----------------------------------------------------------------------
  -- AX.25 framer + hex encoder + UART
  ----------------------------------------------------------------------
  U_FRAMER : entity work.ax25_framer
    generic map(
      G_MAX_PAYLOAD => 10
    )
    port map(
      clk           => clk_125mhz,
      rst           => rst,
      payload       => t_payload,
      payload_len   => t_payload_len,
      payload_valid => t_payload_valid,
      uart_busy     => fr_busy,
      uart_send     => fr_send,
      uart_data     => fr_data,
      frame_active  => frame_active
    );

  U_HEX : entity work.hex_uart_encoder
    port map(
      clk        => clk_125mhz,
      rst        => rst,
      byte_in    => fr_data,
      send_in    => fr_send,
      uart_busy  => uart_busy,
      fr_busy    => fr_busy,
      uart_send  => uart_send,
      uart_data  => uart_data
    );

  U_UART : entity work.uart_tx
    generic map(
      G_CLK_HZ => 125_000_000,
      G_BAUD   => 115200
    )
    port map(
      clk  => clk_125mhz,
      rst  => rst,
      txd  => uart_tx,
      send => uart_send,
      data => uart_data,
      busy => uart_busy
    );

  ----------------------------------------------------------------------
  -- SPI master
  ----------------------------------------------------------------------
  U_SPI : entity work.spi_master
    generic map(
      G_CLK_HZ => 125_000_000,
      G_SPI_HZ => 20_000_000,   -- max 25 MHz for SD
      G_CPOL   => '0',
      G_CPHA   => '0'
    )
    port map(
      clk     => clk_125mhz,
      rst     => rst,
      start   => sd_spi_start,
      tx_byte => sd_spi_tx,
      rx_byte => sd_spi_rx,
      busy    => sd_spi_busy,
      done    => sd_spi_done,
      sclk    => spi_sclk,
      mosi    => spi_mosi,
      miso    => sd_miso,
      cs_n    => spi_cs_n
    );

  ----------------------------------------------------------------------
  -- SD card controller
  ----------------------------------------------------------------------
  U_SD : entity work.sd_spi_controller
    port map(
      clk         => clk_125mhz,
      rst         => rst,
      spi_start   => sd_spi_start,
      spi_tx      => sd_spi_tx,
      spi_rx      => sd_spi_rx,
      spi_busy    => sd_spi_busy,
      spi_done    => sd_spi_done,
      wr_req      => log_wr_req,
      wr_busy     => sd_wr_busy,
      wr_sector   => log_wr_sector,
      wr_data     => log_wr_data,
      wr_data_idx => log_wr_idx,
      init_done   => sd_init_done,
      error_flag  => sd_error
    );

  ----------------------------------------------------------------------
  -- Temperature logger → SD sectors
  ----------------------------------------------------------------------
  U_LOG : entity work.temp_spi_logger
    generic map(
      G_PAY_BYTES => 10
    )
    port map(
      clk         => clk_125mhz,
      rst         => rst,
      pay_in      => t_payload,
      pay_valid   => t_payload_valid,
      wr_req      => log_wr_req,
      wr_sector   => log_wr_sector,
      wr_data     => log_wr_data,
      wr_data_idx => log_wr_idx,
      wr_busy     => sd_wr_busy,
      sd_ready    => sd_init_done
    );

end architecture rtl;