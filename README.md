# Implementation of a VHDL-Based Telemetry System for Data Acquisition  
## Aquasonic III Sounding Rocket

🎓 **Master’s Thesis – Hochschule Bremen**  
👤 **Author:** Md Shahriar Dipto  
📅 **Submission:** Winter Semester 2025–26 (5th Jan 2026)

---

## 📌 Overview

This repository contains the **documentation and VHDL implementation** of a real-time telemetry and data acquisition system developed for the **Aquasonic III sounding rocket**.

The design targets an FPGA (PYNQ-Z2) and provides:

- Real-time temperature acquisition via **I²C** (NXP/Philips SE95)
- Telemetry frame construction using **AX.25 UI frames** + **CRC-16/X.25**
- UART downlink output (ASCII hex stream)
- Persistent onboard logging to **microSD** using **SPI**

---

## 🚀 Key Modules

- **I²C Master (SE95)**: sensor readout FSM  
- **Payload Builder**: packs a small binary telemetry payload  
- **AX.25 Framer**: builds FLAG→ADDR→CTRL→PID→INFO→CRC→FLAG  
- **CRC-16/X.25**: reflected polynomial 0x8408, init 0xFFFF  
- **UART TX**: 8N1 transmitter  
- **SPI Master + SD Controller**: SD init + single-block write (CMD24)  
- **Logger**: buffers records into **512-byte sectors** for SD writes  
- **Testbenches**: I²C slave model, AX.25 tests, SPI/SD tests

---

## 🧩 Repository Structure

| Folder | Description |
|------|-------------|
| `rtl/` | Core synthesizable VHDL modules |
| `top/` | Top-level VHDL for the FPGA board |
| `constraints/` | XDC constraints (PYNQ-Z2) |
| `tb/` | Simulation testbenches and models |
| `docs/` | Thesis PDFs (report + code appendix) |

---

## 📄 Documentation

- `docs/thesis_report.pdf` – Thesis report (theory, architecture, results)
- `docs/thesis_vhdl_code.pdf` – Full VHDL listing appendix

---

## 🛠️ Toolchain / Target

- **Board:** PYNQ-Z2 (Xilinx Zynq-7020)
- **Tool:** Xilinx Vivado
- **System clock:** 125 MHz

---

## 📜 License

Released under the MIT License (see `LICENSE`).

---

## 📬 Contact

- GitHub: https://github.com/mdipto
