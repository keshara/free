#!/bin/bash

VER="8.11.0"
sym_link='/opt/logstash'

echo "logstash tar ball downloading.."
cd /opt/
wget -q -c https://artifacts.elastic.co/downloads/logstash/logstash-$VER-linux-x86_64.tar.gz -O - | tar -xz
echo "--> Complete"
sleep 1

echo "Links the application.."
if [ -L ${sym_link} ] ; then
echo "symlink for logstash already exists!"
else
echo "symlink for logstash creating.."
ln -s /opt/logstash-$VER /opt/logstash
fi
echo "--> Complete"
sleep 1

echo "Creating main config directory.."
if [ -d /opt/logstash/conf.d ] ; then
echo "conf.d already exists!"
else
mkdir -p /opt/logstash/conf.d
mkdir -p /opt/logstash/scripts
fi
echo "--> Complete"
sleep 1


echo "Logstash configs updating.."
cat << \EOF > /opt/logstash/conf.d/main.conf
input { tcp { port => 3501 }}
output { stdout { codec => rubydebug }}
EOF
cd /opt/logstash/config
sed -i 's/# config.reload.automatic: false/config.reload.automatic: true/g' logstash.yml
echo "--> Complete"
sleep 1


echo "Creating service.."
if [ -f "/etc/systemd/system/logstash.service" ]; then
echo "systemd unit file already exists!"
else
echo "systemd unit file is creating.."
cat << \EOF > /etc/systemd/system/logstash.service
[Unit]
Description=logstash

[Service]
Type=simple
ExecStart=/opt/logstash/bin/logstash "--path.settings" "/opt/logstash/config"
Restart=always
WorkingDirectory=/opt/logstash
Nice=19
LimitNOFILE=16384
StandardOutput=null

[Install]
WantedBy=multi-user.target
EOF
fi
echo "--> Complete"
sleep 1

echo "Enable pipelines.."
rm -fr /opt/logstash/config/pipelines.yml
cat << \EOF > /opt/logstash/config/pipelines.yml
- pipeline.id: main
  path.config: "/opt/logstash/conf.d/main.conf"
EOF
echo "--> Complete"
sleep 1


echo "enable/start logstash service"
systemctl daemon-reload
systemctl enable logstash
systemctl start logstash
echo "---------------------------"
echo "Logstash successfully setup"
echo "---------------------------"
