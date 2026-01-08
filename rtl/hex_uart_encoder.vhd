A.7 uart_tx.vhd — Simple UART Transmitter . . . . . . . . . . . . . . . . 28
A.8 spi_master.vhd — Mode-0 SPI Master (byte-wide) . . . . . . . . . . . 31
A.9 sd_spi_controller.vhd — SD Card Init & Single-Block Write (CMD24) 34
A.10 temp_spi_logger.vhd — Buffering 10-Byte Payloads into 512-Byte SD
Sectors . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 41
B Constrain/XDC file for SE95 sensor 45
B.1 pynq_z2_se95.xdc — PYNQ-Z2 constraints for SE95 sensor . . . . . . 45
C Top-level design for PYNQ-Z2 board 47
C.1 Top-Level: top_pynq_se95.vhd . . . . . . . . . . . . . . . . . . . . . . 47
D Testbench design for PYNQ-Z2 board 52
D.1 Testbench Pull-Up Model ( ) . . . . . . . . . . . . . . . . . . 52
pullup.vhd
D.2 Full-System Testbench ( tb_top_pynq_se95.vhd ) . . . . . . . . . . . . . 53
D.3 SE95 I2C Slave Model ( se95_slave_model.vhd ) . . . . . . . . . . . . . 55
D.4 AX.25 Framing Testbench ( tb_ax25_temp.vhd ) . . . . . . . . . . . . . . 59
D.5 SPI Logger + SD Controller Testbench
( tb_spi_logger_sd.vhd ) . . . . . . . . . . . . . . . . . . . . . . . . . . 61
D.6 SPI Master Loopback Testbench
( tb_spi_master_loopback.vhd ) . . . . . . . . . . . . . . . . . . . . . . 65
1
Listings
A.1 se95_controller.vhd : I2C master FSM for NXP SE95 (address 0x4F) 4
A.2 temp_payload_gen.vhd : Build a 10-byte telemetry payload from SE95
data (bytes: , raw MSB, raw LSB, flags, and reserved). . . . . . . . . 15
’T’
A.3 bin_to_bcd.vhd : Unsigned binary to BCD conversion using the Double-
Dabble (shift-add-3) algorithm with start/busy/valid handshake. . . . . . 17
A.4 ax25 ramer.vhd : AX.25UIframebuilder . . . . . . . . . . . . . . . . . . 20
f
A.5 crc16_x25.vhd : Byte-wise CRC-16/X.25 (poly 0x8408 reflected, init
0xFFFF, output XOR 0xFFFF), LSB-first per byte for AX.25. . . . . . . 24
A.6 hex_uart_encoder.vhd : Converts each incoming byte to two ASCII hex
nibbles plus a separating space, with back-pressure via fr_busy to the
framer and uart_busy handshake to the UART. . . . . . . . . . . . . . 25
A.7 uart_tx.vhd : 8N1 UART transmitter with parameterizable clock and
baud. Uses a small FSM (IDLE, START, DATA, STOP) and a clock
divider to generate bit timing. . . . . . . . . . . . . . . . . . . . . . . . . 28
A.8 spi_master.vhd : simple mode-0 SPI master with byte-wide transfers and
parameterizable SCLK ( G_SPI_HZ ). . . . . . . . . . . . . . . . . . . . . . 31
A.9 sd_spi_controller.vhd : minimalSD-cardSPI-modeinitialization(CMD0,
CMD8, CMD55/ACMD41, CMD58, CMD16) and single-block write via
CMD24 with data token . . . . . . . . . . . . . . . . . . . . . . . . . 34
0xFE
A.10 temp_spi_logger.vhd : buffers 10-byte telemetry payloads (2B counter
+ 10B data) into a 512B sector and requests a single-block write via the
SD SPI controller. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 41
B.1 pynq_z2_se95.xdc : PYNQ-Z2 constraints for SE95 sensor. . . . . . . . 45
C.1 top_pynq_se95.vhd — PYNQ-Z2 top-level with I2C, AX.25+UART, and
SPI/SD logging . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 47
D.1
pullup.vhd
— behavioural pull-up for I2C/open-drain lines in simulation 52
D.2 Testbench tb_top_pynq_se95 : full-system simulation (SE95 I2C, AX.25,
UART, SPI/SD). . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 53
D.3 BehaviouralI2CslavemodelfortheSE95sensorusedinsimulation. Returns
a fixed temperature of 25.000◦C (0x1900). . . . . . . . . . . . . . . . . . 55
D.4 Testbench tb_ax25_temp generatinga125MHzclock,pulsing temp_valid ,
and driving the AX.25 framer path. . . . . . . . . . . . . . . . . . . . . . 59
D.5 Testbench . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 61
D.6 tb_spi_master_loopback : verifies spi_master timing by looping MOSI
back to MISO (Mode 0). . . . . . . . . . . . . . . . . . . . . . . . . . . . 65
2
Chapter 1
VHDL Codes
Here is attached all the VHDL codes for Implementation of a VHDL-Based Telemetry
System for Data Acquisition for the Aquasonic-III Sounding Rocket.
3
Appendix A
VHDL Source Codes
A.1 se95 _ controller.vhd — SE95 I2C Master
-- =====================================================================
-- File: HDL/se95_controller.vhd
-- Author: Md Shahriar Dipto
-- Mat.Nr.: 5227587
-- Faculty: 4
-- Institution: Hochschule Bremen
--
-- Description:
-- I2C master finite-state machine that talks to an NXP SE95
-- temperature sensor (7-bit address 0x4F = "1001111").
--
-- The controller:
-- 1) Waits a short time after reset (POWER_UP)
-- 2) Sends START + Address+Write
-- 3) Sends register pointer 0x00 (temperature register)
-- 4) Sends a repeated START + Address+Read
-- 5) Reads two bytes (MSB, LSB)
-- 6) Generates STOP
-- 7) Outputs the 16-bit raw value on temp_data and asserts
-- temp_valid for one clock cycle.
--
-- The I2C timing is generated from the system clock using
-- "i2c_tick" which represents one quarter of an SCL period.
-- Each I2C bit is divided into 4 sub-steps controlled by "seq".
--
-- =====================================================================
27
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
31
-- =========================
-- Entity Declaration
-- =========================
entity se95_controller is
generic (
CLK_HZ : integer := 125_000_000; -- system clock frequency
I2C_FREQ : integer := 100_000 -- desired I2C SCL frequency
);
4
port (
clk : in std_logic; -- system clock
rst : in std_logic; -- synchronous reset
(active ’1’)
sda : inout std_logic; -- I2C SDA line (open
drain)
scl : inout std_logic; -- I2C SCL line (open
drain)
temp_data : out std_logic_vector(15 downto 0); -- raw SE95 register value
temp_valid : out std_logic; -- 1-cycle strobe when
temp_data updated
error_led : out std_logic -- latched when NACK
during address phases
);
end entity se95_controller;
50
-- =========================
-- Architecture
-- =========================
architecture rtl of se95_controller is
55
-------------------------------------------------------------------
-- State machine encoding for the I2C protocol
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
69
signal state : state_t := POWER_UP;
71
-------------------------------------------------------------------
-- I2C bit timing
--
-- One full SCL period is divided into 4 "ticks":
-- seq = 0 : SCL high, drive/release SDA
-- seq = 1 : SCL goes low
-- seq = 2 : hold SCL low
-- seq = 3 : SCL goes high again
--
-- i2c_tick pulses ’1’ once every DIVIDER clock cycles. On each
-- pulse the FSM advances "seq" and possibly the state.
-------------------------------------------------------------------
constant DIVIDER : integer := CLK_HZ / (4 * I2C_FREQ); -- clocks per quarter SCL
period
signal timer : integer range 0 to DIVIDER := 0;
signal i2c_tick : std_logic := ’0’;
87
-------------------------------------------------------------------
--
-- Open-drain control of SDA and SCL
-- scl_enable = ’1’ -> drive SCL low
5
-- scl_enable = ’0’ -> release SCL (external pull-up pulls it high)
--
-- sda_enable = ’1’ -> drive SDA low
-- sda_enable = ’0’ -> release SDA (external pull-up pulls it high)
-------------------------------------------------------------------
signal scl_enable : std_logic := ’0’;
signal sda_enable : std_logic := ’0’;
99
-- SDA input as a clean ’0’/’1’ (to_X01 converts ’Z’/’H’ to ’1’)
signal sda_in : std_logic := ’0’;
102
-------------------------------------------------------------------
-- Byte-level registers
-------------------------------------------------------------------
signal bit_cnt : integer range 0 to 7 := 7; -- bit counter inside
current byte
signal shift_reg : std_logic_vector(7 downto 0) := (others => ’0’); -- tx/rx
shift register
signal msb_store : std_logic_vector(7 downto 0) := (others => ’0’); -- received
MSB
signal lsb_store : std_logic_vector(7 downto 0) := (others => ’0’); -- received
LSB
110
-- Wait timer between measurement cycles (used in WAIT_TIMER)
signal wait_timer_cnt : integer := 0;
113
-- 7-bit SE95 address (A2..A0 = 1 -> 0x4F)
constant ADDR_VAL : std_logic_vector(6 downto 0) := "1001111";
116
-- Internal latched error flag (NACK during address phases)
signal error_flag : std_logic := ’0’;
119
begin
121
-------------------------------------------------------------------
-- Open-drain wiring of external I2C pins
-------------------------------------------------------------------
scl <= ’0’ when scl_enable = ’1’ else ’Z’;
sda <= ’0’ when sda_enable = ’1’ else ’Z’;
sda_in <= to_X01(sda); -- resolve wired-AND to a single ’0’/’1’
128
-- Drive the error LED with the internal flag
error_led <= error_flag;
131
-------------------------------------------------------------------
-- I2C tick generator: produces i2c_tick = ’1’ once every DIVIDER
-- system clock cycles. This is the "time base" for the I2C FSM.
-------------------------------------------------------------------
process(clk)
begin
if rising_edge(clk) then
i2c_tick <= ’0’; -- default: no tick
140
if rst = ’1’ then
timer <= 0;
143
elsif timer = DIVIDER - 1 then
-- reached quarter period -> generate tick and restart counter
6
timer <= 0;
i2c_tick <= ’1’;
148
else
-- keep counting system clocks
timer <= timer + 1;
end if;
end if;
end process;
155
-------------------------------------------------------------------
-- Main I2C Master FSM
--
-- Uses a local variable "seq" (0..3) to sub-divide each bit in
-- four steps, implemented every i2c_tick.
-------------------------------------------------------------------
process(clk)
variable seq : integer range 0 to 3 := 0; -- quarter-SCL phase
begin
if rising_edge(clk) then
166
-- default: temp_valid is a 1-cycle strobe
temp_valid <= ’0’;
169
if rst = ’1’ then
----------------------------------------------------------------
-- Asynchronous reset of the controller
----------------------------------------------------------------
state <= POWER_UP;
scl_enable <= ’0’;
sda_enable <= ’0’;
wait_timer_cnt <= 0;
error_flag <= ’0’;
seq := 0;
180
elsif i2c_tick = ’1’ then
----------------------------------------------------------------
-- Advance the FSM only on each I2C tick (quarter SCL period)
----------------------------------------------------------------
case state is
186
--------------------------------------------------------------
-- 1. POWER_UP: short initial delay after reset
--------------------------------------------------------------
when POWER_UP =>
if wait_timer_cnt >= 40000 then -- ~ 100 ms
state <= START; -- go generate START
wait_timer_cnt <= 0;
else
wait_timer_cnt <= wait_timer_cnt + 1;
end if;
seq := 0; -- restart SCL sub-sequence
198
--------------------------------------------------------------
-- 2. START: generate I2C START condition
-- START = SDA falling while SCL is high
--------------------------------------------------------------
when START =>
7
case seq is
when 0 =>
-- Release both lines high (pull-ups)
scl_enable <= ’0’; -- SCL = HIGH
sda_enable <= ’0’; -- SDA = HIGH
seq := 1;
210
when 1 =>
-- Pull SDA low while SCL still high -> START edge
scl_enable <= ’0’; -- SCL still HIGH
sda_enable <= ’1’; -- SDA -> LOW
seq := 2;
216
when 2 =>
-- Hold START condition for one more tick
scl_enable <= ’0’; -- SCL HIGH
sda_enable <= ’1’; -- SDA LOW
seq := 3;
222
when others =>
-- Now pull SCL low and start sending Address+Write byte
scl_enable <= ’1’; -- SCL -> LOW
sda_enable <= ’1’; -- SDA carries MSB bit
state <= ADDR_W;
bit_cnt <= 7; -- start with MSB
shift_reg <= ADDR_VAL & ’0’; -- 7-bit address + W=0
seq := 0;
end case;
232
--------------------------------------------------------------
-- 3. ADDR_W: transmit Address + Write bit (0)
--------------------------------------------------------------
when ADDR_W =>
case seq is
when 0 =>
-- Place current bit on SDA while SCL low
scl_enable <= ’1’; -- SCL LOW
if shift_reg(7) = ’0’ then -- MSB of shift_reg
sda_enable <= ’1’; -- drive 0
else
sda_enable <= ’0’; -- release -> 1
end if;
seq := 1;
247
when 1 =>
-- Raise SCL to clock the bit into the slave
scl_enable <= ’0’; -- SCL HIGH
seq := 2;
252
when 2 =>
-- Hold SCL high
scl_enable <= ’0’; -- still HIGH
seq := 3;
257
when others =>
-- Lower SCL and shift to next bit
scl_enable <= ’1’; -- SCL LOW
shift_reg <= shift_reg(6 downto 0) & ’0’; -- shift left
8
262
if bit_cnt = 0 then
-- All 8 bits have been sent -> go to ACK phase
state <= ADDR_W_ACK;
else
bit_cnt <= bit_cnt - 1;
end if;
seq := 0;
end case;
271
--------------------------------------------------------------
-- 4. ADDR_W_ACK: read ACK/NACK from slave after address+W
--------------------------------------------------------------
when ADDR_W_ACK =>
case seq is
when 0 =>
sda_enable <= ’0’; -- release SDA (input)
scl_enable <= ’1’; -- SCL LOW
seq := 1;
281
when 1 =>
scl_enable <= ’0’; -- SCL HIGH (sample ACK)
seq := 2;
285
when 2 =>
scl_enable <= ’0’; -- SCL HIGH (hold)
-- If SDA is high, slave NACKed address -> set error
if sda_in = ’1’ then
error_flag <= ’1’;
state <= STOP; -- abort transaction
end if;
seq := 3;
294
when others =>
scl_enable <= ’1’; -- SCL LOW again
if error_flag = ’0’ then
-- No error: proceed to send register pointer 0x00
state <= REG_PTR;
shift_reg <= x"00"; -- temperature register
bit_cnt <= 7;
end if;
seq := 0;
end case;
305
--------------------------------------------------------------
-- 5. REG_PTR: send register pointer (0x00)
--------------------------------------------------------------
when REG_PTR =>
case seq is
when 0 =>
scl_enable <= ’1’; -- SCL LOW
if shift_reg(7) = ’0’ then
sda_enable <= ’1’; -- drive 0
else
sda_enable <= ’0’; -- release -> 1
end if;
seq := 1;
319
9
when 1 =>
scl_enable <= ’0’; -- SCL HIGH
seq := 2;
323
when 2 =>
scl_enable <= ’0’; -- hold HIGH
seq := 3;
327
when others =>
scl_enable <= ’1’; -- SCL LOW
shift_reg <= shift_reg(6 downto 0) & ’0’;
if bit_cnt = 0 then
state <= REG_PTR_ACK; -- go to ACK phase
else
bit_cnt <= bit_cnt - 1;
end if;
seq := 0;
end case;
338
--------------------------------------------------------------
-- 6. REG_PTR_ACK: ignore ACK content, just finish the byte
--------------------------------------------------------------
when REG_PTR_ACK =>
case seq is
when 0 =>
sda_enable <= ’0’; -- release SDA
scl_enable <= ’1’; -- SCL LOW
seq := 1;
348
when 1 =>
scl_enable <= ’0’; -- SCL HIGH
seq := 2;
352
when 2 =>
scl_enable <= ’0’; -- hold HIGH
seq := 3;
356
when others =>
-- prepare for repeated START
scl_enable <= ’1’; -- SCL LOW
state <= RESTART;
seq := 0;
end case;
363
--------------------------------------------------------------
-- 7. RESTART: generate repeated START condition
--------------------------------------------------------------
when RESTART =>
case seq is
when 0 =>
-- Bus idle: SCL high, SDA high
scl_enable <= ’0’; -- SCL HIGH (released)
sda_enable <= ’0’; -- SDA HIGH (released)
seq := 1;
374
when 1 =>
-- SDA low while SCL high -> repeated START
scl_enable <= ’0’; -- SCL HIGH
10
sda_enable <= ’1’; -- SDA LOW
seq := 2;
380
when 2 =>
-- Hold START for one more tick
scl_enable <= ’0’; -- SCL HIGH
sda_enable <= ’1’; -- SDA LOW
seq := 3;
386
when others =>
-- Pull SCL low and prepare Address+Read
scl_enable <= ’1’; -- SCL LOW
sda_enable <= ’1’; -- SDA carries MSB
state <= ADDR_R;
shift_reg <= ADDR_VAL & ’1’; -- 7-bit address + R=1
bit_cnt <= 7;
seq := 0;
end case;
396
--------------------------------------------------------------
-- 8. ADDR_R: send Address + Read bit (1)
--------------------------------------------------------------
when ADDR_R =>
case seq is
when 0 =>
scl_enable <= ’1’; -- SCL LOW
if shift_reg(7) = ’0’ then
sda_enable <= ’1’;
else
sda_enable <= ’0’;
end if;
seq := 1;
410
when 1 =>
scl_enable <= ’0’; -- SCL HIGH
seq := 2;
414
when 2 =>
scl_enable <= ’0’; -- hold HIGH
seq := 3;
418
when others =>
scl_enable <= ’1’; -- SCL LOW
shift_reg <= shift_reg(6 downto 0) & ’0’;
if bit_cnt = 0 then
state <= ADDR_R_ACK; -- ACK from slave
else
bit_cnt <= bit_cnt - 1;
end if;
seq := 0;
end case;
429
--------------------------------------------------------------
-- 9. ADDR_R_ACK: read ACK/NACK after address+R
--------------------------------------------------------------
when ADDR_R_ACK =>
case seq is
when 0 =>
11
sda_enable <= ’0’; -- release SDA
scl_enable <= ’1’; -- SCL LOW
seq := 1;
439
when 1 =>
scl_enable <= ’0’; -- SCL HIGH
seq := 2;
443
when 2 =>
scl_enable <= ’0’; -- hold HIGH
if sda_in = ’1’ then -- NACK -> error
error_flag <= ’1’;
state <= STOP;
end if;
seq := 3;
451
when others =>
scl_enable <= ’1’; -- SCL LOW
if error_flag = ’0’ then
-- proceed to read MSB
state <= READ_MSB;
bit_cnt <= 7;
end if;
seq := 0;
end case;
461
--------------------------------------------------------------
-- 10. READ_MSB: read first (MSB) byte from SE95
--------------------------------------------------------------
when READ_MSB =>
case seq is
when 0 =>
sda_enable <= ’0’; -- release SDA (input)
scl_enable <= ’1’; -- SCL LOW
seq := 1;
471
when 1 =>
scl_enable <= ’0’; -- SCL HIGH -> sample
seq := 2;
475
when 2 =>
scl_enable <= ’0’; -- hold HIGH
-- sample SDA into shift_reg(bit_cnt)
shift_reg(bit_cnt) <= sda_in;
seq := 3;
481
when others =>
scl_enable <= ’1’; -- SCL LOW
if bit_cnt = 0 then
msb_store <= shift_reg; -- store received MSB
state <= M_ACK_MSB; -- master ACKs it
else
bit_cnt <= bit_cnt - 1;
end if;
seq := 0;
end case;
492
--------------------------------------------------------------
12
-- 11. M_ACK_MSB: master sends ACK after MSB
--------------------------------------------------------------
when M_ACK_MSB =>
msb_store <= shift_reg; -- (safety: keep MSB)
case seq is
when 0 =>
sda_enable <= ’1’; -- drive SDA low (ACK)
scl_enable <= ’1’; -- SCL LOW
seq := 1;
503
when 1 =>
scl_enable <= ’0’; -- SCL HIGH
seq := 2;
507
when 2 =>
scl_enable <= ’0’; -- hold HIGH
seq := 3;
511
when others =>
scl_enable <= ’1’; -- SCL LOW
state <= READ_LSB; -- next: read LSB
bit_cnt <= 7;
seq := 0;
end case;
518
--------------------------------------------------------------
-- 12. READ_LSB: read second (LSB) byte from SE95
--------------------------------------------------------------
when READ_LSB =>
case seq is
when 0 =>
sda_enable <= ’0’; -- release SDA
scl_enable <= ’1’; -- SCL LOW
seq := 1;
528
when 1 =>
scl_enable <= ’0’; -- SCL HIGH
seq := 2;
532
when 2 =>
scl_enable <= ’0’; -- hold HIGH
shift_reg(bit_cnt) <= sda_in;
seq := 3;
537
when others =>
scl_enable <= ’1’; -- SCL LOW
if bit_cnt = 0 then
-- finished byte -> go to master NACK
state <= M_NACK_LSB;
else
bit_cnt <= bit_cnt - 1;
end if;
seq := 0;
end case;
548
--------------------------------------------------------------
-- 13. M_NACK_LSB: master NACKs last byte (LSB)
--------------------------------------------------------------
13
when M_NACK_LSB =>
lsb_store <= shift_reg; -- store received LSB
case seq is
when 0 =>
sda_enable <= ’0’; -- release SDA -> NACK (HIGH)
scl_enable <= ’1’; -- SCL LOW
seq := 1;
559
when 1 =>
scl_enable <= ’0’; -- SCL HIGH
seq := 2;
563
when 2 =>
scl_enable <= ’0’; -- hold HIGH
seq := 3;
567
when others =>
scl_enable <= ’1’; -- SCL LOW
state <= STOP; -- proceed to STOP
seq := 0;
end case;
573
--------------------------------------------------------------
-- 14. STOP: generate STOP condition and latch data
--------------------------------------------------------------
when STOP =>
case seq is
when 0 =>
-- SCL and SDA low
sda_enable <= ’1’; -- SDA LOW
scl_enable <= ’1’; -- SCL LOW
seq := 1;
584
when 1 =>
-- Raise SCL first
sda_enable <= ’1’; -- SDA LOW
scl_enable <= ’0’; -- SCL HIGH
seq := 2;
590
when 2 =>
-- Release SDA while SCL is high -> STOP edge
sda_enable <= ’0’; -- SDA HIGH (released)
scl_enable <= ’0’; -- SCL HIGH
seq := 3;
596
when others =>
-- Transaction finished: present data to outside world
temp_data <= msb_store & lsb_store;
temp_valid <= ’1’; -- 1-cycle strobe
error_flag <= ’0’;
state <= WAIT_TIMER; -- delay before next read
wait_timer_cnt <= 0;
seq := 0;
end case;
606
--------------------------------------------------------------
-- 15. WAIT_TIMER: delay between measurement cycles
-- In HW: 100 ms at 125 MHz (40000 clocks).
14
--------------------------------------------------------------
when WAIT_TIMER =>
if wait_timer_cnt >= 40000 then
state <= START; -- trigger next conversion
wait_timer_cnt <= 0;
else
wait_timer_cnt <= wait_timer_cnt + 1;
end if;
seq := 0;
619
-- Safety net (should never be used)
when others =>
null;
end case; -- state
end if; -- i2c_tick
end if; -- rising_edge(clk)
end process;
627
end architecture rtl;
