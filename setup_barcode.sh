#!/bin/bash

# Проверка прав суперпользователя
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт с правами суперпользователя."
  exit
fi

# Запрос домена
read -p "Введите имя домена: " DOMAIN

# Установка необходимых пакетов
apt update
apt install -y nginx docker.io docker-compose

# Создание директории для приложения
mkdir -p /usr/apps/barcode
cd /usr/apps/barcode

# Клонирование репозитория
if ! git clone https://github.com/Proxoff/barcode_generator .; then
  echo "Ошибка: Не удалось клонировать репозиторий."
  exit 1
fi

# Сборка Docker-контейнера
docker build -t barcode_generator .

# Создание Docker Compose файла
cat <<EOF > docker-compose.yml
version: '3.7'
services:
  app:
    image: barcode_generator
    container_name: barcode_generator
    ports:
      - "8000:8000"
    restart: always
EOF

# Запуск Docker-контейнера
docker-compose up -d

# Настройка Nginx
NGINX_CONF=/etc/nginx/sites-available/$DOMAIN
ln -s $NGINX_CONF /etc/nginx/sites-enabled/

cat <<EOF > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /barcode {
        proxy_pass http://127.0.0.1:8000/barcode;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF

# Проверка конфигурации Nginx
nginx -t || exit 1

# Перезапуск Nginx
systemctl restart nginx

# Настройка SSL
SSL_CERT_PATH="/etc/ssl/$DOMAIN"
mkdir -p $SSL_CERT_PATH

cat <<SSL_UPDATE >> $NGINX_CONF

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate $SSL_CERT_PATH/certificate.crt;
    ssl_certificate_key $SSL_CERT_PATH/certificate.key;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /barcode {
        proxy_pass http://127.0.0.1:8000/barcode;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
SSL_UPDATE

# Перезапуск Nginx с SSL
nginx -t || exit 1
systemctl restart nginx

# Финальная инструкция
cat <<INSTRUCTIONS

Установка завершена. Скопируйте SSL-сертификаты в директорию $SSL_CERT_PATH.
После этого приложение будет доступно по адресу https://$DOMAIN/barcode?data=000000285568&format=png.
INSTRUCTIONS