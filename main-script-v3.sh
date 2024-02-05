#!/bin/bash
#
client_repo="ssh://git-codecommit.ca-central-1.amazonaws.com/v1/repos"
read -p "Enter the TOKEN given by XDR team: " TOKEN
read -p "Enter the Hostname given by XDR team: " hostname
echo "-------------------------"
echo "XDR SIEM Collector Setup"
echo "-------------------------"
echo
if [ -f "/opt/appliance/.done" ]; then
  echo "Set already completed. Exiting.."
  exit 1
fi

rm -fr /etc/netplan/*
nic=`cat /proc/net/dev | awk 'NR > 1 {print "" $1 ""}' | egrep '^e|h' | sed s/://g`
read -p "Enter the static IP of the server in CIDR notation(e.g. 1.2.3.4/24): " staticip 
read -p "Enter the IP of your gateway: " gatewayip
read -p "Enter the IP of preferred nameservers (seperated by a coma if more than one): " nameserversip
echo
cat > /etc/netplan/01-netcfg.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $nic:
      addresses:
      - $staticip
      gateway4: $gatewayip
      nameservers:
          addresses: [$nameserversip]
EOF
sudo netplan apply > /dev/null 2>&1
echo "Configuring Network.."
sleep 10
ping -c 3 $nameserversip > /dev/null 2>&1
if [ $? -eq 0 ]; then
	echo "-------------------------"
	echo "Static IP successfully applied"
else
	echo "Nameserver $nameserversip is not available. Please check your network and re-run the script!"
	exit
fi
echo
sleep 1

# Install necessary pkgs..
echo "Installing required pkgs.."
apt-get install -y git curl wget gpg > /dev/null 2>&1
echo "--> Complete"
echo
sleep 1



# Configure GIT basics
echo "Setting up repository.."
git config --global credential.helper store
git config --global user.email "temp@example.com"
git config --global user.name "temp"
echo "--> Complete"
echo
sleep 1

# update ssh config
sed -i "s/XXXXXXXXXXXXXXXX/$TOKEN/g" /root/.ssh/config
sleep 1

hostnamectl set-hostname $hostname
echo

# Verify & git clone
if ! (git -C /opt/appliance/ clone "$client_repo"/"$hostname" > /dev/null 2>&1) then
    echo "Unable to load repository. Check the TOKEN & Hostname provided. If the issue continues, Please contact Jolera XDR Team."
    sed -i "s/$TOKEN//XXXXXXXXXXXXXXXX/g" /root/.ssh/config
    exit 1
else
    echo "--------------------------"
    echo "TOKEN successfully applied"
    echo
    sleep 1
    echo "Continue to setup Logstash.."
    echo
fi
sleep 3

# Logstash setup
cd /opt/appliance/$hostname
bash logstash-setup.sh
echo
echo "Do not close the terminal! application is starting up.."
sleep 60
# Verify Logsatash status
exec 3> /dev/tcp/127.0.0.1/9600
if [ $? -eq 0 ];then 
	 echo "--> Logsatash is listening"
else 
	echo "Logsatash is not working"
	exit
fi
sleep 1



cat << EOF > /opt/logstash/scripts/schedule-task.sh
# configuration update
echo >> /opt/logstash/scripts/log.log
echo "Schedule Task starting - `date` -" >> /opt/logstash/scripts/log.log
echo "--------------------------------" >> /opt/logstash/scripts/log.log
cd /opt/appliance/$hostname
[ -f main.conf ] || exit 1
HEAD1_main_conf=\$(git rev-parse HEAD:main.conf)
if [ -f upgrade.sh ]; then
  HEAD1_upgrade=\$(git rev-parse HEAD:upgrade.sh)
fi
git pull > /dev/null 2>&1
echo "Checking if new configuration is avialable.." >> /opt/logstash/scripts/log.log
HEAD2_main_conf=\$(git rev-parse HEAD:main.conf)
if [ \$HEAD1_main_conf = \$HEAD2_main_conf ];then
  echo "Logstash configuration update is not required" >> /opt/logstash/scripts/log.log
else
  echo "Logstash configuration update is required" >> /opt/logstash/scripts/log.log
  echo >> /opt/logstash/scripts/log.log
  echo "Applying config updates.." >> /opt/logstash/scripts/log.log
  sleep 1
  \cp -fr /opt/logstash/conf.d/main.conf /opt/logstash/conf.d/bk-main.conf
  \cp -fr main.conf /opt/logstash/conf.d/main.conf
  echo "----" > /opt/logstash/logs/logstash-plain.log
  while IFS= read -r LOGLINE || [[ -n "\$LOGLINE" ]] > /dev/null 2>&1; do
    echo "Verifying configuration.." >> /opt/logstash/scripts/log.log
    # printf '%s\n' "\$LOGLINE"
    if [[ "\${LOGLINE}" =~ "[main] Pipeline started" ]]; then
      echo "New configuration successfully applied." >> /opt/logstash/scripts/log.log
    elif [[ "\${LOGLINE}" =~ "[ERROR][logstash" ]]; then
      echo "Found invalid config. Rolling back.." >> /opt/logstash/scripts/log.log
      \cp -fr /opt/logstash/conf.d/bk-main.conf /opt/logstash/conf.d/main.conf
    fi
  done < <(timeout 60 tail -f /opt/logstash/logs/logstash-plain.log)
fi
sleep 1

# Checking if upgrade required..
echo >> /opt/logstash/scripts/log.log
echo "--------------------------------" >> /opt/logstash/scripts/log.log
echo "checking if Logstash Version upgrade is required" >> /opt/logstash/scripts/log.log
if [ -f upgrade.sh ]; then
  HEAD2_upgrade=\$(git rev-parse HEAD:upgrade.sh)
  if [ "\$HEAD1_upgrade" = "\$HEAD2_upgrade" ];then
    echo "Version upgrade is not required!" >> /opt/logstash/scripts/log.log
    echo "--> Job COMPLETED" >> /opt/logstash/scripts/log.log
    echo >> /opt/logstash/scripts/log.log
    exit 0
  else
    echo "Version upgrade is required" >> /opt/logstash/scripts/log.log
    \cp -fr upgrade.sh /opt/logstash/scripts/upgrade.sh
    chmod +x /opt/logstash/scripts/upgrade.sh
    bash /opt/logstash/scripts/upgrade.sh  >> /opt/logstash/scripts/log.log
  fi
  sleep 1
else 
  echo "-> not required" >> /opt/logstash/scripts/log.log
  echo >> /opt/logstash/scripts/log.log
fi
EOF

# Scheduling tasks
crontab -l > /dev/null 2>&1 | { cat; echo "*/30 * * * * /bin/bash /opt/logstash/scripts/schedule-task.sh > /dev/null 2>&1"; } | crontab -
touch /opt/appliance/.done
echo
echo "-----------------------------"
echo "Script successfully executed"
echo "-----------------------------"

