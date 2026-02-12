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

# Temperature Curve
TEMP_IDLE = 35          # Below this = Idle Speed
TEMP_START_RAMP = 40    # Start increasing speed
TEMP_MAX = 70           # 100% Speed
SPEED_IDLE = 0.25       # 25% Speed
SPEED_AT_40C = 0.40     # 40% Speed
SPEED_MAX = 1.00        # 100% Speed

def get_speed(temp):
    if temp >= TEMP_MAX: return SPEED_MAX
    if temp < TEMP_START_RAMP: return SPEED_IDLE
    
    # Linear calculation between 40C and 70C
    temp_range = TEMP_MAX - TEMP_START_RAMP
    speed_range = SPEED_MAX - SPEED_AT_40C
    current_offset = temp - TEMP_START_RAMP
    return SPEED_AT_40C + ((current_offset / temp_range) * speed_range)

def main():
    try:
        factory = PiGPIOFactory()
    except Exception:
        print("Error: pigpiod daemon not running.")
        sys.exit(1)

    fan = PWMOutputDevice(GPIO_PIN, initial_value=SPEED_IDLE, frequency=PWM_FREQ, pin_factory=factory)
    cpu = CPUTemperature()
    
    last_speed = -1

    print(f"Fan Control Started. Idle: {int(SPEED_IDLE*100)}%, Max: {TEMP_MAX}C")

    try:
        while True:
            temp = cpu.temperature
            speed = get_speed(temp)
            fan.value = speed
            
            pct = int(speed * 100)
            
            # Log only on change to keep journals clean
            if pct != last_speed:
                print(f"Fan Speed Changed: {pct}% (Temp: {temp:.1f}C)", flush=True)
                last_speed = pct
                
            time.sleep(POLL_INTERVAL)

    except KeyboardInterrupt:
        fan.value = SPEED_AT_40C
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
