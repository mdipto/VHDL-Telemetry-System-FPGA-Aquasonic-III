# =====================================================================
# PYNQ-Z2 constraints for:
#  - 125 MHz PL clock
#  - BTN0 reset
#  - I2C on Arduino J3 (SDA/SCL)
#  - UART TX on Arduino J3 AR8
#  - LEDs 0..3
#  - SPI on Arduino SPI header (AR_MISO, AR_MOSI, AR_SCK, AR_SS)
# Top level: top_pynq_se95
#
# Author: Md Shahriar Dipto
# Mat.Nr.: 5227587
# Faculty: 4
# Institution: Hochschule Bremen
# =====================================================================

# ---------------------------------------------------------------------
# 125 MHz PL clock (from Ethernet PHY)  -> clk_125mhz
# ---------------------------------------------------------------------
set_property PACKAGE_PIN H16 [get_ports clk_125mhz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_125mhz]
create_clock -period 8.000 -name clk125 [get_ports clk_125mhz]

# ---------------------------------------------------------------------
# User Button BTN0 as synchronous reset (active high) -> rst
# ---------------------------------------------------------------------
set_property PACKAGE_PIN D19 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# ---------------------------------------------------------------------
# I²C on Arduino J3 header
#   AR_SDA -> P16
#   AR_SCL -> P15
# ---------------------------------------------------------------------
set_property PACKAGE_PIN P16 [get_ports i2c_sda]
set_property IOSTANDARD LVCMOS33 [get_ports i2c_sda]
set_property PULLUP true [get_ports i2c_sda]

set_property PACKAGE_PIN P15 [get_ports i2c_scl]
set_property IOSTANDARD LVCMOS33 [get_ports i2c_scl]
set_property PULLUP true [get_ports i2c_scl]

# ---------------------------------------------------------------------
# UART TX routed to Arduino J3 AR8  -> uart_tx
#   AR8 -> V17
# ---------------------------------------------------------------------
set_property PACKAGE_PIN V17 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

# ---------------------------------------------------------------------
# User LEDs (LED0..LED3)
#   LED0 -> R14
#   LED1 -> P14
#   LED2 -> N16
#   LED3 -> M14
# ---------------------------------------------------------------------
set_property PACKAGE_PIN R14 [get_ports led0]
set_property IOSTANDARD LVCMOS33 [get_ports led0]

set_property PACKAGE_PIN P14 [get_ports led1]
set_property IOSTANDARD LVCMOS33 [get_ports led1]

set_property PACKAGE_PIN N16 [get_ports led2]
set_property IOSTANDARD LVCMOS33 [get_ports led2]

set_property PACKAGE_PIN M14 [get_ports led3]
set_property IOSTANDARD LVCMOS33 [get_ports led3]

# ---------------------------------------------------------------------
# SPI interface on Arduino SPI header (external microSD / SPI module)
#   AR_MISO -> W15  (sd_miso, input)
#   AR_SCK  -> H15  (sd_sclk)
#   AR_MOSI -> T12  (sd_mosi)
#   AR_SS   -> F16  (sd_cs_n, active low)
# ---------------------------------------------------------------------
set_property PACKAGE_PIN W15 [get_ports sd_miso]
set_property IOSTANDARD LVCMOS33 [get_ports sd_miso]

set_property PACKAGE_PIN H15 [get_ports sd_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports sd_sclk]

set_property PACKAGE_PIN T12 [get_ports sd_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports sd_mosi]

set_property PACKAGE_PIN F16 [get_ports sd_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports sd_cs_n]

