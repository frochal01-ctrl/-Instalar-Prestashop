#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# --- 1. Instalar Node.js 24 LTS, extensiones PHP, Composer y herramientas ---
apt-get update -y
apt-get install -y ca-certificates curl gnupg unzip git composer \
  php8.2-curl php8.2-gd php8.2-intl php8.2-mbstring php8.2-xml php8.2-zip php8.2-bcmath php8.2-imagick php8.2-mysql

# Añadir repositorio oficial de NodeSource para Node.js 24 (incluye npm)
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt-get install -y nodejs

# --- 2. Ajustar php.ini (Apache y CLI) ---
for INI in /etc/php/8.2/apache2/php.ini /etc/php/8.2/cli/php.ini; do
  sed -i 's/^;*max_input_vars.*/max_input_vars = 5000/' "$INI"
  sed -i 's/^;*memory_limit.*/memory_limit = 512M/' "$INI"
  sed -i 's/^;*post_max_size.*/post_max_size = 128M/' "$INI"
  sed -i 's/^;*upload_max_filesize.*/upload_max_filesize = 128M/' "$INI"
done

# --- 3. Módulos, AllowOverride y detección de HTTPS tras proxy en Apache ---
a2enmod rewrite headers setenvif
sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
echo 'SetEnvIf X-Forwarded-Proto "https" HTTPS=on' > /etc/apache2/conf-available/proxy-ssl.conf
a2enconf proxy-ssl
systemctl restart apache2

# --- 4. Descargar código fuente desde GitHub Tags, compilar e instalar ---
if [ "$1" = "instalar" ]; then
  cd /tmp
  rm -rf 9.2.1.zip PrestaShop-9.2.1
  curl -fL -o 9.2.1.zip https://github.com/PrestaShop/PrestaShop/archive/refs/tags/9.2.1.zip
  unzip -q 9.2.1.zip

  rm -rf /var/www/html/* /var/www/html/.[!.]*
  cp -r /tmp/PrestaShop-9.2.1/. /var/www/html/
  chown -R www-data:www-data /var/www/html/

  # Instalar dependencias PHP (Composer) como www-data con caché en /tmp
  cd /var/www/html
  sudo -u www-data HOME=/tmp COMPOSER_ALLOW_SUPERUSER=1 php -d memory_limit=-1 /usr/bin/composer install --no-dev --optimize-autoloader

  # Compilar todos los assets (themes y módulos) ignorando tests, vendor y node_modules
  find /var/www/html -maxdepth 4 -name "package.json" \
    -not -path "*/vendor/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/tests/*" | while read -r pkg; do
      DIR=$(dirname "$pkg")
      echo "Compilando assets en: $DIR"
      cd "$DIR"
      sudo -u www-data HOME=/tmp npm install --no-audit --no-fund
      sudo -u www-data HOME=/tmp NODE_OPTIONS=--openssl-legacy-provider npm run build || true
  done

  cd /var/www/html

  # Ejecutar instalador CLI
  sudo -u www-data php -d memory_limit=-1 /var/www/html/install-dev/index_cli.php \
    --domain=franbalanceador.duckdns.org \
    --db_server=192.168.20.20 \
    --db_name=prestashop_db \
    --db_user=ps_user \
    --db_password=password_seguro \
    --prefix=ps_ \
    --language=es \
    --country=es \
    --timezone=Europe/Madrid \
    --ssl=1 \
    --rewrite=1 \
    --email=admin@franbalanceador.duckdns.org \
    --password=AdminPassword123 \
    --firstname=Admin \
    --lastname=Tienda

  # Parchear porcentajes sin escapar en traducciones es-ES (evita ValueError en PHP 8.2)
  find /var/www/html/translations/es-ES /var/www/html/themes/hummingbird/translations/es-ES \
    -type f -name '*.xlf' \
    -exec sed -i -E 's/%([^sdfbcdeEfFgGhHoOxXu%])/%%\1/g; s/%$/%%/g' {} + 2>/dev/null || true

  # Limpieza tras instalar y borrado de caché para aplicar traducciones
  rm -rf /var/www/html/install-dev /var/www/html/admin_tienda /var/www/html/var/cache/*
  mv /var/www/html/admin-dev /var/www/html/admin_tienda

  # --- Instalar y configurar phpMyAdmin apuntando a Capa 3 (192.168.20.20) ---
    cd /tmp
  curl -fsSL -o phpMyAdmin.tar.gz https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz
  mkdir -p /var/www/html/phpmyadmin
  tar -xzf phpMyAdmin.tar.gz --strip-components=1 -C /var/www/html/phpmyadmin
  rm -f phpMyAdmin.tar.gz

  BLOWFISH=$(openssl rand -base64 24)
  cat <<PMAEOF > /var/www/html/phpmyadmin/config.inc.php
<?php
\$cfg['blowfish_secret'] = '$BLOWFISH';
\$i = 1;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['host'] = '192.168.20.20';
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;
PMAEOF

  mkdir -p /var/www/html/phpmyadmin/tmp
  chown -R www-data:www-data /var/www/html/phpmyadmin

  # Guardar copia compilada e instalada en /vagrant para que apache2 la reuse
  tar -czf /vagrant/ps_instalado.tar.gz -C /var/www/html .
else
  # En apache2: extraer la copia ya compilada e instalada desde /vagrant
  rm -rf /var/www/html/* /var/www/html/.[!.]*
  tar -xzf /vagrant/ps_instalado.tar.gz -C /var/www/html
  chown -R www-data:www-data /var/www/html/
fi

# --- 5. Aislamiento de red (sin salida a Internet) ---
ip route del default || true
cat << 'NETEOF' > /etc/network/if-up.d/sin-internet
#!/bin/sh
ip route del default 2>/dev/null || true
NETEOF
chmod +x /etc/network/if-up.d/sin-internet




