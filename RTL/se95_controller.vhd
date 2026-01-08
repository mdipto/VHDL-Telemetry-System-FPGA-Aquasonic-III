-- =====================================================================
--  File: HDL/se95_controller.vhd
--  Author: Md Shahriar Dipto
--  Mat.Nr.: 5227587
--  Faculty: 4
--  Institution: Hochschule Bremen
--
--  Description:
--    I2C master finite-state machine that talks to an NXP SE95
--    temperature sensor (7-bit address 0x4F = "1001111").
--
--    The controller:
--      1) Waits a short time after reset (POWER_UP)
--      2) Sends START + Address+Write
--      3) Sends register pointer 0x00 (temperature register)
--      4) Sends a repeated START + Address+Read
--      5) Reads two bytes (MSB, LSB)
--      6) Generates STOP
--      7) Outputs the 16-bit raw value on temp_data and asserts
--         temp_valid for one clock cycle.
--
--    The I2C timing is generated from the system clock using
--    "i2c_tick" which represents one quarter of an SCL period.
--    Each I2C bit is divided into 4 sub-steps controlled by "seq".
--
-- =====================================================================

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- =========================
-- Entity Declaration
-- =========================
entity se95_controller is
  generic (
    CLK_HZ   : integer := 125_000_000;  -- system clock frequency
    I2C_FREQ : integer := 100_000       -- desired I2C SCL frequency
  );
  port (
    clk        : in  std_logic;                          -- system clock
    rst        : in  std_logic;                          -- synchronous reset (active '1')
    sda        : inout std_logic;                        -- I2C SDA line (open drain)
    scl        : inout std_logic;                        -- I2C SCL line (open drain)
    temp_data  : out std_logic_vector(15 downto 0);      -- raw SE95 register value
    temp_valid : out std_logic;                          -- 1-cycle strobe when temp_data updated
    error_led  : out std_logic                           -- latched when NACK during address phases
  );
end entity se95_controller;

-- =========================
-- Architecture
-- =========================
architecture rtl of se95_controller is

  -------------------------------------------------------------------
  --  State machine encoding for the I2C protocol
  -------------------------------------------------------------------
  type state_t is (
    POWER_UP, START,
    ADDR_W, ADDR_W_ACK,
    REG_PTR, REG_PTR_ACK,
    RESTART,
    ADDR_R, ADDR_R_ACK,
    READ_MSB, M_ACK_MSB,
    READ_LSB, M_NACK_LSB,
    STOP, WAIT_TIMER
  );

  signal state : state_t := POWER_UP;

  -------------------------------------------------------------------
  --  I2C bit timing
  --
  --  One full SCL period is divided into 4 "ticks":
  --     seq = 0 : SCL high, drive/release SDA
  --     seq = 1 : SCL goes low
  --     seq = 2 : hold SCL low
  --     seq = 3 : SCL goes high again
  --
  --  i2c_tick pulses '1' once every DIVIDER clock cycles. On each
  --  pulse the FSM advances "seq" and possibly the state.
  -------------------------------------------------------------------
  constant DIVIDER : integer := CLK_HZ / (4 * I2C_FREQ); -- clocks per quarter SCL period
  signal timer     : integer range 0 to DIVIDER := 0;
  signal i2c_tick  : std_logic := '0';

  -------------------------------------------------------------------
  --
  --  Open-drain control of SDA and SCL
  --  scl_enable = '1'  -> drive SCL low
  --  scl_enable = '0'  -> release SCL (external pull-up pulls it high)
  --
  --  sda_enable = '1'  -> drive SDA low
  --  sda_enable = '0'  -> release SDA (external pull-up pulls it high)
  -------------------------------------------------------------------
  signal scl_enable : std_logic := '0';
  signal sda_enable : std_logic := '0';

  -- SDA input as a clean '0'/'1' (to_X01 converts 'Z'/'H' to '1')
  signal sda_in : std_logic := '0';

  -------------------------------------------------------------------
  --  Byte-level registers
  -------------------------------------------------------------------
  signal bit_cnt   : integer range 0 to 7 := 7;          -- bit counter inside current byte
  signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');  -- tx/rx shift register
  signal msb_store : std_logic_vector(7 downto 0) := (others => '0');  -- received MSB
  signal lsb_store : std_logic_vector(7 downto 0) := (others => '0');  -- received LSB

  -- Wait timer between measurement cycles (used in WAIT_TIMER)
  signal wait_timer_cnt : integer := 0;

  -- 7-bit SE95 address (A2..A0 = 1 -> 0x4F)
  constant ADDR_VAL : std_logic_vector(6 downto 0) := "1001111";

  -- Internal latched error flag (NACK during address phases)
  signal error_flag : std_logic := '0';

begin

  -------------------------------------------------------------------
  --  Open-drain wiring of external I2C pins
  -------------------------------------------------------------------
  scl <= '0' when scl_enable = '1' else 'Z';
  sda <= '0' when sda_enable = '1' else 'Z';
  sda_in <= to_X01(sda);          -- resolve wired-AND to a single '0'/'1'

  -- Drive the error LED with the internal flag
  error_led <= error_flag;

  -------------------------------------------------------------------
  --  I2C tick generator: produces i2c_tick = '1' once every DIVIDER
  --  system clock cycles. This is the "time base" for the I2C FSM.
  -------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      i2c_tick <= '0';            -- default: no tick

      if rst = '1' then
        timer <= 0;

      elsif timer = DIVIDER - 1 then
        -- reached quarter period -> generate tick and restart counter
        timer    <= 0;
        i2c_tick <= '1';

      else
        -- keep counting system clocks
        timer <= timer + 1;
      end if;
    end if;
  end process;

  -------------------------------------------------------------------
  --  Main I2C Master FSM
  --
  --  Uses a local variable "seq" (0..3) to sub-divide each bit in
  --  four steps, implemented every i2c_tick.
  -------------------------------------------------------------------
  process(clk)
    variable seq : integer range 0 to 3 := 0;  -- quarter-SCL phase
  begin
    if rising_edge(clk) then

      -- default: temp_valid is a 1-cycle strobe
      temp_valid <= '0';

      if rst = '1' then
        ----------------------------------------------------------------
        -- Asynchronous reset of the controller
        ----------------------------------------------------------------
        state          <= POWER_UP;
        scl_enable     <= '0';
        sda_enable     <= '0';
        wait_timer_cnt <= 0;
        error_flag     <= '0';
        seq            := 0;

      elsif i2c_tick = '1' then
        ----------------------------------------------------------------
        -- Advance the FSM only on each I2C tick (quarter SCL period)
        ----------------------------------------------------------------
        case state is

          --------------------------------------------------------------
          -- 1. POWER_UP: short initial delay after reset
          --------------------------------------------------------------
          when POWER_UP =>
            if wait_timer_cnt >= 40000 then     -- ~ 100 ms
              state          <= START;       -- go generate START
              wait_timer_cnt <= 0;
            else
              wait_timer_cnt <= wait_timer_cnt + 1;
            end if;
            seq := 0;                        -- restart SCL sub-sequence

          --------------------------------------------------------------
          -- 2. START: generate I2C START condition
          --    START = SDA falling while SCL is high
          --------------------------------------------------------------
          when START =>
            case seq is
              when 0 =>
                -- Release both lines high (pull-ups)
                scl_enable <= '0';           -- SCL = HIGH
                sda_enable <= '0';           -- SDA = HIGH
                seq        := 1;

              when 1 =>
                -- Pull SDA low while SCL still high -> START edge
                scl_enable <= '0';           -- SCL still HIGH
                sda_enable <= '1';           -- SDA -> LOW
                seq        := 2;

              when 2 =>
                -- Hold START condition for one more tick
                scl_enable <= '0';           -- SCL HIGH
                sda_enable <= '1';           -- SDA LOW
                seq        := 3;

              when others =>
                -- Now pull SCL low and start sending Address+Write byte
                scl_enable <= '1';           -- SCL -> LOW
                sda_enable <= '1';           -- SDA carries MSB bit
                state      <= ADDR_W;
                bit_cnt    <= 7;             -- start with MSB
                shift_reg  <= ADDR_VAL & '0'; -- 7-bit address + W=0
                seq        := 0;
            end case;

          --------------------------------------------------------------
          -- 3. ADDR_W: transmit Address + Write bit (0)
          --------------------------------------------------------------
          when ADDR_W =>
            case seq is
              when 0 =>
                -- Place current bit on SDA while SCL low
                scl_enable <= '1';           -- SCL LOW
                if shift_reg(7) = '0' then   -- MSB of shift_reg
                  sda_enable <= '1';         -- drive 0
                else
                  sda_enable <= '0';         -- release -> 1
                end if;
                seq := 1;

              when 1 =>
                -- Raise SCL to clock the bit into the slave
                scl_enable <= '0';           -- SCL HIGH
                seq        := 2;

              when 2 =>
                -- Hold SCL high
                scl_enable <= '0';           -- still HIGH
                seq        := 3;

              when others =>
                -- Lower SCL and shift to next bit
                scl_enable <= '1';           -- SCL LOW
                shift_reg  <= shift_reg(6 downto 0) & '0'; -- shift left

                if bit_cnt = 0 then
                  -- All 8 bits have been sent -> go to ACK phase
                  state <= ADDR_W_ACK;
                else
                  bit_cnt <= bit_cnt - 1;
                end if;
                seq := 0;
            end case;

          --------------------------------------------------------------
          -- 4. ADDR_W_ACK: read ACK/NACK from slave after address+W
          --------------------------------------------------------------
          when ADDR_W_ACK =>
            case seq is
              when 0 =>
                sda_enable <= '0';           -- release SDA (input)
                scl_enable <= '1';           -- SCL LOW
                seq        := 1;

              when 1 =>
                scl_enable <= '0';           -- SCL HIGH (sample ACK)
                seq        := 2;

              when 2 =>
                scl_enable <= '0';           -- SCL HIGH (hold)
                -- If SDA is high, slave NACKed address -> set error
                if sda_in = '1' then
                  error_flag <= '1';
                  state      <= STOP;        -- abort transaction
                end if;
                seq := 3;

              when others =>
                scl_enable <= '1';           -- SCL LOW again
                if error_flag = '0' then
                  -- No error: proceed to send register pointer 0x00
                  state     <= REG_PTR;
                  shift_reg <= x"00";        -- temperature register
                  bit_cnt   <= 7;
                end if;
                seq := 0;
            end case;

          --------------------------------------------------------------
          -- 5. REG_PTR: send register pointer (0x00)
          --------------------------------------------------------------
          when REG_PTR =>
            case seq is
              when 0 =>
                scl_enable <= '1';           -- SCL LOW
                if shift_reg(7) = '0' then
                  sda_enable <= '1';         -- drive 0
                else
                  sda_enable <= '0';         -- release -> 1
                end if;
                seq := 1;

              when 1 =>
                scl_enable <= '0';           -- SCL HIGH
                seq        := 2;

              when 2 =>
                scl_enable <= '0';           -- hold HIGH
                seq        := 3;

              when others =>
                scl_enable <= '1';           -- SCL LOW
                shift_reg  <= shift_reg(6 downto 0) & '0';
                if bit_cnt = 0 then
                  state <= REG_PTR_ACK;      -- go to ACK phase
                else
                  bit_cnt <= bit_cnt - 1;
                end if;
                seq := 0;
            end case;

          --------------------------------------------------------------
          -- 6. REG_PTR_ACK: ignore ACK content, just finish the byte
          --------------------------------------------------------------
          when REG_PTR_ACK =>
            case seq is
              when 0 =>
                sda_enable <= '0';           -- release SDA
                scl_enable <= '1';           -- SCL LOW
                seq        := 1;

              when 1 =>
                scl_enable <= '0';           -- SCL HIGH
                seq        := 2;

              when 2 =>
                scl_enable <= '0';           -- hold HIGH
                seq        := 3;

              when others =>
                -- prepare for repeated START
                scl_enable <= '1';           -- SCL LOW
                state      <= RESTART;
                seq        := 0;
            end case;

          --------------------------------------------------------------
          -- 7. RESTART: generate repeated START condition
          --------------------------------------------------------------
          when RESTART =>
            case seq is
              when 0 =>
                -- Bus idle: SCL high, SDA high
                scl_enable <= '0';           -- SCL HIGH (released)
                sda_enable <= '0';           -- SDA HIGH (released)
                seq        := 1;

              when 1 =>
                -- SDA low while SCL high -> repeated START
                scl_enable <= '0';           -- SCL HIGH
                sda_enable <= '1';           -- SDA LOW
                seq        := 2;

              when 2 =>
                -- Hold START for one more tick
                scl_enable <= '0';           -- SCL HIGH
                sda_enable <= '1';           -- SDA LOW
                seq        := 3;

              when others =>
                -- Pull SCL low and prepare Address+Read
                scl_enable <= '1';           -- SCL LOW
                sda_enable <= '1';           -- SDA carries MSB
                state      <= ADDR_R;
                shift_reg  <= ADDR_VAL & '1'; -- 7-bit address + R=1
                bit_cnt    <= 7;
                seq        := 0;
            end case;

          --------------------------------------------------------------
          -- 8. ADDR_R: send Address + Read bit (1)
          --------------------------------------------------------------
          when ADDR_R =>
            case seq is
              when 0 =>
                scl_enable <= '1';           -- SCL LOW
                if shift_reg(7) = '0' then
                  sda_enable <= '1';
                else
                  sda_enable <= '0';
                end if;
                seq := 1;

              when 1 =>
                scl_enable <= '0';           -- SCL HIGH
                seq        := 2;

              when 2 =>
                scl_enable <= '0';           -- hold HIGH
                seq        := 3;

              when others =>
                scl_enable <= '1';           -- SCL LOW
                shift_reg  <= shift_reg(6 downto 0) & '0';
                if bit_cnt = 0 then
                  state <= ADDR_R_ACK;       -- ACK from slave
                else
                  bit_cnt <= bit_cnt - 1;
                end if;
                seq := 0;
            end case;

          --------------------------------------------------------------
          -- 9. ADDR_R_ACK: read ACK/NACK after address+R
          --------------------------------------------------------------
          when ADDR_R_ACK =>
            case seq is
              when 0 =>
                sda_enable <= '0';           -- release SDA
                scl_enable <= '1';           -- SCL LOW
                seq        := 1;

              when 1 =>
                scl_enable <= '0';           -- SCL HIGH
                seq        := 2;

              when 2 =>
                scl_enable <= '0';           -- hold HIGH
                if sda_in = '1' then         -- NACK -> error
                  error_flag <= '1';
                  state      <= STOP;
                end if;
                seq := 3;

              when others =>
                scl_enable <= '1';           -- SCL LOW
                if error_flag = '0' then
                  -- proceed to read MSB
                  state   <= READ_MSB;
                  bit_cnt <= 7;
                end if;
                seq := 0;
            end case;

          --------------------------------------------------------------
          -- 10. READ_MSB: read first (MSB) byte from SE95
          --------------------------------------------------------------
          when READ_MSB =>
            case seq is
              when 0 =>
                sda_enable <= '0';           -- release SDA (input)
                scl_enable <= '1';           -- SCL LOW
                seq        := 1;

              when 1 =>
                scl_enable <= '0';           -- SCL HIGH -> sample
                seq        := 2;

              when 2 =>
                scl_enable <= '0';           -- hold HIGH
                -- sample SDA into shift_reg(bit_cnt)
                shift_reg(bit_cnt) <= sda_in;
                seq                 := 3;

              when others =>
                scl_enable <= '1';           -- SCL LOW
                if bit_cnt = 0 then
                  msb_store <= shift_reg;    -- store received MSB
                  state     <= M_ACK_MSB;    -- master ACKs it
                else
                  bit_cnt <= bit_cnt - 1;
                end if;
                seq := 0;
            end case;

          --------------------------------------------------------------
          -- 11. M_ACK_MSB: master sends ACK after MSB
          --------------------------------------------------------------
          when M_ACK_MSB =>
            msb_store <= shift_reg;          -- (safety: keep MSB)
            case seq is
              when 0 =>
                sda_enable <= '1';           -- drive SDA low (ACK)
                scl_enable <= '1';           -- SCL LOW
                seq        := 1;

              when 1 =>
                scl_enable <= '0';           -- SCL HIGH
                seq        := 2;

              when 2 =>
                scl_enable <= '0';           -- hold HIGH
                seq        := 3;

              when others =>
                scl_enable <= '1';           -- SCL LOW
                state      <= READ_LSB;      -- next: read LSB
                bit_cnt    <= 7;
                seq        := 0;
            end case;

          --------------------------------------------------------------
          -- 12. READ_LSB: read second (LSB) byte from SE95
          --------------------------------------------------------------
          when READ_LSB =>
            case seq is
              when 0 =>
                sda_enable <= '0';           -- release SDA
                scl_enable <= '1';           -- SCL LOW
                seq        := 1;

              when 1 =>
                scl_enable <= '0';           -- SCL HIGH
                seq        := 2;

              when 2 =>
                scl_enable <= '0';           -- hold HIGH
                shift_reg(bit_cnt) <= sda_in;
                seq                 := 3;

              when others =>
                scl_enable <= '1';           -- SCL LOW
                if bit_cnt = 0 then
                  -- finished byte -> go to master NACK
                  state <= M_NACK_LSB;
                else
                  bit_cnt <= bit_cnt - 1;
                end if;
                seq := 0;
            end case;

          --------------------------------------------------------------
          -- 13. M_NACK_LSB: master NACKs last byte (LSB)
          --------------------------------------------------------------
          when M_NACK_LSB =>
            lsb_store <= shift_reg;          -- store received LSB
            case seq is
              when 0 =>
                sda_enable <= '0';           -- release SDA -> NACK (HIGH)
                scl_enable <= '1';           -- SCL LOW
                seq        := 1;

              when 1 =>
                scl_enable <= '0';           -- SCL HIGH
                seq        := 2;

              when 2 =>
                scl_enable <= '0';           -- hold HIGH
                seq        := 3;

              when others =>
                scl_enable <= '1';           -- SCL LOW
                state      <= STOP;          -- proceed to STOP
                seq        := 0;
            end case;

          --------------------------------------------------------------
          -- 14. STOP: generate STOP condition and latch data
          --------------------------------------------------------------
          when STOP =>
            case seq is
              when 0 =>
                -- SCL and SDA low
                sda_enable <= '1';           -- SDA LOW
                scl_enable <= '1';           -- SCL LOW
                seq        := 1;

              when 1 =>
                -- Raise SCL first
                sda_enable <= '1';           -- SDA LOW
                scl_enable <= '0';           -- SCL HIGH
                seq        := 2;

              when 2 =>
                -- Release SDA while SCL is high -> STOP edge
                sda_enable <= '0';           -- SDA HIGH (released)
                scl_enable <= '0';           -- SCL HIGH
                seq        := 3;

              when others =>
                -- Transaction finished: present data to outside world
                temp_data  <= msb_store & lsb_store;
                temp_valid <= '1';           -- 1-cycle strobe
                error_flag <= '0';
                state      <= WAIT_TIMER; -- delay before next read
                wait_timer_cnt <= 0;
                seq            := 0;
            end case;

          --------------------------------------------------------------
          -- 15. WAIT_TIMER: delay between measurement cycles
          --     In HW: 100 ms at 125 MHz (40000 clocks).
          --------------------------------------------------------------
          when WAIT_TIMER =>
            if wait_timer_cnt >= 40000 then
              state          <= START;      -- trigger next conversion
              wait_timer_cnt <= 0;
            else
              wait_timer_cnt <= wait_timer_cnt + 1;
            end if;
            seq := 0;

          -- Safety net (should never be used)
          when others =>
            null;
        end case; -- state
      end if; -- i2c_tick
    end if;   -- rising_edge(clk)
  end process;

end architecture rtl;
