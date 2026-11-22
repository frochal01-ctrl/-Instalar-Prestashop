#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# 1. Instalar todo mientras haya acceso a Internet (incluyendo ufw)
apt-get update -y
apt-get install -y mariadb-server git ufw

# 2. Configurar MariaDB
sed -i 's/^bind-address.*/bind-address = 192.168.20.20/' /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl restart mariadb

# Base de datos práctica LAMP
mysql -e "CREATE DATABASE IF NOT EXISTS lamp_db;"
mysql -e "CREATE USER IF NOT EXISTS 'lamp_user'@'192.168.20.%' IDENTIFIED BY 'password_seguro';"
mysql -e "GRANT ALL PRIVILEGES ON lamp_db.* TO 'lamp_user'@'192.168.20.%';"

# Base de datos PrestaShop
mysql -e "CREATE DATABASE IF NOT EXISTS prestashop_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'ps_user'@'192.168.20.%' IDENTIFIED BY 'password_seguro';"
mysql -e "GRANT ALL PRIVILEGES ON prestashop_db.* TO 'ps_user'@'192.168.20.%';"

mysql -e "FLUSH PRIVILEGES;"

# 3. Importar esquema de la base de datos LAMP
cd /tmp
rm -rf iaw-practica-lamp
git clone https://github.com/josejuansanchez/iaw-practica-lamp.git
mysql lamp_db < /tmp/iaw-practica-lamp/db/database.sql

# 4. Configurar UFW antes de aislar la red
ufw default deny incoming
ufw default allow outgoing
ufw allow in on eth0 to any port 22 proto tcp
ufw allow from 192.168.20.0/24 to any port 3306 proto tcp
ufw --force enable

# 5. Aislar la capa 3 sin salida a internet (siempre al final)
ip route del default || true

cat << 'EOF' > /etc/network/if-up.d/sin-internet
#!/bin/sh
ip route del default 2>/dev/null || true
EOF
chmod +x /etc/network/if-up.d/sin-internet











