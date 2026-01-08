library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ax25_temp is
end entity tb_ax25_temp;

architecture sim of tb_ax25_temp is

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';

  signal temp_raw   : std_logic_vector(15 downto 0) := x"1900"; -- 25°C raw
  signal temp_valid : std_logic := '0';
  signal i2c_error  : std_logic := '0';

  -- 10-byte payload
  signal payload       : std_logic_vector(10*8-1 downto 0);
  signal payload_valid : std_logic;
  signal payload_len   : std_logic_vector(7 downto 0);

  signal uart_busy : std_logic := '0';
  signal uart_send : std_logic;
  signal uart_data : std_logic_vector(7 downto 0);
  signal frame_act : std_logic;

begin

  -- 125 MHz clock (8 ns period)
  clk <= not clk after 4 ns;

  --------------------------------------------------------------------
  -- DUT: temp_payload_gen
  --------------------------------------------------------------------
  U_PAYLOAD: entity work.temp_payload_gen
    generic map(
      G_MAX_PAYLOAD => 10
    )
    port map(
      clk           => clk,
      rst           => rst,
      temp_raw      => temp_raw,
      valid         => temp_valid,
      i2c_error     => i2c_error,
      payload       => payload,
      payload_valid => payload_valid,
      payload_len   => payload_len
    );

  --------------------------------------------------------------------
  -- DUT: ax25_framer
  --------------------------------------------------------------------
  U_FRAMER: entity work.ax25_framer
    generic map(
      G_MAX_PAYLOAD => 10
    )
    port map(
      clk           => clk,
      rst           => rst,
      payload       => payload,
      payload_len   => payload_len,
      payload_valid => payload_valid,
      uart_busy     => uart_busy,
      uart_send     => uart_send,
      uart_data     => uart_data,
      frame_active  => frame_act
    );

  --------------------------------------------------------------------
  -- stimulus
  --------------------------------------------------------------------
  stim: process
  begin
    -- reset
    wait for 50 ns;
    rst <= '0';

    -- after some cycles, assert temp_valid once
    wait for 200 ns;
    temp_raw   <= x"1900";   -- 25 °C example
    i2c_error  <= '0';
    temp_valid <= '1';
    wait for 8 ns;           -- one clock
    temp_valid <= '0';

    -- later, send another sample with error flag set
    wait for 5 us;
    temp_raw   <= x"1A00";
    i2c_error  <= '1';
    temp_valid <= '1';
    wait for 8 ns;
    temp_valid <= '0';

    wait;
  end process;

end architecture sim;
