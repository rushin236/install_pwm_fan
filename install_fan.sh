#!/bin/bash

# ==========================================
# Raspberry Pi 4 PWM Fan Installer (Debian Trixie/Bookworm)
# Installs pigpio from source + Silent PWM Fan Control
# ==========================================

set -e  # Exit on error

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo ./install_fan.sh)"
    exit
fi

echo ">>> Updating System..."
apt update && apt install -y build-essential python3-setuptools python3-full wget unzip python3-gpiozero python3-rpi.gpio

# --- Step 1: Install pigpio from Source ---
if ! command -v pigpiod &> /dev/null; then
    echo ">>> pigpiod not found. Compiling from source..."
    cd /tmp
    wget https://github.com/joan2937/pigpio/archive/refs/tags/v79.tar.gz
    tar xzf v79.tar.gz
    cd pigpio-79
    make
    make install
    ldconfig
    cd ..
    rm -rf pigpio-79 v79.tar.gz
    echo ">>> pigpio installed successfully."
else
    echo ">>> pigpio is already installed. Skipping compilation."
fi

# --- Step 2: Create pigpiod Service ---
echo ">>> Creating pigpiod systemd service..."
cat <<EOF > /etc/systemd/system/pigpiod.service
[Unit]
Description=Pigpio Daemon
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/pigpiod -l
PIDFile=/var/run/pigpio.pid
ExecStop=/bin/systemctl kill pigpiod
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# --- Step 3: Create Python Fan Script ---
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="pwm_fan.py"

echo ">>> Creating Fan Control Script at $INSTALL_DIR/$SCRIPT_NAME..."
cat <<EOF > $INSTALL_DIR/$SCRIPT_NAME
#!/usr/bin/env python3
import time
import signal
import sys
from gpiozero import PWMOutputDevice, CPUTemperature
from gpiozero.pins.pigpio import PiGPIOFactory

# --- Configuration ---
GPIO_PIN = 18           # Physical Pin 12
PWM_FREQ = 25000        # 25kHz (Silent)
POLL_INTERVAL = 3       # Seconds

def main():
    # Attempt to connect to the pigpio daemon
    try:
        factory = PiGPIOFactory()
    except Exception:
        print("Error: pigpiod daemon not running. Run: sudo pigpiod")
        sys.exit(1)

    # Initialize Hardware
    # Note: initial_value set to 0.5 (50%) just to start safe
    fan = PWMOutputDevice(GPIO_PIN, initial_value=0.5, frequency=PWM_FREQ, pin_factory=factory)
    cpu = CPUTemperature()

    last_speed = -1
    print("Fan Control Started using Custom IF/ELSE Curve.")

    try:
        while True:
            temp = cpu.temperature
            speed = 0.0

            # ---------------------------------------------------------
            # CUSTOM FAN CURVE (IF/ELSE BLOCK)
            # ---------------------------------------------------------
            if temp < 40:
                speed = 0.40  # Below 40°C: Run at 40% speed (Idle)

            elif temp < 50:
                speed = 0.50  # 40°C to 49.9°C: Run at 50% speed

            elif temp < 60:
                speed = 0.75  # 50°C to 59.9°C: Run at 75% speed

            else:
                speed = 1.00  # 60°C and above: Run at 100% speed
            # ---------------------------------------------------------

            # Apply the speed to the fan
            fan.value = speed

            # Calculate percentage for display
            pct = int(speed * 100)

            # Log only on change to keep journals clean
            if pct != last_speed:
                print(f"Fan Speed Changed: {pct}% (Temp: {temp:.1f}C)", flush=True)
                last_speed = pct

            time.sleep(POLL_INTERVAL)

    except KeyboardInterrupt:
        print("\nStopping Fan Control...")
        fan.value = 0.50  # Set to a safe 50% on exit
        sys.exit(0)

if __name__ == "__main__":
    main()
EOF

chmod +x $INSTALL_DIR/$SCRIPT_NAME

# --- Step 4: Create Fan Service ---
echo ">>> Creating PWM Fan systemd service..."
cat <<EOF > /etc/systemd/system/pwm-fan.service
[Unit]
Description=PWM Fan Control
After=network.target pigpiod.service
Requires=pigpiod.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 $INSTALL_DIR/$SCRIPT_NAME
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# --- Step 5: Enable & Start Everything ---
echo ">>> Enabling services..."
systemctl daemon-reload
systemctl enable pigpiod
systemctl start pigpiod

# Wait a moment for pigpiod to initialize
sleep 2

systemctl enable pwm-fan
systemctl restart pwm-fan

echo "=========================================="
echo "SUCCESS! Setup Complete."
echo "Check status with: sudo systemctl status pwm-fan"
echo "View logs with:    sudo journalctl -u pwm-fan -f"
echo "=========================================="
