-- =====================================================================
--  File: HDL/ax25_framer.vhd (extended with SPI/SD logging)
--  Role: AXI25 frame creation
--
--  Author: Md Shahriar Dipto
--  Mat.Nr.: 5227587
--  Faculty: 4
--  Institution: Hochschule Bremen
-- =====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ax25_framer is
  generic (
    G_MAX_PAYLOAD : integer := 32
  );
  port (
    clk           : in  std_logic;
    rst           : in  std_logic;

    -- from temp_payload_gen
    payload       : in  std_logic_vector(G_MAX_PAYLOAD*8-1 downto 0);
    payload_len   : in  std_logic_vector(7 downto 0);
    payload_valid : in  std_logic;

    -- to HEX encoder (NOT the real UART directly)
    uart_busy     : in  std_logic;                       -- busy from HEX encoder
    uart_send     : out std_logic;                       -- 1-cycle strobe
    uart_data     : out std_logic_vector(7 downto 0);    -- frame byte

    frame_active  : out std_logic
  );
end entity;

architecture rtl of ax25_framer is

  --------------------------------------------------------------------
  -- AX.25 constants
  --------------------------------------------------------------------
  constant C_FLAG      : std_logic_vector(7 downto 0) := x"7E";
  constant C_CTRL_UI   : std_logic_vector(7 downto 0) := x"03"; -- UI frame
  constant C_PID_NO_L3 : std_logic_vector(7 downto 0) := x"F0"; -- no layer 3

  --------------------------------------------------------------------
  -- AX.25 ADDRESS FIELDS
  -- Destination: "GROUND-0"
  -- Source     : "AQSNC3-0"
  --
  -- Each callsign character is ASCII << 1.
  -- SSID bytes:
  --   0x60 : SSID = 0, C = 0, last = 0 (more addresses follow)
  --   0x61 : SSID = 0, C = 0, last = 1 (last address in list)
  --------------------------------------------------------------------
  constant C_HDR_LEN : integer := 14;

  type byte_arr_t is array (0 to C_HDR_LEN-1) of std_logic_vector(7 downto 0);

  -- DEST "GROUND-0", SRC "AQSNC3-0"
  constant C_HEADER : byte_arr_t := (
    -- DEST "GROUND-0"
    0  => x"8E",  -- 'G' << 1
    1  => x"A4",  -- 'R' << 1
    2  => x"9E",  -- 'O' << 1
    3  => x"AA",  -- 'U' << 1
    4  => x"9C",  -- 'N' << 1
    5  => x"88",  -- 'D' << 1
    6  => x"60",  -- SSID 0, C=0, last=0

    -- SRC "AQSNC3-0"
    7  => x"82",  -- 'A' << 1
    8  => x"A2",  -- 'Q' << 1
    9  => x"A6",  -- 'S' << 1
    10 => x"9C",  -- 'N' << 1
    11 => x"86",  -- 'C' << 1
    12 => x"66",  -- '3' << 1
    13 => x"61"   -- SSID 0, C=0, last=1
  );

  --------------------------------------------------------------------
  -- Internal payload buffer
  --------------------------------------------------------------------
  type pay_arr_t is array (0 to G_MAX_PAYLOAD-1) of std_logic_vector(7 downto 0);
  signal pay_buf   : pay_arr_t := (others => (others => '0'));
  signal pay_len_i : integer range 0 to G_MAX_PAYLOAD := 0;

  --------------------------------------------------------------------
  -- CRC-16/X.25 instance wiring
  --------------------------------------------------------------------
  signal crc_data : std_logic_vector(7 downto 0) := (others => '0');
  signal crc_we   : std_logic := '0';
  signal crc_init : std_logic := '0';
  signal crc_val  : std_logic_vector(15 downto 0);

  --------------------------------------------------------------------
  -- FSM
  --------------------------------------------------------------------
  type st_t is (
    ST_IDLE,
    ST_FLAG1,
    ST_HDR,
    ST_CTRL,
    ST_PID,
    ST_INFO,
    ST_CRC1,
    ST_CRC2,
    ST_FLAG2
  );
  signal st : st_t := ST_IDLE;

  signal hdr_idx  : integer range 0 to C_HDR_LEN      := 0;
  signal info_idx : integer range 0 to G_MAX_PAYLOAD  := 0;

  signal s_send   : std_logic := '0';
  signal s_data   : std_logic_vector(7 downto 0) := (others => '0');
  signal s_active : std_logic := '0';

begin
  uart_send    <= s_send;
  uart_data    <= s_data;
  frame_active <= s_active;

  --------------------------------------------------------------------
  -- CRC instance
  --------------------------------------------------------------------
  U_CRC : entity work.crc16_x25
    port map(
      clk     => clk,
      rst     => rst,
      init    => crc_init,
      data_in => crc_data,
      data_we => crc_we,
      crc_out => crc_val
    );

  --------------------------------------------------------------------
  -- Main FSM
  --------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then

      s_send   <= '0';
      crc_we   <= '0';
      crc_init <= '0';

      if rst = '1' then
        st        <= ST_IDLE;
        s_active  <= '0';
        hdr_idx   <= 0;
        info_idx  <= 0;
        pay_len_i <= 0;

      else
        case st is

          when ST_IDLE =>
            s_active <= '0';
            if payload_valid = '1' then
              -- capture payload bytes into local buffer
              for i in 0 to G_MAX_PAYLOAD-1 loop
                pay_buf(i) <= payload(i*8+7 downto i*8);
              end loop;
              pay_len_i <= to_integer(unsigned(payload_len));
              hdr_idx   <= 0;
              info_idx  <= 0;
              crc_init  <= '1';          -- reset CRC LFSR
              st        <= ST_FLAG1;
            end if;

          when ST_FLAG1 =>
            s_active <= '1';
            if uart_busy = '0' then
              s_data <= C_FLAG;
              s_send <= '1';
              st     <= ST_HDR;
            end if;

          when ST_HDR =>
            if uart_busy = '0' then
              s_data   <= C_HEADER(hdr_idx);
              s_send   <= '1';
              crc_data <= C_HEADER(hdr_idx);
              crc_we   <= '1';

              if hdr_idx = C_HDR_LEN-1 then
                hdr_idx <= 0;
                st      <= ST_CTRL;
              else
                hdr_idx <= hdr_idx + 1;
              end if;
            end if;

          when ST_CTRL =>
            if uart_busy = '0' then
              s_data   <= C_CTRL_UI;
              s_send   <= '1';
              crc_data <= C_CTRL_UI;
              crc_we   <= '1';
              st       <= ST_PID;
            end if;

          when ST_PID =>
            if uart_busy = '0' then
              s_data   <= C_PID_NO_L3;
              s_send   <= '1';
              crc_data <= C_PID_NO_L3;
              crc_we   <= '1';
              st       <= ST_INFO;
            end if;

          when ST_INFO =>
            if info_idx >= pay_len_i then
              st <= ST_CRC1;
            else
              if uart_busy = '0' then
                s_data   <= pay_buf(info_idx);
                s_send   <= '1';
                crc_data <= pay_buf(info_idx);
                crc_we   <= '1';
                info_idx <= info_idx + 1;
              end if;
            end if;

          when ST_CRC1 =>
            if uart_busy = '0' then
              s_data <= crc_val(7 downto 0);   -- LSB first
              s_send <= '1';
              st     <= ST_CRC2;
            end if;

          when ST_CRC2 =>
            if uart_busy = '0' then
              s_data <= crc_val(15 downto 8);  -- MSB
              s_send <= '1';
              st     <= ST_FLAG2;
            end if;

          when ST_FLAG2 =>
            if uart_busy = '0' then
              s_data   <= C_FLAG;
              s_send   <= '1';
              s_active <= '0';
              st       <= ST_IDLE;
            end if;

        end case;
      end if;
    end if;
  end process;

end architecture rtl;
