-- =====================================================================
--  File: rtl/temp_spi_logger.vhd (extended with SPI/SD logging)
--  Role: Buffer 10-byte payloads into 512-byte SD sectors
--
--  Author: Md Shahriar Dipto
--  Mat.Nr.: 5227587
--  Faculty: 4
--  Institution: Hochschule Bremen
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity temp_spi_logger is
  generic(
    G_PAY_BYTES : integer := 10   -- length of payload in bytes
  );
  port(
    clk       : in  std_logic;
    rst       : in  std_logic;

    -- from temp_payload_gen
    pay_in    : in  std_logic_vector(G_PAY_BYTES*8-1 downto 0);
    pay_valid : in  std_logic;

    -- to SD controller
    wr_req    : out std_logic;                    -- strobe
    wr_sector : out std_logic_vector(31 downto 0);
    wr_data   : out std_logic_vector(7 downto 0); -- byte stream
    wr_data_idx : out std_logic_vector(8 downto 0); -- 0..511

    wr_busy   : in  std_logic;                    -- from SD ctrl
    sd_ready  : in  std_logic
  );
end entity temp_spi_logger;

architecture rtl of temp_spi_logger is

  type mem_t is array (0 to 511) of std_logic_vector(7 downto 0);
  signal buf       : mem_t := (others => (others => '0'));

  signal buf_idx   : integer range 0 to 511 := 0;
  signal rec_cnt   : unsigned(15 downto 0) := (others => '0');

  signal sector_cnt: unsigned(31 downto 0) := (others => '0');

  type st_t is (S_IDLE, S_FILL, S_REQ, S_WAIT_WR);
  signal st        : st_t := S_IDLE;

  signal wr_req_i  : std_logic := '0';
  signal wr_idx_i  : std_logic_vector(8 downto 0) := (others => '0');
  signal wr_data_i : std_logic_vector(7 downto 0) := (others => '0');

begin
  wr_req      <= wr_req_i;
  wr_sector   <= std_logic_vector(sector_cnt);
  wr_data     <= wr_data_i;
  wr_data_idx <= wr_idx_i;

  process(clk)
    variable i : integer;
  begin
    if rising_edge(clk) then
      wr_req_i <= '0';

      if rst = '1' then
        st         <= S_IDLE;
        buf_idx    <= 0;
        rec_cnt    <= (others => '0');
        sector_cnt <= (others => '0');

      else
        case st is

          when S_IDLE =>
            if sd_ready = '1' then
              st <= S_FILL;
            end if;

          when S_FILL =>
            -- accept payloads and pack into buffer
            if pay_valid = '1' then
              -- record layout: [0..1]=sample counter, [2..11]=payload (10 bytes)
              if buf_idx <= 500 then  -- keep room
                -- write sample counter (big-endian)
                buf(buf_idx)     <= std_logic_vector(rec_cnt(15 downto 8));
                buf(buf_idx+1)   <= std_logic_vector(rec_cnt(7 downto 0));

                -- write payload bytes 0..9
                for j in 0 to G_PAY_BYTES-1 loop
                  buf(buf_idx+2+j) <= pay_in(j*8+7 downto j*8);
                end loop;

                buf_idx  <= buf_idx + 2 + G_PAY_BYTES;
                rec_cnt  <= rec_cnt + 1;
              end if;

              -- if near end of sector or exactly full -> trigger write
              if buf_idx >= 512 - (2+G_PAY_BYTES) then
                st <= S_REQ;
              end if;
            end if;

          when S_REQ =>
            if wr_busy = '0' then
              wr_req_i <= '1';
              -- present bytes via wr_data/wr_data_idx
              wr_idx_i <= (others => '0');
              st       <= S_WAIT_WR;
            end if;

          when S_WAIT_WR =>
            -- while SD controller is writing, we must present each byte
            if wr_busy = '1' then
              -- SD controller will sample wr_data according to wr_data_idx
              wr_data_i <= buf(to_integer(unsigned(wr_idx_i)));
              if wr_idx_i /= std_logic_vector(to_unsigned(511,9)) then
                wr_idx_i <= std_logic_vector(unsigned(wr_idx_i)+1);
              end if;
            else
              -- done
              sector_cnt <= sector_cnt + 1;
              buf_idx    <= 0;
              st         <= S_FILL;
            end if;

        end case;
      end if;
    end if;
  end process;

end architecture rtl;
