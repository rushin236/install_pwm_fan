# Raspberry Pi 4 PWM Fan Control (Silent 25kHz)

This repository contains an automated setup script for controlling a 4-pin PWM fan on a Raspberry Pi 4 running **Debian Trixie (Testing)** or **Bookworm**.

It solves the common issues with "hummy" fans and missing `pigpio` packages on newer OS versions by compiling `pigpio` from source and using hardware-timed PWM.

## Features

- **Silent Operation:** Runs at **25kHz** (Hardware PWM) to eliminate motor noise.
- **Smart Curve:** - **Idle (<50°C):** 35% speed (Silent)
    - **Load (50°C):** 50% speed
    - **Max (70°C):** 100% speed
- **Clean Logs:** Only logs when fan speed actually changes (no log spam).
- **Auto-Start:** Installs as a systemd service automatically.

## Hardware Setup

Before running the software, ensure your fan is connected to the correct pins:

- **Fan PWM Pin (Blue/Green):** GPIO 18 (Physical Pin 12)
- **Fan Power (+):** 5V (Physical Pin 4)
- **Fan Ground (-):** GND (Physical Pin 6)

## Installation

1.  **Clone this repository:**

    ```bash
    git clone https://github.com/rushin236/install_pwm_fan.git
    cd install_pwm_fan
    ```

2.  **Run the installer:**

    ```bash
    sudo chmod +x install_fan.sh
    sudo ./install_fan.sh
    ```

    _The script will automatically compile `pigpio`, install Python dependencies, and set up the system service._

## Usage

**Check Status:**

```bash
sudo systemctl status pwm-fan

```

**View Live Logs:**

```bash
sudo journalctl -u pwm-fan -f

```

**Stop/Start:**

```bash
sudo systemctl stop pwm-fan
sudo systemctl start pwm-fan

```
