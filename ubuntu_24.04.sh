#!/bin/bash
PATH="/bin:/usr/bin:/usr/sbin:$PATH"
# -*- coding: utf-8 -*-
# exit on first error aka exit <=1
set -eo pipefail
# Variables
script_version="v0.0.1"
shortname="ubuntu_24.04"
echo -e ""
echo -e "${bold}${blue}i-doit for ${shortname} is beeing installed${default}"
##
## Configuration
##
## You **should not** edit these settings.
## You will be asked for your preferred settings.
## To overwrite these settings export them before running this script.
## For example:
##     export MARIADB_INNODB_BUFFER_POOL_SIZE=2G
: "${MARIADB_HOSTNAME:="localhost"}"
: "${MARIADB_SUPERUSER_USERNAME:="root"}"
: "${MARIADB_SUPERUSER_PASSWORD:="idoit"}"
: "${MARIADB_INNODB_BUFFER_POOL_SIZE:="1G"}"
: "${IDOIT_ADMIN_CENTER_PASSWORD:="admin"}"
: "${MARIADB_IDOIT_USERNAME:="idoit"}"
: "${MARIADB_IDOIT_PASSWORD:="idoit"}"
: "${IDOIT_DEFAULT_TENANT:="CMDB"}"
: "${INSTALL_DIR:="/var/www/html"}"
: "${UPDATE_FILE_PRO:="https://i-doit.com/updates.xml"}"
: "${UPDATE_FILE_OPEN:="https://i-doit.org/updates.xml"}"
: "${UPDATE_FILE_EVAL:="https://eval-downloads.i-doit.com/idoit-eval-automatic.zip"}"
: "${SCRIPT_SETTINGS:="/etc/i-doit/i-doit.sh"}"
: "${CONSOLE_BIN:="/usr/local/bin/idoit"}"
: "${JOBS_BIN:="/usr/local/bin/idoit-jobs"}"
: "${CRON_FILE:="/etc/cron.d/i-doit"}"
: "${BACKUP_DIR:="/var/backups/i-doit"}"
: "${RECOMMENDED_PHP_VERSION:="8.0"}"
: "${RECOMMENDED_MARIADB_VERSION:="10.6"}"

# Needed settings
APACHE_CONFIG_FILE="/etc/apache2/sites-available/i-doit.conf"
PHP_FPM_SOCKET="/var/run/php-fpm/php8.3-fpm.sock"
PHP_FPM_UNIT="php8.3-fpm"
PHP_CONFIG_FILE="/etc/php/8.3/mods-available/i-doit.ini"
INSTALLDIR="/var/www/html/i-doit"
# Update and upgrade system packages
update_and_install_packages() {
    trap_on
    commandaction="Updating and Installing packages"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator
    
    # Update
    if [ "$DEBUG" -ge 1 ]; then
        sudo apt-get update --yes || print_fail
    else
        sudo apt-get update -qq --yes || print_fail
        print_ok_nl "apt update"
    fi

    # upgrade
    if [ "$DEBUG" -ge 1 ]; then
        sudo apt-get upgrade --yes || print_fail
    else
        sudo apt-get upgrade -qq --yes || print_fail
        print_ok_nl "apt upgrade"
    fi

    # trap off because it could fail some installation dings
    trap_off

    # Install dependencies
    if [ "$DEBUG" -ge 1 ]; then
    for item in apache2 libapache2-mod-fcgid mariadb-client mariadb-server memcached unzip sudo moreutils php php-{bcmath,cli,common,curl,fpm,gd,imagick,json,ldap,mbstring,memcached,mysql,pgsql,soap,xml,zip}; do
        sudo apt-get install -y "$item"
        print_ok_nl "${lightblue}${item}${default} installed"
    done
    else
    for item in apache2 libapache2-mod-fcgid mariadb-client mariadb-server memcached unzip sudo moreutils php php-{bcmath,cli,common,curl,fpm,gd,imagick,json,ldap,mbstring,memcached,mysql,pgsql,soap,xml,zip}; do
        sudo apt-get install -qq -y "$item"
        print_ok_nl "${lightblue}${item}${default} installed"
    done
    fi
    trap_off
    print_complete "${bold}${green}${commandaction}${default}"
}

get_binaries() {
    commandaction="Check available binaries"
    trap_on
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator

    declare -A binaries
    # List of binaries to check
    local binaries_list=("mariadb" "sudo" "unzip" "wget" "php" "systemctl" "memcached" "date" "curl" "a2ensite" "a2dissite" "a2enmod" "a2dismod")
    
    commandaction="Binary"
    # Loop to find each binary
    for binary in "${binaries_list[@]}"; do
        binaries[$binary]=$(command -v "$binary" || print_fail "${red}${binary}${default} not found")
        print_ok_nl "Found binary ${lightblue}${binary}${default} at ${binaries[$binary]}"
    done
    commandaction="Check available binaries"
    trap_off
    print_complete "${bold}${green}${commandaction}${default}"
}

# seems not needed anymore <https://mariadb.com/kb/en/authentication-from-mariadb-10-4/>
secure_installation() {
    trap_on
    commandaction="Securing MySQL installation"
    mysql_secure_installation
    print_complete "${bold}${green}${commandaction}${default}"
    trap_off
}

download_and_extract_idoit() {
    trap_on
    commandaction="Download and extract i-doit"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator

    local url="https://login.i-doit.com/downloads/idoit-31.zip"
    local output="/tmp/idoit-311.zip"
    download_file "$url" "$output"
    extract_zip "$output" "$INSTALLDIR"
    chown -R "${APACHEUSER}":"${APACHEUSER}" "${INSTALLDIR}"

    trap_off
    print_complete "${bold}${green}${commandaction}${default}"
}

conf_php_fpm() {
    trap_on
    commandaction="Configure PHP-FPM"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator
    if [ "$DEBUG" -ge 1 ]; then
        sudo a2enmod proxy_fcgi
    else
        sudo a2enmod -q proxy_fcgi
    fi

    if [ "$DEBUG" -ge 1 ]; then
        sudo touch ${PHP_CONFIG_FILE}
    else
        sudo touch ${PHP_CONFIG_FILE} &> /dev/null || print_fail_nl
    fi

    cat <<EOF >"$PHP_CONFIG_FILE" || print_fail_nl "Unable to create and edit file '${PHP_CONFIG_FILE}'"
allow_url_fopen = Yes
file_uploads = On
magic_quotes_gpc = Off
max_execution_time = 300
max_file_uploads = 42
max_input_time = 60
max_input_vars = 10000
memory_limit = 256M
post_max_size = 128M
register_argc_argv = On
register_globals = Off
short_open_tag = On
upload_max_filesize = 128M
display_errors = Off
display_startup_errors = Off
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
log_errors = On
default_charset = "UTF-8"
default_socket_timeout = 60
date.timezone = Europe/Berlin
session.gc_maxlifetime = 604800
session.cookie_lifetime = 0
mysqli.default_socket = ${MARIADB_SOCKET}
EOF
    print_ok_nl "Created PHP config file ${PHP_CONFIG_FILE}"

    if [ "$DEBUG" -ge 1 ]; then
        sudo phpenmod i-doit
    else
        sudo phpenmod -q i-doit
    fi
    print_ok_nl "phpenmod i-doit"

    if [ "$DEBUG" -ge 1 ]; then
        sudo systemctl restart "$PHP_FPM_UNIT"
    else
        sudo systemctl -q restart "$PHP_FPM_UNIT"
    fi
    print_ok_nl "Restart ${PHP_FPM_UNIT}"

    trap_off
    print_complete "${bold}${green}${commandaction}${default}"
}

conf_apache() {
    trap_on
    commandaction="Configuring Apache2"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator
    hostname="$(cat /etc/hostname)"

    if [ "$DEBUG" -ge 1 ]; then
        sudo touch ${APACHE_CONFIG_FILE}
    else
        sudo touch ${APACHE_CONFIG_FILE} &> /dev/null || print_fail_nl
    fi
    print_ok_nl "Created ${APACHE_CONFIG_FILE}"

    cat << EOF >${APACHE_CONFIG_FILE} || print_fail_nl
ServerName ${hostname}

<VirtualHost *:80>
    ServerAdmin i-doit@example.net

    DirectoryIndex index.php
    DocumentRoot ${INSTALL_DIR}/

    <Directory ${INSTALL_DIR}/>
        AllowOverride None

        ${APACHE_HTACCESS_SUBSTITUTION}
    </Directory>

    TimeOut 600
    ProxyTimeout 600

    <FilesMatch "\\.php$">
        <If "-f %{REQUEST_FILENAME}">
            SetHandler "proxy:unix:${PHP_FPM_SOCKET}|fcgi://localhost"
        </If>
    </FilesMatch>

    LogLevel warn
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
    print_ok_nl "Created apache2 config ${APACHE_CONFIG_FILE}"

    if [ "$DEBUG" -ge 1 ]; then
        sudo a2ensite i-doit
    else
        sudo a2ensite -q i-doit
    fi
    print_ok_nl "a2ensite idoit"

    if [ "$DEBUG" -ge 1 ]; then
        sudo a2enmod rewrite
    else
        sudo a2enmod -q rewrite
    fi
    print_ok_nl "a2enmod rewrite"

    if [ "$DEBUG" -ge 1 ]; then
        sudo systemctl restart apache2
    else
        sudo systemctl -q restart apache2
    fi
    print_ok_nl "Restart apache2"
    trap_off
    print_complete "${bold}${green}${commandaction}${default}"
}

conf_mariadb() {
    trap_on
    commandaction="Configuring MySQL"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator

    pass="$({
            choose '!@#$%^\&'
            choose '0123456789'
            choose 'abcdefghijklmnopqrstuvwxyz'
            choose 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
            for i in $( seq 1 $(( 4 + RANDOM % 8 )) )
            do
                choose '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
            done
            } | sort -R | awk '{printf "%s",$1}' )" || print_fail_nl
    print_ok_nl "Created random password ${pass}"
    echo "$pass"

    pass2="$(pass_gen | awk '{printf "%s",$1}')"
    echo "$pass2"

    if [ "$DEBUG" -ge 1 ]; then
        sudo mysql -e"ALTER USER root@localhost IDENTIFIED VIA mysql_native_password USING PASSWORD('${pass}')"
    else
        sudo mysql -e"ALTER USER root@localhost IDENTIFIED VIA mysql_native_password USING PASSWORD('${pass}')"
    fi


    trap_off
    print_complete "${bold}${green}${commandaction}${default}"
}

setup_cron() {
    trap_on
    commandaction="Setting up cron job"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator

    echo "0 2 * * * root ${INSTALLDIR}/backup.sh" >> /etc/crontab
    trap_off
    print_complete "${bold}${green}${commandaction}${default}"
}

# sudo apt update
# sudo apt upgrade -y

# # Install necessary packages
# sudo apt install -y apache2 mysql-server php libapache2-mod-php php-mysql php-xml php-mbstring curl unzip

# # Secure MySQL installation
# sudo mysql_secure_installation

# # Create i-doit database and user
# sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE ${IDOIT_DB_NAME};"
# sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER '${IDOIT_DB_USER}'@'localhost' IDENTIFIED BY '${IDOIT_DB_PASSWORD}';"
# sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${IDOIT_DB_NAME}.* TO '${IDOIT_DB_USER}'@'localhost';"
# sudo mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"

# # Download and extract i-doit
# curl -o /tmp/idoit.zip -L "https://login.i-doit.com/download/idoit-31.zip"
# sudo unzip /tmp/idoit.zip -d /var/www/html/
# sudo mv /var/www/html/idoit-"${IDOIT_VERSION}" /var/www/html/idoit

# # Set permissions
# sudo chown -R ${APACHE_USER}:${APACHE_USER} /var/www/html/idoit
# sudo chmod -R 755 /var/www/html/idoit

# # Configure Apache
# sudo bash -c 'cat <<EOF > /etc/apache2/sites-available/idoit.conf
# <VirtualHost *:80>
# ServerAdmin webmaster@localhost
# DocumentRoot /var/www/html/idoit
# ErrorLog \${APACHE_LOG_DIR}/error.log
# CustomLog \${APACHE_LOG_DIR}/access.log combined
# </VirtualHost>
# EOF'

# sudo a2ensite idoit.conf
# sudo a2enmod rewrite
# sudo systemctl restart apache2

main() {
    commandaction="i-doit installation on Ubuntu 24.04"
    trap_on 
    update_and_install_packages
    get_binaries 
    #secure_installation 
    download_and_extract_idoit 
    conf_php_fpm
    conf_apache 
    conf_mariadb 
    setup_cron 
    
    success_banner
    support_list
}
# =============
# main script

main "$@"
exit 0
# =============


