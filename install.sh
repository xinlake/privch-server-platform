#!/bin/bash

# rand password
function randPasswd {
    local length=${1:-16}
    if ! [[ "$length" =~ ^[0-9]+$ ]]; then
        length=16
    fi

    if [[ -c /dev/urandom ]]; then
        echo "$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c$length)"
    else
        echo "$(openssl rand -base64 $length | tr -dc A-Za-z0-9)"
    fi
}

# upgrade os and install packages
function installPackages {
    apt update
    DEBIAN_FRONTEND=noninteractive apt upgrade -y

    local packages=(
        mariadb-server
        nginx
        redis-server
        supervisor
        git
        php
        php-fpm
        php-cli
        php-bcmath
        php-mbstring
        php-gd
        php-gmp
        php-xml
        php-zip
        php-curl
        php-redis
        php-mysql
    )

    apt install -y "${packages[@]}"

    # setup mysql
    echo -e "\nn\nY\nY\nY\nY\n" | mysql_secure_installation

    # config redis
    sed --in-place --expression '/^[[:space:]]*supervised no[[:space:]]*$/s/supervised no/supervised systemd/' \
        /etc/redis/redis.conf

    systemctl enable --now mariadb
    systemctl enable --now nginx
    systemctl enable --now redis-server
    systemctl enable --now supervisor
}

function createMysqlUserAndDb {
    local db_name="$1"
    local db_user="$2"
    local db_passwd="$3"

    mysql --execute "CREATE DATABASE $db_name;"
    mysql --execute "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_passwd';"
    mysql --execute "GRANT ALL PRIVILEGES ON *.* TO '$db_user'@'localhost' WITH GRANT OPTION;"
    mysql --execute "FLUSH PRIVILEGES;"
}

# install v2board
function installV2Board {
    local v2board_mysql_db="$1"
    local v2board_mysql_user="$2"
    local v2board_mysql_passwd="$3"
    local site_dir_root="$4"
    local site_admin_email="$5"
    local site_nginx_file="$6"

    mkdir --mode 0755 --parents $site_dir_root
    mkdir --mode 0755 --parents ~/.composer
    echo "{}" > ~/.composer/composer.json

    rm -rf $site_dir_root/* && rm -rf $site_dir_root/.*
    git clone --depth 1 --branch dev https://github.com/v2board/v2board.git $site_dir_root/
    rm -rf $site_dir_root/.git*

    cd $site_dir_root
    export COMPOSER_ALLOW_SUPERUSER=1
    echo -e "\n$v2board_mysql_db\n$v2board_mysql_user\n$v2board_mysql_passwd\n$site_admin_email\n" \
        | sh init.sh

    mkdir --mode 0755 --parents ~/privch-server-platform
    git clone --depth 1 --branch dev https://github.com/xinlake/privch-server-platform.git \
        ~/privch-server-platform/

    # create blocklist file
    sh ~/privch-server-platform/create_blocklist.sh $SITE_DIR_ROOT/blocklist.conf

    sed --expression "s|\<SITE_DIR_ROOT\>|$site_dir_root|g" ~/privch-server-platform/supervisor.conf \
        > /etc/supervisor/conf.d/v2board.conf

    sed --expression "s|\<SITE_DIR_ROOT\>|$site_dir_root|g" ~/privch-server-platform/nginx.conf \
        > /etc/nginx/sites-available/$site_nginx_file

    # start processes which have been set to autostart.
    supervisorctl reread
    supervisorctl update

    chown --recursive www-data:www-data $site_dir_root
    chmod --recursive 755 $site_dir_root

    # everythind ready
    rm /etc/nginx/sites-enabled/default
    ln --symbolic /etc/nginx/sites-available/$site_nginx_file /etc/nginx/sites-enabled/$site_nginx_file
}

# start here #
# check root
if [[ $EUID -ne 0 ]]; then
    echo "This script only supports running as root"
    exit 1
fi

installPackages

# create mysql user and db for v2board
V2BOARD_MYSQL_DB="PRIVCH"
V2BOARD_MYSQL_USER="privch"
V2BOARD_MYSQL_PASSWD="$(randPasswd)"

SITE_DIR_ROOT="/var/www/privch"
SITE_ADMIN_EMAIL="xinlakeliu@gmail.com"
SITE_SSL_EMAIL="xinlakeliu@gmail.com"
SITE_NGINX_FILE="privch"

# Obtain ssl/tls certificate
# certbot certonly --nginx --noninteractive \
#     --agree-tos --email $SITE_SSL_EMAIL \
#     --domains DOMAIN \
#     --webroot --webroot-path $WEB_ROOT
# if [ $? -ne 0 ]; then
#     echo "Obtain SSL/TLS certificate failed."
#     exit 1
# fi

createMysqlUserAndDb "$V2BOARD_MYSQL_DB" "$V2BOARD_MYSQL_USER" "$V2BOARD_MYSQL_PASSWD"
installV2Board "$V2BOARD_MYSQL_DB" "$V2BOARD_MYSQL_USER" "$V2BOARD_MYSQL_PASSWD" \
               "$SITE_DIR_ROOT" "$SITE_ADMIN_EMAIL" "$SITE_NGINX_FILE"

systemctl restart mariadb
systemctl restart nginx
systemctl restart redis-server
systemctl restart supervisor

# create v2board cron task
*/1 * * * * php $SITE_DIR_ROOT/artisan schedule:run >/dev/null 2>&1

echo "PrivCh MySQL User: $V2BOARD_MYSQL_USER"
echo "PrivCh MySQL Password: $V2BOARD_MYSQL_PASSWD"

echo "PrivCh Site Config: $SITE_NGINX_FILE"
echo "PrivCh WWW Directory: $SITE_DIR_ROOT"
