#!/bin/bash
# 20231223 BM - made changes - Moved readsb before vector to get it to complete succesfully
#						- changed logfile to home dir so it is not lost when rebooted
#						- Extended delay for service check at the end
#						- changed modification of readsb config to append to line rather than replace
#						- Restarted services at end to load new config
#						- Added reboot prompt to the end


# Throw warning if script is not executed as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root to set up the service correctly"
    echo "Run it like this:"
    echo "sudo ./download.sh"
    exit 1
fi

#BM - Added this block to setup a logfile in the users home dir so it is not lost on reboot
current_datetime=$(date +'%Y-%m-%d_%H-%M')
#change to user's home dir
user_dir=$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)
cd $user_dir
logfile="${user_dir}/wingbits_${current_datetime}.log"
#echo $logfile

mkdir -p /etc/wingbits

if [[ -e /etc/wingbits/device ]]; then
    read -r device_id < /etc/wingbits/device
fi

if [[ -z ${device_id} ]]; then
    read -p "Enter the device ID: " device_id </dev/tty
    echo "$device_id" > /etc/wingbits/device
fi

echo "Using device ID: $device_id"

# possible they just hit enter above or the file is empty
if [[ -z ${device_id} ]]; then
    echo "You need to add the device id that you got in the email"
    exit 1
else
    grep -qxF "DEVICE_ID=\"$device_id\"" /etc/default/vector || echo "DEVICE_ID=\"$device_id\"" >> /etc/default/vector
    echo "Device ID saved to local config file /etc/wingbits/device"
fi

# Function to display loading animation with an airplane icon
function show_loading() {
  local text=$1
  local delay=0.2
  local frames=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")
  local frame_count=${#frames[@]}
  local i=0

  while true; do
    local frame_index=$((i % frame_count))
    printf "\r%s  %s" "${frames[frame_index]}" "${text}"
    sleep $delay
    i=$((i + 1))
  done
}

# Function to run multiple commands and log the output
function run_command() {
  local commands=("$@")
  local text=${commands[0]}
  local command
  echo "===================${text}====================" >> $logfile

  for command in "${commands[@]:1}"; do
    (
      eval "${command}" >> $logfile 2>&1
      printf "done" > /tmp/wingbits.done
    ) &
    local pid=$!

    show_loading "${text}" &
    local spinner_pid=$!

    # Wait for the command to finish
    wait "${pid}"

    # Kill the spinner
    kill "${spinner_pid}"
    wait "${spinner_pid}" 2>/dev/null

    # Check if the command completed successfully
    if [[ -f /tmp/wingbits.done ]]; then
      rm /tmp/wingbits.done
      printf "\r\033[0;32m✓\033[0m   %s\n" "${text}"
    else
      printf "\r\033[0;31m✗\033[0m   %s\n" "${text}"
    fi
  done
}

function check_service_status(){
  local services=("vector" "readsb")
  for service in "${services[@]}"; do
    status="$(systemctl is-active "$service".service)"
    if [ "$status" != "active" ]; then
        echo "$service is inactive. Waiting 30 seconds..."
        sleep 30											#BM - Extended delay to give it time for readsb and vector to start
        status="$(systemctl is-active "$service".service)"
        if [ "$status" != "active" ]; then
            echo "$service is still inactive."
        else
            echo "$service is now active. ✈"
        fi
    else
        echo "$service is active. ✈"
    fi
  done
}
# Step 1: Update package repositories
run_command "Updating package repositories" "apt-get update"

# Step 2: Upgrade installed packages
run_command "Upgrading installed packages" "apt-get upgrade -y"

# Step 3: Install curl if not already installed
run_command "Installing curl" "apt-get -y install curl"


#BM - Switched the order of readsb and vector install as readsb would often error out if last
# Step 4: Download and install readsb
run_command "Installing readsb" \
    "curl -sL https://github.com/wiedehopf/adsb-scripts/raw/master/readsb-install.sh | bash" \
    "sed -i -e 's|After=.*|After=vector.service|' /lib/systemd/system/readsb.service" \
	"curl -sL https://github.com/wiedehopf/graphs1090/raw/master/install.sh | bash"
	
#BM - Took out above - "sed -i 's|NET_OPTIONS=\".*\"|NET_OPTIONS=\"--net-only --net-connector localhost,30006,json_out\"|' /etc/default/readsb"  \
#BM - Could not work out yet how to make the following line work with eval so have separated it out for now...
if grep -q -- "--net-connector localhost,30006,json_out" /etc/default/readsb; 
	then
    echo "readsb already configured for Wingbits" | sudo tee >> $logfile
else
	sed -i.bak 's/NET_OPTIONS="[^"]*/& '"--net-connector localhost,30006,json_out"'/' /etc/default/readsb
	echo "Added Wingbits config to readsb config file" | sudo tee >> $logfile
fi

# Step 5: Download and install Vector
run_command "Installing vector" \
  "curl -1sLf 'https://repositories.timber.io/public/vector/cfg/setup/bash.deb.sh' | sudo -E bash" \
  "apt-get -y install vector" \
  "mkdir -p /etc/vector" \
  "touch /etc/vector/vector.yaml" \
  "curl -o /etc/vector/vector.yaml 'https://gitlab.com/wingbits/config/-/raw/master/vector.yaml'" \
  "sed -i 's|ExecStart=.*|ExecStart=/usr/bin/vector --watch-config|' /lib/systemd/system/vector.service" 
  "echo \"DEVICE_ID=\\\"$device_id\\\"\" | sudo tee -a /etc/default/vector > /dev/null"



# Step 6: Reload systemd daemon, enable and start services
run_command "Starting services" \
  "systemctl daemon-reload" \
  "systemctl enable vector" \
  "systemctl restart readsb vector"	#BM - Needs to be restarted to load new config
 # "systemctl enable readsb" \	#BM - Already enabled by the readsb install
 # "systemctl start vector" \
  

# Step 7: Create the check status cron job
echo '#!/bin/bash
STATUS="$(systemctl is-active vector.service)"

if [ "$STATUS" != "active" ]; then
    systemctl restart vector.service
    echo "$(date): Service was restarted" >> $logfile
fi' > /etc/wingbits/check_status.sh && \
sudo chmod +x /etc/wingbits/check_status.sh && \
echo "*/5 * * * * root /bin/bash /etc/wingbits/check_status.sh" | sudo tee /etc/cron.d/wingbits

echo -e "\n\033[0;32mInstallation completed successfully!\033[0m"

# Step 8: Check if services are online
check_service_status

echo -e "\nPlease restart with \"sudo reboot\" to finalise install"
