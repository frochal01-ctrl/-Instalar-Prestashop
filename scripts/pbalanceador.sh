#!/bin/bash
set -e

DOMINIO="franbalanceador.duckdns.org"
TOKEN_DUCKDNS="840b3e40-26c7-4cf4-b2d8-a2460e9b57da"
EMAIL="jkanime00000@gmail.com"

# 1. Instalar Apache, Certbot y el plugin DNS de DuckDNS
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2 certbot python3-pip
pip3 install certbot-dns-duckdns --break-system-packages

# 2. Habilitar módulos de balanceo de carga y SSL en Apache
a2enmod proxy proxy_http proxy_balancer lbmethod_byrequests ssl headers

# 3. Generar el certificado válido con Certbot y Let's Encrypt (vía DNS)
certbot certonly \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  --preferred-challenges dns \
  --authenticator dns-duckdns \
  --dns-duckdns-token "$TOKEN_DUCKDNS" \
  --dns-duckdns-propagation-seconds 60 \
  -d "$DOMINIO"

# 4. Configurar Apache con el certificado generado y el balanceo de carga con sesiones persistentes
cat <<EOF > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
    ServerName $DOMINIO
    Redirect permanent / https://$DOMINIO/
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMINIO
    ServerAdmin webmaster@localhost

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$DOMINIO/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$DOMINIO/privkey.pem

    RequestHeader set X-Forwarded-Proto "https"

    Header add Set-Cookie "ROUTEID=.%{BALANCER_WORKER_ROUTE}e; path=/" env=BALANCER_ROUTE_CHANGED
    <Proxy "balancer://micluster">
        BalancerMember http://192.168.10.11 route=1
        BalancerMember http://192.168.10.12 route=2
        ProxySet lbmethod=byrequests stickysession=ROUTEID
    </Proxy>

    ProxyPreserveHost On
    ProxyPass / balancer://micluster/
    ProxyPassReverse / balancer://micluster/

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# 5. Comprobar sintaxis, reiniciar Apache y configurar UFW
apache2ctl configtest
systemctl restart apache2

apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable




