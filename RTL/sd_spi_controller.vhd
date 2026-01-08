-- =====================================================================
--  File: HDL/sd_spi_controller.vhd (extended with SPI/SD logging)
--  Role: Minimal SD-card SPI-mode init + single-block write (CMD24)
--
--  Author: Md Shahriar Dipto
--  Mat.Nr.: 5227587
--  Faculty: 4
--  Institution: Hochschule Bremen
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sd_spi_controller is
  port(
    clk        : in  std_logic;
    rst        : in  std_logic;

    -- interface to spi_master (byte-wise)
    spi_start  : out std_logic;
    spi_tx     : out std_logic_vector(7 downto 0);
    spi_rx     : in  std_logic_vector(7 downto 0);
    spi_busy   : in  std_logic;
    spi_done   : in  std_logic;

    -- write-sector interface (from logger)
    wr_req     : in  std_logic;               -- strobe: write this sector
    wr_busy    : out std_logic;               -- '1' while write in progress
    wr_sector  : in  std_logic_vector(31 downto 0); -- logical sector #
    wr_data    : in  std_logic_vector(7 downto 0);  -- current data byte
    wr_data_idx: in  std_logic_vector(8 downto 0);  -- 0..511 index

    init_done  : out std_logic;
    error_flag : out std_logic
  );
end entity sd_spi_controller;

architecture rtl of sd_spi_controller is

  -- SD command tokens (CMD index ORed with 0x40)
  constant CMD0  : std_logic_vector(7 downto 0) := x"40";
  constant CMD8  : std_logic_vector(7 downto 0) := x"48";
  constant CMD55 : std_logic_vector(7 downto 0) := x"77";
  constant ACMD41: std_logic_vector(7 downto 0) := x"69";
  constant CMD58 : std_logic_vector(7 downto 0) := x"7A";
  constant CMD16 : std_logic_vector(7 downto 0) := x"50";
  constant CMD24 : std_logic_vector(7 downto 0) := x"58";

  type st_t is (
    S_RESET,
    S_IDLE_CLK,
    S_CMD0, S_WAIT_R1_0,
    S_CMD8, S_WAIT_R7,
    S_CMD55, S_ACMD41, S_WAIT_ACMD41,
    S_CMD58, S_WAIT_R3,
    S_CMD16, S_WAIT_R1_16,
    S_READY,

    -- write states
    S_WR_WAIT_REQ,
    S_WR_CMD24, S_WR_WAIT_R1,
    S_WR_SEND_TOKEN,
    S_WR_DATA,
    S_WR_SEND_CRC,
    S_WR_WAIT_DATA_RESP,
    S_WR_WAIT_BUSY,
    S_WR_DONE
  );

  signal st        : st_t := S_RESET;
  signal next_st   : st_t := S_RESET;

  signal spi_start_i : std_logic := '0';
  signal spi_tx_i    : std_logic_vector(7 downto 0) := (others => '1');

  signal init_done_i : std_logic := '0';
  signal err_i       : std_logic := '0';

  signal wr_busy_i   : std_logic := '0';

  signal byte_cnt    : integer range 0 to 520 := 0;
  signal idle_cnt    : integer range 0 to 100 := 0;

  signal sector_l    : std_logic_vector(31 downto 0) := (others => '0');
  signal wr_req_l    : std_logic := '0';

begin
  spi_start  <= spi_start_i;
  spi_tx     <= spi_tx_i;
  init_done  <= init_done_i;
  error_flag <= err_i;
  wr_busy    <= wr_busy_i;

  process(clk)
  begin
    if rising_edge(clk) then
      spi_start_i <= '0';  -- default

      if rst = '1' then
        st          <= S_RESET;
        init_done_i <= '0';
        err_i       <= '0';
        idle_cnt    <= 0;
        wr_busy_i   <= '0';
        wr_req_l    <= '0';
      else

        wr_req_l <= wr_req;   -- simple edge capture

        case st is

          --------------------------------------------------------------
          -- After power-up: send >74 dummy clocks with CS high
          --------------------------------------------------------------
          when S_RESET =>
            init_done_i <= '0';
            err_i       <= '0';
            wr_busy_i   <= '0';
            idle_cnt    <= 0;
            -- send 0xFF as many times as needed with CS high (outside)
            if spi_busy = '0' then
              spi_tx_i   <= x"FF";
              spi_start_i <= '1';
              idle_cnt   <= idle_cnt + 1;
              if idle_cnt = 15 then  -- 16 bytes * 8 bits = 128 clocks
                st <= S_CMD0;
              end if;
            end if;

          --------------------------------------------------------------
          -- CMD0: GO_IDLE_STATE
          --------------------------------------------------------------
          when S_CMD0 =>
            if spi_busy = '0' then
              -- send CMD0 argument and CRC (0x95)
              spi_tx_i    <= CMD0;
              spi_start_i <= '1';
              byte_cnt    <= 0;
              st          <= S_WAIT_R1_0;
            end if;

          when S_WAIT_R1_0 =>
            if spi_done = '1' then
              case byte_cnt is
                when 0 =>
                  spi_tx_i    <= x"00"; spi_start_i <= '1'; byte_cnt <= 1;
                when 1 =>
                  spi_tx_i    <= x"00"; spi_start_i <= '1'; byte_cnt <= 2;
                when 2 =>
                  spi_tx_i    <= x"00"; spi_start_i <= '1'; byte_cnt <= 3;
                when 3 =>
                  spi_tx_i    <= x"00"; spi_start_i <= '1'; byte_cnt <= 4;
                when 4 =>
                  spi_tx_i    <= x"95"; spi_start_i <= '1'; byte_cnt <= 5;
                when others =>
                  -- now poll for R1 with 0xFF
                  spi_tx_i    <= x"FF"; spi_start_i <= '1';
                  if spi_rx(0) = '1' then
                    -- expect 0x01 (in idle)
                    st <= S_CMD8;
                  end if;
              end case;
            end if;

          --------------------------------------------------------------
          -- CMD8: SEND_IF_COND (check voltage range)
          --------------------------------------------------------------
          when S_CMD8 =>
            if spi_busy = '0' then
              spi_tx_i    <= CMD8;
              spi_start_i <= '1';
              byte_cnt    <= 0;
              st          <= S_WAIT_R7;
            end if;

          when S_WAIT_R7 =>
            if spi_done = '1' then
              case byte_cnt is
                when 0 =>
                  spi_tx_i <= x"00"; spi_start_i<='1'; byte_cnt<=1;
                when 1 =>
                  spi_tx_i <= x"00"; spi_start_i<='1'; byte_cnt<=2;
                when 2 =>
                  spi_tx_i <= x"01"; spi_start_i<='1'; byte_cnt<=3; -- VHS=0, check pattern=0xAA
                when 3 =>
                  spi_tx_i <= x"AA"; spi_start_i<='1'; byte_cnt<=4;
                when 4 =>
                  spi_tx_i <= x"87"; spi_start_i<='1'; byte_cnt<=5; -- CRC
                when others =>
                  spi_tx_i <= x"FF"; spi_start_i<='1';
                  -- ignore full R7 content; only check not 0xFF
                  if spi_rx /= x"FF" then
                    st <= S_CMD55;
                  end if;
              end case;
            end if;

          --------------------------------------------------------------
          -- ACMD41 loop (via CMD55)
          --------------------------------------------------------------
          when S_CMD55 =>
            if spi_busy = '0' then
              spi_tx_i    <= CMD55;
              spi_start_i <= '1';
              byte_cnt    <= 0;
              st          <= S_ACMD41;
            end if;

          when S_ACMD41 =>
            if spi_done = '1' then
              case byte_cnt is
                when 0 =>
                  spi_tx_i<=x"00"; spi_start_i<='1'; byte_cnt<=1;
                when 1 =>
                  spi_tx_i<=x"00"; spi_start_i<='1'; byte_cnt<=2;
                when 2 =>
                  spi_tx_i<=x"00"; spi_start_i<='1'; byte_cnt<=3;
                when 3 =>
                  spi_tx_i<=x"00"; spi_start_i<='1'; byte_cnt<=4;
                when 4 =>
                  spi_tx_i<=x"65"; spi_start_i<='1'; byte_cnt<=5; -- dummy CRC
                when others =>
                  -- now send ACMD41 = CMD55 prefix already done
                  spi_tx_i    <= ACMD41;
                  spi_start_i <= '1';
                  byte_cnt    <= 0;
                  st          <= S_WAIT_ACMD41;
              end case;
            end if;

          when S_WAIT_ACMD41 =>
            if spi_done = '1' then
              if byte_cnt < 5 then
                spi_tx_i    <= x"00"; spi_start_i<='1'; byte_cnt<=byte_cnt+1;
              else
                -- now poll R1 (0x00 when ready)
                spi_tx_i    <= x"FF"; spi_start_i<='1';
                if spi_rx = x"00" then
                  st <= S_CMD58;
                else
                  -- still idle; issue another CMD55/ACMD41
                  st <= S_CMD55;
                end if;
              end if;
            end if;

          --------------------------------------------------------------
          -- CMD58 (read OCR) + CMD16 (set block size 512)
          --------------------------------------------------------------
          when S_CMD58 =>
            if spi_busy = '0' then
              spi_tx_i    <= CMD58;
              spi_start_i <= '1';
              byte_cnt    <= 0;
              st          <= S_WAIT_R3;
            end if;

          when S_WAIT_R3 =>
            if spi_done = '1' then
              if byte_cnt < 5 then
                spi_tx_i    <= x"00"; spi_start_i<='1'; byte_cnt<=byte_cnt+1;
              else
                spi_tx_i    <= x"FF"; spi_start_i<='1';
                st          <= S_CMD16;
              end if;
            end if;

          when S_CMD16 =>
            if spi_busy = '0' then
              spi_tx_i    <= CMD16;
              spi_start_i <= '1';
              byte_cnt    <= 0;
              st          <= S_WAIT_R1_16;
            end if;

          when S_WAIT_R1_16 =>
            if spi_done = '1' then
              case byte_cnt is
                when 0 =>
                  spi_tx_i<=x"00"; spi_start_i<='1'; byte_cnt<=1;
                when 1 =>
                  spi_tx_i<=x"00"; spi_start_i<='1'; byte_cnt<=2;
                when 2 =>
                  spi_tx_i<=x"02"; spi_start_i<='1'; byte_cnt<=3; -- 512 bytes
                when 3 =>
                  spi_tx_i<=x"00"; spi_start_i<='1'; byte_cnt<=4;
                when 4 =>
                  spi_tx_i<=x"01"; spi_start_i<='1'; byte_cnt<=5; -- CRC (dummy ok)
                when others =>
                  spi_tx_i<=x"FF"; spi_start_i<='1';
                  if spi_rx = x"00" then
                    init_done_i <= '1';
                    st          <= S_WR_WAIT_REQ;
                  else
                    err_i       <= '1';
                    st          <= S_WR_WAIT_REQ;
                  end if;
              end case;
            end if;

          --------------------------------------------------------------
          -- Ready for write requests
          --------------------------------------------------------------
          when S_WR_WAIT_REQ =>
            wr_busy_i <= '0';
            if init_done_i = '1' and wr_req_l = '1' and err_i = '0' then
              sector_l  <= wr_sector;
              st        <= S_WR_CMD24;
              byte_cnt  <= 0;
            end if;

          --------------------------------------------------------------
          -- CMD24: WRITE_BLOCK
          --------------------------------------------------------------
          when S_WR_CMD24 =>
            wr_busy_i <= '1';
            if spi_busy = '0' then
              spi_tx_i    <= CMD24;
              spi_start_i <= '1';
              byte_cnt    <= 0;
              st          <= S_WR_WAIT_R1;
            end if;

          when S_WR_WAIT_R1 =>
            if spi_done = '1' then
              case byte_cnt is
                when 0 =>
                  spi_tx_i <= sector_l(31 downto 24); spi_start_i<='1'; byte_cnt<=1;
                when 1 =>
                  spi_tx_i <= sector_l(23 downto 16); spi_start_i<='1'; byte_cnt<=2;
                when 2 =>
                  spi_tx_i <= sector_l(15 downto 8);  spi_start_i<='1'; byte_cnt<=3;
                when 3 =>
                  spi_tx_i <= sector_l(7 downto 0);   spi_start_i<='1'; byte_cnt<=4;
                when 4 =>
                  spi_tx_i <= x"FF";                  spi_start_i<='1'; byte_cnt<=5; -- dummy CRC
                when others =>
                  spi_tx_i <= x"FF"; spi_start_i<='1';
                  if spi_rx = x"00" then
                    st       <= S_WR_SEND_TOKEN;
                  else
                    err_i    <= '1';
                    st       <= S_WR_DONE;
                  end if;
              end case;
            end if;

          --------------------------------------------------------------
          -- Data token + 512 bytes + dummy CRC
          --------------------------------------------------------------
          when S_WR_SEND_TOKEN =>
            if spi_busy = '0' then
              spi_tx_i    <= x"FE";  -- single-block token
              spi_start_i <= '1';
              byte_cnt    <= 0;
              st          <= S_WR_DATA;
            end if;

          when S_WR_DATA =>
            if spi_done = '1' then
              if byte_cnt < 512 then
                -- send data bytes; logger supplies wr_data at index
                spi_tx_i    <= wr_data;  -- assumes wr_data matches index
                spi_start_i <= '1';
                byte_cnt    <= byte_cnt + 1;
              else
                st <= S_WR_SEND_CRC;
              end if;
            end if;

          when S_WR_SEND_CRC =>
            if spi_busy = '0' then
              -- two dummy CRC bytes
              spi_tx_i    <= x"FF"; spi_start_i<='1';
              byte_cnt    <= 0;
              st          <= S_WR_WAIT_DATA_RESP;
            end if;

          when S_WR_WAIT_DATA_RESP =>
            if spi_done = '1' then
              if byte_cnt = 0 then
                spi_tx_i    <= x"FF"; spi_start_i<='1'; byte_cnt<=1;
              else
                -- check data response token (xxx0_101)
                if (spi_rx(4 downto 0) = "00101") then
                  st <= S_WR_WAIT_BUSY;
                else
                  err_i <= '1';
                  st    <= S_WR_DONE;
                end if;
              end if;
            end if;

          when S_WR_WAIT_BUSY =>
            -- card drives MISO low while busy; poll until 0xFF
            if spi_busy = '0' then
              spi_tx_i    <= x"FF"; spi_start_i<='1';
              if spi_done = '1' then
                if spi_rx = x"FF" then
                  st <= S_WR_DONE;
                end if;
              end if;
            end if;

          when S_WR_DONE =>
            wr_busy_i <= '0';
            st        <= S_WR_WAIT_REQ;
            
          when others =>
            st <= S_RESET;
            

        end case;
      end if;
    end if;
  end process;

end architecture rtl;
