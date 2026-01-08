-- =====================================================================
-- File: se95_slave_model.vhd
-- Desc: Behavioural (non-synthesizable) I²C slave model for NXP SE95.
--       Simulates the SE95 temperature register response for testbench.
--
--       This model:
--       • Detects I²C START + STOP conditions
--       • Responds to its 7-bit address + R/W
--       • Accepts register pointer writes
--       • Returns fixed temperature 25.000 °C = 0x1900
--       • Uses open-drain I²C (slave only drives SDA low)
--
-- Author : Md Shahriar Dipto
-- Mat.Nr.: 5227587
-- Faculty: 4
-- Institution: Hochschule Bremen
-- =====================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity se95_slave_model is
  generic (
    G_ADDR : std_logic_vector(6 downto 0) := "1001111"  -- SE95 default address
  );
  port (
    sda : inout std_logic;  -- I²C SDA line
    scl : inout std_logic   -- I²C SCL line (always driven by master)
  );
end entity se95_slave_model;

architecture sim of se95_slave_model is

  --------------------------------------------------------------------
  -- Fixed temperature value output by this SE95 model:
  -- SE95 resolution: 0.03125 °C per LSB → 25.000°C = 25 / 0.03125 = 800
  -- 800 decimal = 0x0320 → shifted left 3 bits → 0x1900
  --------------------------------------------------------------------
  constant C_TEMP : std_logic_vector(15 downto 0) := x"1900";
  constant C_MSB  : std_logic_vector(7 downto 0)  := C_TEMP(15 downto 8);
  constant C_LSB  : std_logic_vector(7 downto 0)  := C_TEMP(7 downto 0);

  --------------------------------------------------------------------
  -- Open-drain behavioural driver
  --------------------------------------------------------------------
  signal sda_drv : std_logic := 'Z';  -- '0' = pull SDA low, 'Z' = release
  signal sda_in  : std_logic;         -- resolved input ('0' or '1')
  signal scl_in  : std_logic;         -- resolved input ('0' or '1')

begin

  --------------------------------------------------------------------
  -- Slave SDA driving: only LOW or HIGH-Z (never drives a '1')
  --------------------------------------------------------------------
  sda <= '0' when sda_drv = '0' else 'Z';

  --------------------------------------------------------------------
  -- Slave NEVER drives SCL → leave it floating
  --------------------------------------------------------------------
  scl <= 'Z';

  --------------------------------------------------------------------
  -- Convert any ('H','L','Z','U') into clean '0'/'1'
  --------------------------------------------------------------------
  sda_in <= to_x01(sda);
  scl_in <= to_x01(scl);

  --------------------------------------------------------------------
  -- Main behavioural I²C slave process
  -- This loop runs forever, serving repeated SE95 transactions.
  --------------------------------------------------------------------
  se95_behaviour : process
    variable addr_byte  : std_logic_vector(7 downto 0);
    variable ptr_byte   : std_logic_vector(7 downto 0);
    variable rw_bit     : std_logic;
    variable i          : integer;
    variable addr_match : boolean;
  begin
    sda_drv <= 'Z';   -- release SDA initially

    ------------------------------------------------------------------
    -- MAIN LOOP
    -- Wait for START → Decode address → Read/Write pointer →
    -- Respond to read → Wait for STOP → Repeat
    ------------------------------------------------------------------
    loop

      ----------------------------------------------------------------
      -- 1) Detect START: SDA goes 1→0 while SCL = 1
      ----------------------------------------------------------------
      wait until (sda_in'event and sda_in = '0' and scl_in = '1');

      ----------------------------------------------------------------
      -- 2) Read Address + W bit (8 bits)
      ----------------------------------------------------------------
      addr_byte := (others => '0');
      for i in 7 downto 0 loop
        wait until scl_in'event and scl_in = '1';   -- rising edge
        addr_byte(i) := sda_in;                     -- read SDA bit
      end loop;

      -- Extract R/W bit and compare address
      rw_bit     := addr_byte(0);
      addr_match :=
          (addr_byte(7 downto 1) = G_ADDR) and  -- correct device?
          (rw_bit = '0');                       -- must be WRITE

      -- ACK only if matched
      if addr_match then
        sda_drv <= '0';     -- ACK
      else
        sda_drv <= 'Z';     -- NACK / ignore
      end if;

      -- Clock ACK cycle
      wait until scl_in'event and scl_in = '1';
      wait until scl_in'event and scl_in = '0';
      sda_drv <= 'Z';

      ----------------------------------------------------------------
      -- 3) Receive Register Pointer Byte (ignored)
      ----------------------------------------------------------------
      ptr_byte := (others => '0');
      for i in 7 downto 0 loop
        wait until scl_in'event and scl_in = '1';
        ptr_byte(i) := sda_in;
      end loop;

      -- ACK pointer if we belong to this transaction
      if addr_match then
        sda_drv <= '0';
      else
        sda_drv <= 'Z';
      end if;

      wait until scl_in'event and scl_in = '1';
      wait until scl_in'event and scl_in = '0';
      sda_drv <= 'Z';

      ----------------------------------------------------------------
      -- 4) Wait for repeated START → Address + R
      ----------------------------------------------------------------
      if addr_match then

        -- Look for a START condition again
        wait until (sda_in'event and sda_in = '0' and scl_in = '1');

        -- Read address + R
        addr_byte := (others => '0');
        for i in 7 downto 0 loop
          wait until scl_in'event and scl_in = '1';
          addr_byte(i) := sda_in;
        end loop;

        -- Decode read request
        rw_bit     := addr_byte(0);
        addr_match :=
            (addr_byte(7 downto 1) = G_ADDR) and
            (rw_bit = '1');      -- must be READ

        -- ACK if OK
        if addr_match then
          sda_drv <= '0';
        else
          sda_drv <= 'Z';
        end if;

        wait until scl_in'event and scl_in = '1';
        wait until scl_in'event and scl_in = '0';
        sda_drv <= 'Z';
      end if;

      ----------------------------------------------------------------
      -- 5) If addressed → Transmit MSB and LSB of temperature register
      ----------------------------------------------------------------
      if addr_match then

        --------------------------------------------------------------
        -- Send MSB  (Bit 7 first)
        --------------------------------------------------------------
        for i in 7 downto 0 loop
          -- Drive while SCL low
          if C_MSB(i) = '0' then sda_drv <= '0';
          else                    sda_drv <= 'Z';
          end if;

          wait until scl_in'event and scl_in = '1';  -- master samples
          wait until scl_in'event and scl_in = '0';
        end loop;

        -- Master ACKs MSB (SDA low)
        sda_drv <= 'Z';   -- release
        wait until scl_in'event and scl_in = '1';
        wait until scl_in'event and scl_in = '0';

        --------------------------------------------------------------
        -- Send LSB
        --------------------------------------------------------------
        for i in 7 downto 0 loop
          if C_LSB(i) = '0' then sda_drv <= '0';
          else                    sda_drv <= 'Z';
          end if;

          wait until scl_in'event and scl_in = '1';
          wait until scl_in'event and scl_in = '0';
        end loop;

        -- Master NACKs LSB
        sda_drv <= 'Z';
        wait until scl_in'event and scl_in = '1';
        wait until scl_in'event and scl_in = '0';

      end if;

      ----------------------------------------------------------------
      -- 6) Wait for STOP → SDA goes 0→1 while SCL=1
      ----------------------------------------------------------------
      wait until (sda_in'event and sda_in = '1' and scl_in = '1');

      -- Now the entire SE95 read cycle is complete, loop again
    end loop;

  end process se95_behaviour;

end architecture sim;
