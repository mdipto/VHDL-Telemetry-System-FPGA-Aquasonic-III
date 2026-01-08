-- =====================================================================
-- Testbench: tb_spi_logger_sd
-- Purpose  : Exercise temp_spi_logger + sd_spi_controller
--            using a simple byte-level SD-card SPI model.
--
-- DUTs     :
--   - temp_spi_logger   (collects 10-byte payloads into 512-byte sectors)
--   - sd_spi_controller (initialises SD card and issues CMD24 writes)
--
-- NOTE:
--   This testbench **does not** instantiate spi_master.
--   Instead, it models the SPI bus at the byte level using the
--   spi_start/spi_tx/spi_rx/spi_busy/spi_done handshake.
--
--   For the thesis:
--     • Use this TB to show correct sector-buffering + SD protocol.
--     • Use a separate simple TB for spi_master (loopback) to show
--       correct SCLK/MOSI/MISO timing.
--
--  Author: Md Shahriar Dipto
--  Mat.Nr.: 5227587
--  Faculty: 4
--  Institution: Hochschule Bremen
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_spi_logger_sd is
end entity tb_spi_logger_sd;

architecture sim of tb_spi_logger_sd is

  constant C_CLK_HZ    : integer := 125_000_000;
  constant C_PAY_BYTES : integer := 10;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal pay_in    : std_logic_vector(C_PAY_BYTES*8-1 downto 0) := (others => '0');
  signal pay_valid : std_logic := '0';

  signal wr_req      : std_logic;
  signal wr_sector   : std_logic_vector(31 downto 0);
  signal wr_data     : std_logic_vector(7 downto 0);
  signal wr_data_idx : std_logic_vector(8 downto 0);
  signal wr_busy     : std_logic;
  signal sd_ready    : std_logic;

  signal spi_start  : std_logic;
  signal spi_tx     : std_logic_vector(7 downto 0);
  signal spi_rx     : std_logic_vector(7 downto 0) := x"FF";
  signal spi_busy   : std_logic := '0';
  signal spi_done   : std_logic := '0';

  signal init_done  : std_logic;
  signal error_flag : std_logic;

begin

  clk <= not clk after 4 ns;

  U_LOG : entity work.temp_spi_logger
    generic map(
      G_PAY_BYTES => C_PAY_BYTES
    )
    port map(
      clk         => clk,
      rst         => rst,
      pay_in      => pay_in,
      pay_valid   => pay_valid,
      wr_req      => wr_req,
      wr_sector   => wr_sector,
      wr_data     => wr_data,
      wr_data_idx => wr_data_idx,
      wr_busy     => wr_busy,
      sd_ready    => sd_ready
    );

  U_SD : entity work.sd_spi_controller
    port map(
      clk         => clk,
      rst         => rst,
      spi_start   => spi_start,
      spi_tx      => spi_tx,
      spi_rx      => spi_rx,
      spi_busy    => spi_busy,
      spi_done    => spi_done,
      wr_req      => wr_req,
      wr_busy     => wr_busy,
      wr_sector   => wr_sector,
      wr_data     => wr_data,
      wr_data_idx => wr_data_idx,
      init_done   => init_done,
      error_flag  => error_flag
    );

  sd_ready <= init_done and not error_flag;

  -- byte-level SD model
  sd_model : process(clk)
    type cmd_t is (NONE, CMD0, CMD8, CMD55, ACMD41, CMD58, CMD16, CMD24);
    variable cur_cmd        : cmd_t := NONE;
    variable in_data_block  : boolean := false;
    variable sent_data_resp : boolean := false;
    variable busy_phase     : integer := 0;
    variable data_count     : integer := 0;
  begin
    if rising_edge(clk) then
      spi_done <= '0';

      if rst = '1' then
        spi_busy       <= '0';
        spi_rx         <= x"FF";
        cur_cmd        := NONE;
        in_data_block  := false;
        sent_data_resp := false;
        busy_phase     := 0;
        data_count     := 0;

      else
        if spi_start = '1' then
          spi_busy <= '1';
          spi_rx   <= x"FF";

          case spi_tx is
            when x"40" => cur_cmd := CMD0;  spi_rx <= x"FF";
            when x"48" => cur_cmd := CMD8;  spi_rx <= x"FF";
            when x"77" => cur_cmd := CMD55; spi_rx <= x"01";
            when x"69" => cur_cmd := ACMD41;spi_rx <= x"FF";
            when x"7A" => cur_cmd := CMD58; spi_rx <= x"FF";
            when x"50" => cur_cmd := CMD16; spi_rx <= x"FF";
            when x"58" =>
              cur_cmd        := CMD24;
              in_data_block  := false;
              sent_data_resp := false;
              busy_phase     := 0;
              spi_rx         <= x"FF";

            when x"FE" =>
              in_data_block := true;
              data_count    := 0;
              spi_rx        <= x"FF";

            when x"FF" =>
              case cur_cmd is
                when CMD0   => spi_rx <= x"01"; cur_cmd := NONE;
                when CMD8   => spi_rx <= x"01"; cur_cmd := NONE;
                when ACMD41 => spi_rx <= x"00"; cur_cmd := NONE;
                when CMD58  => spi_rx <= x"00"; cur_cmd := NONE;
                when CMD16  => spi_rx <= x"00"; cur_cmd := NONE;
                when CMD24  =>
                  if in_data_block and (data_count > 512+1) and not sent_data_resp then
                    spi_rx         <= x"05";
                    sent_data_resp := true;
                    busy_phase     := 0;
                  elsif sent_data_resp and busy_phase < 2 then
                    spi_rx     <= x"00";
                    busy_phase := busy_phase + 1;
                  else
                    spi_rx        <= x"FF";
                    cur_cmd       := NONE;
                    in_data_block := false;
                  end if;
                when others =>
                  spi_rx <= x"FF";
              end case;

            when others =>
              if in_data_block then
                data_count := data_count + 1;
              end if;
              spi_rx <= x"FF";
          end case;

          spi_done <= '1';
          spi_busy <= '0';

          report "SPI TX=" &
                 integer'image(to_integer(unsigned(spi_tx))) &
                 " RX=" &
                 integer'image(to_integer(unsigned(spi_rx)));

        end if;
      end if;
    end if;
  end process sd_model;

  -- payload stimulus
  stim : process
    variable sample : integer := 0;
    variable p      : std_logic_vector(C_PAY_BYTES*8-1 downto 0);
  begin
    wait for 200 ns;
    rst <= '0';
    wait for 200 us;

    for i in 0 to 45 loop
      p := (others => '0');
      p(7 downto 0)    := x"54";
      p(15 downto 8)   := x"19";
      p(23 downto 16)  := x"00";
      p(31 downto 24)  := "0000000" & '0';

      pay_in    <= p;
      pay_valid <= '1';
      wait until rising_edge(clk);
      pay_valid <= '0';

      sample := sample + 1;
      wait for 50 us;
    end loop;

    wait for 2 ms;
    report "Simulation finished" severity failure;
  end process stim;

end architecture sim;


