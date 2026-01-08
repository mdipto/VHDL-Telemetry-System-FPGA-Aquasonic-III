-- =====================================================================
-- File: sim/pullup.vhd
-- Desc: Simple behavioural pull-up model for XSIM / VHDL testbenches.
--       XSIM does NOT support the Verilog "pullup" primitive.
--       Therefore, we emulate a weak logic-'1' on an inout signal.
--
-- Author: Md Shahriar Dipto
-- Mat.Nr.: 5227587
-- Faculty: 4
-- Institution: Hochschule Bremen
-- =====================================================================

library IEEE;
use IEEE.std_logic_1164.all;

-- ---------------------------------------------------------------------
-- Entity: pullup
-- ---------------------------------------------------------------------
-- This module provides a *weak* pull-up on an inout std_logic signal.
-- Usage: instantiate it in the testbench:
--
--   PU_SDA : entity work.pullup port map(line => i2c_sda_w);
--
-- It ensures the line defaults HIGH when *no one* is driving it.
-- This is necessary because:
--   - I²C uses **open-drain** signalling: devices only pull LOW.
--   - A pull-up (external or modelled) is required so the bus returns to '1'.
--
-- In real hardware, resistors provide this pull-up.
-- In simulation, we emulate this with a weak driver.
-- ---------------------------------------------------------------------
entity pullup is
  port(line : inout std_logic);
end entity pullup;

architecture behave of pullup is
begin

  -----------------------------------------------------------------------
  -- Behavioural pull-up driver
  -- --------------------------------------------------------------------
  -- Drive the line with `'H'` which is a **weak logic high**.
  --
  -- In std_logic resolution:
  --   'H' combines with a '0' → resolves to '0'
  --   'H' combines with 'Z' → resolves to '1'
  --
  -- This correctly models I²C / open-drain behaviour:
  --   - If nothing drives the bus, it floats HIGH.
  --   - If any device pulls low, the bus resolves to LOW.
  --
  -- "after 0 ns" ensures the driver is created at time zero.
  -- If simply write "line <= 'H';", XSIM sometimes does not
  -- create the driver early enough, causing initial 'U' states.
  -----------------------------------------------------------------------
  line <= 'H' after 0 ns;

end architecture behave;
