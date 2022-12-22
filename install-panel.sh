#!/bin/bash

set -e

#############################################################################
#                                                                           #
# Project 'pterodactyl-installer' for panel                                 #
#                                                                           #
# Copyright (C) 2018 - 2022, Vilhelm Prytz, <vilhelm@prytznet.se>           #
#                                                                           #
#   This program is free software: you can redistribute it and/or modify    #
#   it under the terms of the GNU General Public License as published by    #
#   the Free Software Foundation, either version 3 of the License, or       #
#   (at your option) any later version.                                     #
#                                                                           #
#   This program is distributed in the hope that it will be useful,         #
#   but WITHOUT ANY WARRANTY; without even the implied warranty of          #
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           #
#   GNU General Public License for more details.                            #
#                                                                           #
#   You should have received a copy of the GNU General Public License       #
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.  #
#                                                                           #
# https://github.com/vilhelmprytz/pterodactyl-installer/blob/master/LICENSE #
#                                                                           #
# This script is not associated with the official Pterodactyl Project.      #
# https://github.com/vilhelmprytz/pterodactyl-installer                     #
#                                                                           #
#############################################################################

######## General checks #########

# exit with error status code if user is not root
if [[ $EUID -ne 0 ]]; then
  echo "* Skrip ini harus dijalankan dengan hak akses root (sudo)." 1>&2
  exit 1
fi

# check for curl
if ! [ -x "$(command -v curl)" ]; then
  echo "* curl diperlukan agar skrip ini berfungsi."
  echo "* instal menggunakan apt (Debian dan derivatives) atau yum/dnf (CentOS)"
  exit 1
fi

########## Variables ############

# versioning
GITHUB_SOURCE="v0.11.0"
SCRIPT_RELEASE="v0.11.0"

# Version Panel
PANEL_VERSION="v1.10.4"

FQDN=""

# Default MySQL credentials
MYSQL_DB="pterodactyl"
MYSQL_USER="pterodactyl"
MYSQL_PASSWORD=""

# Environment
email=""

# Initial admin account
user_email=""
user_username=""
user_firstname=""
user_lastname=""
user_password=""

# Assume SSL, will fetch different config if true
SSL_AVAILABLE=false
ASSUME_SSL=false
CONFIGURE_LETSENCRYPT=false

# download URLs
PANEL_DL_URL="https://github.com/pterodactyl/panel/releases/download/$PANEL_VERSION/panel.tar.gz"
GITHUB_BASE_URL="https://raw.githubusercontent.com/fokusdotid/pterodactyl-installer/$GITHUB_SOURCE"

# ufw firewall
CONFIGURE_UFW=false

# firewall_cmd
CONFIGURE_FIREWALL_CMD=false

# firewall status
CONFIGURE_FIREWALL=false

# input validation regex's
email_regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"

####### Version checking ########

# define version using information from GitHub
get_latest_release() {
  curl --silent "https://api.github.com/repos/$1/releases/tags/$PANEL_VERSION" | # Get latest release from GitHub api
    grep '"tag_name":' |                                                         # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                                                 # Pluck JSON value
}

# pterodactyl version
echo "* Mengambil informasi rilis.."
PTERODACTYL_VERSION="$(get_latest_release "pterodactyl/panel")"

####### lib func #######

array_contains_element() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

valid_email() {
  [[ $1 =~ ${email_regex} ]]
}

invalid_ip() {
  ip route get "$1" >/dev/null 2>&1
  echo $?
}

####### Visual functions ########

print_error() {
  COLOR_RED='\033[0;31m'
  COLOR_NC='\033[0m'

  echo ""
  echo -e "* ${COLOR_RED}ERROR CUK${COLOR_NC}: $1"
  echo ""
}

print_warning() {
  COLOR_YELLOW='\033[1;33m'
  COLOR_NC='\033[0m'
  echo ""
  echo -e "* ${COLOR_YELLOW}WARNENG${COLOR_NC}: $1"
  echo ""
}

print_brake() {
  for ((n = 0; n < $1; n++)); do
    echo -n "#"
  done
  echo ""
}

hyperlink() {
  echo -e "\e]8;;${1}\a${1}\e]8;;\a"
}

##### User input functions ######

required_input() {
  local __resultvar=$1
  local result=''

  while [ -z "$result" ]; do
    echo -n "* ${2}"
    read -r result

    if [ -z "${3}" ]; then
      [ -z "$result" ] && result="${4}"
    else
      [ -z "$result" ] && print_error "${3}"
    fi
  done

  eval "$__resultvar="'$result'""
}

email_input() {
  local __resultvar=$1
  local result=''

  while ! valid_email "$result"; do
    echo -n "* ${2}"
    read -r result

    valid_email "$result" || print_error "${3}"
  done

  eval "$__resultvar="'$result'""
}

password_input() {
  local __resultvar=$1
  local result=''
  local default="$4"

  while [ -z "$result" ]; do
    echo -n "* ${2}"

    # modified from https://stackoverflow.com/a/22940001
    while IFS= read -r -s -n1 char; do
      [[ -z $char ]] && {
        printf '\n'
        break
      }                               # ENTER pressed; output \n and break.
      if [[ $char == $'\x7f' ]]; then # backspace was pressed
        # Only if variable is not empty
        if [ -n "$result" ]; then
          # Remove last char from output variable.
          [[ -n $result ]] && result=${result%?}
          # Erase '*' to the left.
          printf '\b \b'
        fi
      else
        # Add typed char to output variable.
        result+=$char
        # Print '*' in its stead.
        printf '*'
      fi
    done
    [ -z "$result" ] && [ -n "$default" ] && result="$default"
    [ -z "$result" ] && print_error "${3}"
  done

  eval "$__resultvar="'$result'""
}

ask_letsencrypt() {
  if [ "$CONFIGURE_UFW" == false ] && [ "$CONFIGURE_FIREWALL_CMD" == false ]; then
    print_warning "Let's Encrypt membutuhkan port 80/443 untuk dibuka! Anda telah memilih keluar dari konfigurasi firewall otomatis; gunakan ini dengan risiko Anda sendiri (jika port 80/443 ditutup, skrip akan gagal)!"
  fi

  echo -e -n "* Apakah Anda ingin mengonfigurasi HTTPS secara otomatis menggunakan Let's Encrypt? (y/N): "
  read -r CONFIRM_SSL

  if [[ "$CONFIRM_SSL" =~ [Yy] ]]; then
    CONFIGURE_LETSENCRYPT=true
    ASSUME_SSL=false
  fi
}

ask_assume_ssl() {
  echo "* Let's Encrypt tidak akan dikonfigurasi secara otomatis oleh skrip ini (pengguna memilih keluar)."
  echo "* Anda dapat 'mengasumsikan' Let's Encrypt, yang berarti skrip akan mengunduh konfigurasi nginx yang dikonfigurasi untuk menggunakan sertifikat Let's Encrypt tetapi skrip tidak akan mendapatkan sertifikat untuk Anda."
  echo "* Jika Anda mengasumsikan SSL dan tidak mendapatkan sertifikat, penginstalan Anda tidak akan berfungsi."
  echo -n "* Asumsikan SSL atau tidak? (y/N): "
  read -r ASSUME_SSL_INPUT

  [[ "$ASSUME_SSL_INPUT" =~ [Yy] ]] && ASSUME_SSL=true
  true
}

check_FQDN_SSL() {
  if [[ $(invalid_ip "$FQDN") == 1 && $FQDN != 'localhost' ]]; then
    SSL_AVAILABLE=true
  else
    print_warning "* Let's Encrypt tidak akan tersedia untuk alamat IP."
    echo "* Untuk menggunakan Let's Encrypt, Anda harus menggunakan nama domain yang valid."
  fi
}

ask_firewall() {
  case "$OS" in
  ubuntu | debian)
    echo -e -n "* Apakah Anda ingin mengonfigurasi UFW (firewall) secara otomatis? (y/N): "
    read -r CONFIRM_UFW

    if [[ "$CONFIRM_UFW" =~ [Yy] ]]; then
      CONFIGURE_UFW=true
      CONFIGURE_FIREWALL=true
    fi
    ;;
  centos)
    echo -e -n "* Apakah Anda ingin mengkonfigurasi firewall-cmd (firewall) secara otomatis? (y/N): "
    read -r CONFIRM_FIREWALL_CMD

    if [[ "$CONFIRM_FIREWALL_CMD" =~ [Yy] ]]; then
      CONFIGURE_FIREWALL_CMD=true
      CONFIGURE_FIREWALL=true
    fi
    ;;
  esac
}

####### OS check funtions #######

detect_distro() {
  if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$(echo "$ID" | awk '{print tolower($0)}')
    OS_VER=$VERSION_ID
  elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si | awk '{print tolower($0)}')
    OS_VER=$(lsb_release -sr)
  elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$(echo "$DISTRIB_ID" | awk '{print tolower($0)}')
    OS_VER=$DISTRIB_RELEASE
  elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS="debian"
    OS_VER=$(cat /etc/debian_version)
  elif [ -f /etc/SuSe-release ]; then
    # Older SuSE/etc.
    OS="SuSE"
    OS_VER="?"
  elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    OS="Red Hat/CentOS"
    OS_VER="?"
  else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    OS_VER=$(uname -r)
  fi

  OS=$(echo "$OS" | awk '{print tolower($0)}')
  OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
}

check_os_comp() {
  CPU_ARCHITECTURE=$(uname -m)
  if [ "${CPU_ARCHITECTURE}" != "x86_64" ]; then # check the architecture
    print_warning "Terdeteksi arsitektur CPU $CPU_ARCHITECTURE"
    print_warning "Menggunakan arsitektur selain 64 bit (x86_64) akan menyebabkan masalah."

    echo -e -n "* Apakah Anda yakin ingin melanjutkan? aku sih y (y/N):"
    read -r choice

    if [[ ! "$choice" =~ [Yy] ]]; then
      print_error "Instalasi dibatalkan!"
      exit 1
    fi
  fi

  case "$OS" in
  ubuntu)
    PHP_SOCKET="/run/php/php8.0-fpm.sock"
    [ "$OS_VER_MAJOR" == "18" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "20" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "22" ] && SUPPORTED=true
    ;;
  debian)
    PHP_SOCKET="/run/php/php8.0-fpm.sock"
    [ "$OS_VER_MAJOR" == "9" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "10" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "11" ] && SUPPORTED=true
    ;;
  centos)
    PHP_SOCKET="/var/run/php-fpm/pterodactyl.sock"
    [ "$OS_VER_MAJOR" == "7" ] && SUPPORTED=true
    [ "$OS_VER_MAJOR" == "8" ] && SUPPORTED=true
    ;;
  *)
    SUPPORTED=false
    ;;
  esac

  # exit if not supported
  if [ "$SUPPORTED" == true ]; then
    echo "* $OS $OS_VER is supported."
  else
    echo "* $OS $OS_VER is not supported"
    print_error "OS tidak didukung, awokawok :v"
    exit 1
  fi
}

##### Main installation functions #####

# Install composer
install_composer() {
  echo "* Installing composer.."
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  echo "* Composer installed!"
}

# Download pterodactyl files
ptdl_dl() {
  echo "* Mengunduh file panel pterodactyl .. "
  mkdir -p /var/www/pterodactyl
  cd /var/www/pterodactyl || exit

  curl -Lo panel.tar.gz "$PANEL_DL_URL"
  tar -xzvf panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/

  cp .env.example .env
  [ "$OS" == "centos" ] && export PATH=/usr/local/bin:$PATH
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

  php artisan key:generate --force
  echo "* File pterodactyl panel & composer dependencies terinstall!"
}

# Create a databse with user
create_database() {
  if [ "$OS" == "centos" ]; then
    # secure MariaDB
    echo "* Instalasi aman MariaDB. Berikut ini adalah default yang aman."
    echo "* Tetapkan kata sandi root? [Y/n] Y"
    echo "* Remove anonymous users? [Y/n] Y"
    echo "* Disallow root login remotely? [Y/n] Y"
    echo "* Remove test database and access to it? [Y/n] Y"
    echo "* Reload privilege tables now? [Y/n] Y"
    echo "*"

    [ "$OS_VER_MAJOR" == "7" ] && mariadb-secure-installation
    [ "$OS_VER_MAJOR" == "8" ] && mysql_secure_installation

    echo "* Skrip seharusnya meminta Anda untuk mengatur kata sandi root MySQL sebelumnya (jangan bingung dengan kata sandi pengguna basis data pterodactyl)"
    echo "* MySQL sekarang akan meminta Anda memasukkan kata sandi sebelum setiap perintah."

    echo "* Create MySQL user."
    mysql -u root -p -e "CREATE USER '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"

    echo "* Create database."
    mysql -u root -p -e "CREATE DATABASE ${MYSQL_DB};"

    echo "* Grant privileges."
    mysql -u root -p -e "GRANT ALL PRIVILEGES ON ${MYSQL_DB}.* TO '${MYSQL_USER}'@'127.0.0.1' WITH GRANT OPTION;"

    echo "* Flush privileges."
    mysql -u root -p -e "FLUSH PRIVILEGES;"
  else
    echo "* Performing MySQL queries.."

    echo "* Creating MySQL user.."
    mysql -u root -e "CREATE USER '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"

    echo "* Creating database.."
    mysql -u root -e "CREATE DATABASE ${MYSQL_DB};"

    echo "* Granting privileges.."
    mysql -u root -e "GRANT ALL PRIVILEGES ON ${MYSQL_DB}.* TO '${MYSQL_USER}'@'127.0.0.1' WITH GRANT OPTION;"

    echo "* Flushing privileges.."
    mysql -u root -e "FLUSH PRIVILEGES;"

    echo "* MySQL database created & configured!"
  fi
}

# Configure environment
configure() {
  app_url="http://$FQDN"
  [ "$ASSUME_SSL" == true ] && app_url="https://$FQDN"
  [ "$CONFIGURE_LETSENCRYPT" == true ] && app_url="https://$FQDN"

  # Fill in environment:setup automatically
  php artisan p:environment:setup \
    --author="$email" \
    --url="$app_url" \
    --timezone="$timezone" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="localhost" \
    --redis-pass="null" \
    --redis-port="6379" \
    --settings-ui=true

  # Fill in environment:database credentials automatically
  php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="$MYSQL_DB" \
    --username="$MYSQL_USER" \
    --password="$MYSQL_PASSWORD"

  # configures database
  php artisan migrate --seed --force

  # Create user account
  php artisan p:user:make \
    --email="$user_email" \
    --username="$user_username" \
    --name-first="$user_firstname" \
    --name-last="$user_lastname" \
    --password="$user_password" \
    --admin=1
}

# set the correct folder permissions depending on OS and webserver
set_folder_permissions() {
  # if os is ubuntu or debian, we do this
  case "$OS" in
  debian | ubuntu)
    chown -R www-data:www-data ./*
    ;;
  centos)
    chown -R nginx:nginx ./*
    ;;
  esac
}

# insert cronjob
insert_cronjob() {
  echo "* Installing cronjob.. "

  crontab -l | {
    cat
    echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
  } | crontab -

  echo "* Cronjob installed!"
}

install_pteroq() {
  echo "* Installing pteroq service.."

  curl -o /etc/systemd/system/pteroq.service $GITHUB_BASE_URL/configs/pteroq.service

  case "$OS" in
  debian | ubuntu)
    sed -i -e "s@<user>@www-data@g" /etc/systemd/system/pteroq.service
    ;;
  centos)
    sed -i -e "s@<user>@nginx@g" /etc/systemd/system/pteroq.service
    ;;
  esac

  systemctl enable pteroq.service
  systemctl start pteroq

  echo "* Installed pteroq!"
}

##### OS specific install functions #####

apt_update() {
  apt update -q -y && apt upgrade -y
}

yum_update() {
  yum -y update
}

dnf_update() {
  dnf -y upgrade
}

enable_services_debian_based() {
  systemctl enable mariadb
  systemctl enable redis-server
  systemctl start mariadb
  systemctl start redis-server
}

enable_services_centos_based() {
  systemctl enable mariadb
  systemctl enable nginx
  systemctl enable redis
  systemctl start mariadb
  systemctl start redis
}

selinux_allow() {
  setsebool -P httpd_can_network_connect 1 || true # these commands can fail OK
  setsebool -P httpd_execmem 1 || true
  setsebool -P httpd_unified 1 || true
}

ubuntu22_dep() {
  echo "* Installing dependencies for Ubuntu 22.."

  # Add "add-apt-repository" command
  apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg

  # Ubuntu universe repo
  add-apt-repository universe

  # Add PPA for PHP (we need 8.0 and focal only has 7.4)
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php

  # Update repositories list
  apt_update

  # Install Dependencies
  apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server redis cron

  # Enable services
  enable_services_debian_based

  echo "* Dependencies for Ubuntu installed!"
}

ubuntu20_dep() {
  echo "* Installing dependencies for Ubuntu 20.."

  # Add "add-apt-repository" command
  apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg

  # Ubuntu universe repo
  add-apt-repository universe

  # Add PPA for PHP (we need 8.0 and focal only has 7.4)
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php

  # Update repositories list
  apt_update

  # Install Dependencies
  apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server redis cron

  # Enable services
  enable_services_debian_based

  echo "* Dependencies for Ubuntu installed!"
}

ubuntu18_dep() {
  echo "* Installing dependencies for Ubuntu 18.."

  # Add "add-apt-repository" command
  apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg

  # Ubuntu universe repo
  add-apt-repository universe

  # Add PPA for PHP (we need 8.0 and bionic only has 7.2)
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php

  # Add the MariaDB repo (bionic has mariadb version 10.1 and we need newer than that)
  curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

  # Update repositories list
  apt_update

  # Install Dependencies
  apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server redis cron

  # Enable services
  enable_services_debian_based

  echo "* Dependencies for Ubuntu installed!"
}

debian_stretch_dep() {
  echo "* Installing dependencies for Debian 8/9.."

  # MariaDB need dirmngr
  apt -y install dirmngr

  # install PHP 8.0 using sury's repo instead of PPA
  apt install ca-certificates apt-transport-https lsb-release -y
  wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list

  # Add the MariaDB repo (oldstable has mariadb version 10.1 and we need newer than that)
  curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash

  # Update repositories list
  apt_update

  # Install Dependencies
  apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx curl tar unzip git redis-server cron

  # Enable services
  enable_services_debian_based

  echo "* Dependencies for Debian 8/9 installed!"
}

debian_buster_dep() {
  echo "* Installing dependencies for Debian 10.."

  # MariaDB need dirmngr
  apt -y install dirmngr

  # install PHP 8.0 using sury's repo instead of default 7.2 package (in buster repo)
  # this guide shows how: https://vilhelmprytz.se/2018/08/22/install-php72-on-Debian-8-and-9.html
  apt install ca-certificates apt-transport-https lsb-release -y
  wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list

  # Update repositories list
  apt_update

  # install dependencies
  apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx curl tar unzip git redis-server cron

  # Enable services
  enable_services_debian_based

  echo "* Dependencies for Debian 10 installed!"
}

debian_dep() {
  echo "* Installing dependencies for Debian 11.."

  # MariaDB need dirmngr
  apt -y install dirmngr

  # install PHP 8.0 using sury's repo instead of default 7.2 package (in buster repo)
  # this guide shows how: https://vilhelmprytz.se/2018/08/22/install-php72-on-Debian-8-and-9.html
  apt install ca-certificates apt-transport-https lsb-release -y
  wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list

  # Update repositories list
  apt_update

  # install dependencies
  apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx curl tar unzip git redis-server cron

  # Enable services
  enable_services_debian_based

  echo "* Dependencies for Debian 11 installed!"
}

centos7_dep() {
  echo "* Installing dependencies for CentOS 7.."

  # SELinux tools
  yum install -y policycoreutils policycoreutils-python selinux-policy selinux-policy-targeted libselinux-utils setroubleshoot-server setools setools-console mcstrans

  # Add remi repo (php8.0)
  yum install -y epel-release http://rpms.remirepo.net/enterprise/remi-release-7.rpm
  yum install -y yum-utils
  yum-config-manager -y --disable remi-php54
  yum-config-manager -y --enable remi-php80
  yum_update

  # Install MariaDB
  curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

  # Install dependencies
  yum -y install php php-common php-tokenizer php-curl php-fpm php-cli php-json php-mysqlnd php-mcrypt php-gd php-mbstring php-pdo php-zip php-bcmath php-dom php-opcache mariadb-server nginx curl tar zip unzip git redis

  # Enable services
  enable_services_centos_based

  # SELinux (allow nginx and redis)
  selinux_allow

  echo "* Dependencies for CentOS installed!"
}

centos8_dep() {
  echo "* Installing dependencies for CentOS 8.."

  # SELinux tools
  dnf install -y policycoreutils selinux-policy selinux-policy-targeted setroubleshoot-server setools setools-console mcstrans

  # add remi repo (php8.0)
  dnf install -y epel-release http://rpms.remirepo.net/enterprise/remi-release-8.rpm
  dnf module enable -y php:remi-8.0
  dnf_update

  dnf install -y php php-common php-fpm php-cli php-json php-mysqlnd php-gd php-mbstring php-pdo php-zip php-bcmath php-dom php-opcache

  # MariaDB (use from official repo)
  dnf install -y mariadb mariadb-server

  # Other dependencies
  dnf install -y nginx curl tar zip unzip git redis

  # Enable services
  enable_services_centos_based

  # SELinux (allow nginx and redis)
  selinux_allow

  echo "* Dependencies for CentOS installed!"
}

##### OTHER OS SPECIFIC FUNCTIONS #####

centos_php() {
  curl -o /etc/php-fpm.d/www-pterodactyl.conf $GITHUB_BASE_URL/configs/www-pterodactyl.conf

  systemctl enable php-fpm
  systemctl start php-fpm
}

firewall_ufw() {
  apt install -y ufw

  echo -e "\n* Enabling Uncomplicated Firewall (UFW)"
  echo "* Opening port 22 (SSH), 80 (HTTP) and 443 (HTTPS)"

  # pointing to /dev/null silences the command output
  ufw allow ssh >/dev/null
  ufw allow http >/dev/null
  ufw allow https >/dev/null

  ufw --force enable
  ufw --force reload
  ufw status numbered | sed '/v6/d'
}

firewall_firewalld() {
  echo -e "\n* Enabling firewall_cmd (firewalld)"
  echo "* Opening port 22 (SSH), 80 (HTTP) and 443 (HTTPS)"

  # Install
  [ "$OS_VER_MAJOR" == "7" ] && yum -y -q install firewalld >/dev/null
  [ "$OS_VER_MAJOR" == "8" ] && dnf -y -q install firewalld >/dev/null

  # Enable
  systemctl --now enable firewalld >/dev/null # Enable and start

  # Configure
  firewall-cmd --add-service=http --permanent -q  # Port 80
  firewall-cmd --add-service=https --permanent -q # Port 443
  firewall-cmd --add-service=ssh --permanent -q   # Port 22
  firewall-cmd --reload -q                        # Enable firewall

  echo "* Firewall-cmd installed"
  print_brake 70
}

letsencrypt() {
  FAILED=false

  # Install certbot
  case "$OS" in
  debian | ubuntu)
    apt-get -y install certbot python3-certbot-nginx
    ;;
  centos)
    [ "$OS_VER_MAJOR" == "7" ] && yum -y -q install certbot python-certbot-nginx
    [ "$OS_VER_MAJOR" == "8" ] && dnf -y -q install certbot python3-certbot-nginx
    ;;
  esac

  # Obtain certificate
  certbot --nginx --redirect --no-eff-email --email "$email" -d "$FQDN" || FAILED=true

  # Check if it succeded
  if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == true ]; then
    print_warning "Proses mendapatkan sertifikat Let's Encrypt gagal!"
    echo -n "* Masih mengasumsikan SSL? (y/N): "
    read -r CONFIGURE_SSL

    if [[ "$CONFIGURE_SSL" =~ [Yy] ]]; then
      ASSUME_SSL=true
      CONFIGURE_LETSENCRYPT=false
      configure_nginx
    else
      ASSUME_SSL=false
      CONFIGURE_LETSENCRYPT=false
    fi
  fi
}

##### WEBSERVER CONFIGURATION FUNCTIONS #####

configure_nginx() {
  echo "* Configuring nginx .."

  if [ $ASSUME_SSL == true ] && [ $CONFIGURE_LETSENCRYPT == false ]; then
    DL_FILE="nginx_ssl.conf"
  else
    DL_FILE="nginx.conf"
  fi

  if [ "$OS" == "centos" ]; then
    # remove default config
    rm -rf /etc/nginx/conf.d/default

    # download new config
    curl -o /etc/nginx/conf.d/pterodactyl.conf $GITHUB_BASE_URL/configs/$DL_FILE

    # replace all <domain> places with the correct domain
    sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/conf.d/pterodactyl.conf

    # replace all <php_socket> places with correct socket "path"
    sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" /etc/nginx/conf.d/pterodactyl.conf
  else
    # remove default config
    rm -rf /etc/nginx/sites-enabled/default

    # download new config
    curl -o /etc/nginx/sites-available/pterodactyl.conf $GITHUB_BASE_URL/configs/$DL_FILE

    # replace all <domain> places with the correct domain
    sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-available/pterodactyl.conf

    # replace all <php_socket> places with correct socket "path"
    sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" /etc/nginx/sites-available/pterodactyl.conf

    # on debian 9, TLS v1.3 is not supported (see #76)
    [ "$OS" == "debian" ] && [ "$OS_VER_MAJOR" == "9" ] && sed -i 's/ TLSv1.3//' /etc/nginx/sites-available/pterodactyl.conf

    # enable pterodactyl
    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
  fi

  if [ "$ASSUME_SSL" == false ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
    systemctl restart nginx
  fi

  echo "* nginx configured!"
}

##### MAIN FUNCTIONS #####

perform_install() {
  echo "* Memulai penginstalan.. ini mungkin memakan waktu cukup lama!"

  case "$OS" in
  debian | ubuntu)
    apt_update

    [ "$CONFIGURE_UFW" == true ] && firewall_ufw

    if [ "$OS" == "ubuntu" ]; then
      [ "$OS_VER_MAJOR" == "22" ] && ubuntu22_dep
      [ "$OS_VER_MAJOR" == "20" ] && ubuntu20_dep
      [ "$OS_VER_MAJOR" == "18" ] && ubuntu18_dep
    elif [ "$OS" == "debian" ]; then
      [ "$OS_VER_MAJOR" == "9" ] && debian_stretch_dep
      [ "$OS_VER_MAJOR" == "10" ] && debian_buster_dep
      [ "$OS_VER_MAJOR" == "11" ] && debian_dep
    fi
    ;;

  centos)
    [ "$OS_VER_MAJOR" == "7" ] && yum_update
    [ "$OS_VER_MAJOR" == "8" ] && dnf_update

    [ "$CONFIGURE_FIREWALL_CMD" == true ] && firewall_firewalld

    [ "$OS_VER_MAJOR" == "7" ] && centos7_dep
    [ "$OS_VER_MAJOR" == "8" ] && centos8_dep
    ;;
  esac

  [ "$OS" == "centos" ] && centos_php
  install_composer
  ptdl_dl
  create_database
  configure
  set_folder_permissions
  insert_cronjob
  install_pteroq
  configure_nginx
  [ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt
  true
}

main() {
  # check if we can detect an already existing installation
  if [ -d "/var/www/pterodactyl" ]; then
    print_warning "Skrip telah mendeteksi bahwa Anda sudah memiliki panel Pterodactyl di sistem Anda! Anda tidak dapat menjalankan skrip beberapa kali, itu akan gagal!"
    echo -e -n "* Apakah Anda yakin ingin melanjutkan? (y/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
      print_error "Installation aborted!"
      exit 1
    fi
  fi

  # detect distro
  detect_distro

  print_brake 70
  echo "* Pterodactyl panel installation script @ $SCRIPT_RELEASE"
  echo "*"
  echo "* Original Script By @vilhelmprytz (Vilhelm Prytz)"
  echo "* di Recode oleh @fokusdotid (Fokus ID)"
  echo "*"
  echo "* Jika ingin menggunakan script resmi, silahkan kunjungi:"
  echo "* https://github.com/vilhelmprytz/pterodactyl-installer"
  echo "*"
  echo "* Made with ❤️ by @fokusdotid (Fokus ID)"
  echo "* https://github.com/fokusdotid/pterodactyl-installer"
  echo "*"
  echo "* This script is not associated with the official Pterodactyl Project."
  echo "*"
  echo "* Running $OS version $OS_VER."
  echo "* Latest pterodactyl/panel is $PTERODACTYL_VERSION"
  print_brake 70

  # checks if the system is compatible with this installation script
  check_os_comp

  # set database credentials
  print_brake 72
  echo "* Konfigurasi Database."
  echo ""
  echo "* Ini akan menjadi kredensial yang digunakan untuk komunikasi antara MySQL"
  echo "* database dan panel. Anda tidak perlu membuat database"
  echo "* sebelum menjalankan skrip ini, skrip akan melakukannya untuk Anda."
  echo ""

  MYSQL_DB="-"
  while [[ "$MYSQL_DB" == *"-"* ]]; do
    required_input MYSQL_DB "Nama database (panel): " "" "panel"
    [[ "$MYSQL_DB" == *"-"* ]] && print_error "Nama database tidak boleh mengandung tanda hubung"
  done

  MYSQL_USER="-"
  while [[ "$MYSQL_USER" == *"-"* ]]; do
    required_input MYSQL_USER "Database username (pterodactyl): " "" "pterodactyl"
    [[ "$MYSQL_USER" == *"-"* ]] && print_error "Database username tidak boleh mengandung tanda hubung"
  done

  # MySQL password input
  rand_pw=$(
    tr -dc 'A-Za-z0-9!"#$%&()*+,-./:;<=>?@[\]^_`{|}~' </dev/urandom | head -c 64
    echo
  )
  password_input MYSQL_PASSWORD "Kata sandi (tekan enter untuk menggunakan kata sandi yang dibuat secara acak): " "MySQL password cannot be empty" "$rand_pw"

  readarray -t valid_timezones <<<"$(curl -s $GITHUB_BASE_URL/configs/valid_timezones.txt)"
  echo "* Daftar zona waktu yang valid di sini $(hyperlink "https://www.php.net/manual/en/timezones.php")"

  while [ -z "$timezone" ]; do
    echo -n "* Pilih zona waktu [Europe/Stockholm]: "
    read -r timezone_input

    array_contains_element "$timezone_input" "${valid_timezones[@]}" && timezone="$timezone_input"
    [ -z "$timezone_input" ] && timezone="Europe/Stockholm" # because köttbullar!
  done

  email_input email "Berikan alamat email yang akan digunakan untuk mengonfigurasi Let's Encrypt dan Pterodactyl: " "Email cannot be empty or invalid"

  # Initial admin account
  email_input user_email "Alamat email untuk akun admin: " "Email cannot be empty or invalid"
  required_input user_username "Nama pengguna untuk akun admin: " "Username cannot be empty"
  required_input user_firstname "Nama depan untuk akun admin: " "Name cannot be empty"
  required_input user_lastname "Nama belakang untuk akun admin: " "Name cannot be empty"
  password_input user_password "Kata sandi untuk akun admin: " "Password cannot be empty"

  print_brake 72

  # set FQDN
  while [ -z "$FQDN" ]; do
    echo -n "* Set the FQDN of this panel (panel.example.com): "
    read -r FQDN
    [ -z "$FQDN" ] && print_error "FQDN cannot be empty"
  done

  # Check if SSL is available
  check_FQDN_SSL

  # Ask if firewall is needed
  ask_firewall

  # Only ask about SSL if it is available
  if [ "$SSL_AVAILABLE" == true ]; then
    # Ask if letsencrypt is needed
    ask_letsencrypt
    # If it's already true, this should be a no-brainer
    [ "$CONFIGURE_LETSENCRYPT" == false ] && ask_assume_ssl
  fi

  # verify FQDN if user has selected to assume SSL or configure Let's Encrypt
  [ "$CONFIGURE_LETSENCRYPT" == true ] || [ "$ASSUME_SSL" == true ] && bash <(curl -s $GITHUB_BASE_URL/lib/verify-fqdn.sh) "$FQDN" "$OS"

  # summary
  summary

  # confirm installation
  echo -e -n "\n* Konfigurasi selesai. Lanjutkan dengan instalasi? (y/N): "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Yy] ]]; then
    perform_install
  else
    # run welcome script again
    print_error "Installation aborted."
    exit 1
  fi
}

summary() {
  print_brake 62
  echo "* Pterodactyl panel $PTERODACTYL_VERSION with nginx on $OS"
  echo "* Nama Database: $MYSQL_DB"
  echo "* Pengguna Database: $MYSQL_USER"
  echo "* Kata Sandi Database: (censored)"
  echo "* Zona waktu: $timezone"
  echo "* Email: $email"
  echo "* Email Pengguna: $user_email"
  echo "* Username: $user_username"
  echo "* Nama depan: $user_firstname"
  echo "* Nama belakang: $user_lastname"
  echo "* Katasandi pengguna: (censored)"
  echo "* Hostname/FQDN: $FQDN"
  echo "* Configure Firewall? $CONFIGURE_FIREWALL"
  echo "* Configure Let's Encrypt? $CONFIGURE_LETSENCRYPT"
  echo "* Asumsikan SSL? $ASSUME_SSL"
  echo "*"
  echo "* Made with ❤️ by @fokusdotid (Fokus ID)"
  echo "* https://github.com/fokusdotid/pterodactyl-installer"
  print_brake 62
}

goodbye() {
  print_brake 62
  echo "* Panel installation completed"
  echo "*"

  [ "$CONFIGURE_LETSENCRYPT" == true ] && echo "* Your panel should be accessible from $(hyperlink "$app_url")"
  [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ] && echo "* You have opted in to use SSL, but not via Let's Encrypt automatically. Your panel will not work until SSL has been configured."
  [ "$ASSUME_SSL" == false ] && [ "$CONFIGURE_LETSENCRYPT" == false ] && echo "* Your panel should be accessible from $(hyperlink "$app_url")"

  echo "*"
  echo "* Installation is using nginx on $OS"
  echo "* Thank you for using this script."
  echo "*"
  echo "* Made with ❤️ by @fokusdotid (Fokus ID)"
  echo "* https://github.com/fokusdotid/pterodactyl-installer"
  [ "$CONFIGURE_FIREWALL" == false ] && echo -e "* ${COLOR_RED}Note${COLOR_NC}: If you haven't configured the firewall: 80/443 (HTTP/HTTPS) is required to be open!"
  print_brake 62
}

# run script
main
goodbye
