#!/bin/bash
# -*- coding: utf-8 -*-
PATH="/bin:/usr/bin:/usr/sbin:$PATH"

# The exit status of a pipeline is the exit status of the last command in the pipeline
set -eo pipefail
# Variables
install_ubuntu_2204_version="v0.0.2"
shortname="ubuntu_22.04"
echo -e ""
echo -e "${bold}${blue}i-doit for ${shortname} version ${install_ubuntu_2204_version} is beeing installed${default}"
script_log "Start installing i-doit on ${shortname} with script version ${install_ubuntu_2204_version} " >> "${LOGFILE}"

## Configuration
##
## You **should not** edit these settings.

# Needed settings
LOGFILE="/tmp/idoit-install.log"
INSTALLDIR="/var/www/html/i-doit"
APACHE_CONFIG_FILE="/etc/apache2/sites-available/i-doit.conf"
APACHE_USER="www-data"
APACHE_GROUP="www-data"
PHP_FPM_SOCKET="/var/run/php/php8.1-fpm.sock"
PHP_FPM_UNIT="php8.1-fpm"
PHP_CONFIG_FILE="/etc/php/8.1/mods-available/i-doit.ini"
MARIADB_CONFIG_FILE="/etc/mysql/mariadb.conf.d/99-i-doit.cnf"
MARIADB_SUPERUSER_USERNAME="root"
MARIADB_IDOIT_USERNAME="idoit"
MARIADB_HOSTNAME="localhost"
TENANT_NAME="Your company name"
##

# If a ERROR or WARN or FAIL occur save to array and display at the end
#TODO

trap 'print_error "An error occurred on line $LINENO while executing: $BASH_COMMAND"; exit 1' ERR

# Update and upgrade system packages
update_and_install_packages() {
    
    commandaction="Updating and Installing packages"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator
    
    # Update
    if [ "$DEBUG" -ge 1 ]; then
        sudo apt-get update --yes || print_warn
    else
        sudo apt-get update -qq --yes || print_warn
        print_ok "apt update"
    fi

    # upgrade
    if [ "$DEBUG" -ge 1 ]; then
        sudo apt-get upgrade -y || print_warn
    else
        sudo apt-get upgrade -qq -y || print_warn
        print_ok "apt upgrade"
    fi

    # TODO yes or no full-upgrade?
    #if [ "$DEBUG" -ge 1 ]; then
    #    sudo apt-get full-upgrade -y || print_warn
    #else
    #    sudo apt-get full-upgrade -qq -y || print_warn
    #    print_ok "apt full-upgrade"
    #fi


    # Install dependencies
    if [ "$DEBUG" -ge 1 ]; then
    for item in apache2 libapache2-mod-fcgid mariadb-client mariadb-server memcached unzip sudo moreutils wget php php-{bcmath,cli,common,curl,fpm,gd,imagick,json,ldap,mbstring,memcached,mysql,pgsql,soap,xml,zip}; do
        print_info "${lightblue}${item}${default} is beeing installed"
        sudo apt-get install  -y "$item"
        if [ $? -ge 1 ]; then
            print_error "${item}"
        fi
        print_ok "${green}${item}${default} installed"
    done
    else
    for item in apache2 libapache2-mod-fcgid mariadb-client mariadb-server memcached unzip sudo moreutils wget php php-{bcmath,cli,common,curl,fpm,gd,imagick,json,ldap,mbstring,memcached,mysql,pgsql,soap,xml,zip}; do
        sudo apt-get install -qq -y "$item" &>/dev/null
        if [ $? -ge 1 ]; then 
            print_error "${item}"
        fi
        print_ok "${lightblue}${item}${default} installed"
    done
    fi
    
    echo -e "------------------------------"
    print_complete "${bold}${green}${commandaction} ${default}"
    echo ""
}

get_binaries() {
    commandaction="Check available binaries"
    
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
        print_ok "Found binary ${lightblue}${binary}${default} at ${binaries[$binary]}"
    done
    echo -e "------------------------------"
    print_complete "${bold}${green}${commandaction} ${default}"
    echo ""
}

# checks if the application is already extracted, downloads the ZIP file if needed and extracts it to the installation directory
download_and_extract_idoit() {
    local commandaction="Download and extract i-doit"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator

    get_latest_idoit_version
    local debug_mode=${DEBUG:-0}  # Default to 0 if DEBUG is not set
    local idoit_url="https://login.i-doit.com/downloads/idoit-${latest_version}.zip"
    local idoit_zip="idoit-${latest_version}.zip"
    local INSTALLDIR=${INSTALLDIR:-"/var/www/html/idoit/"}  # Default installation directory
    local output="${TEMPDIR}/$idoit_zip"


    # Check if i-doit is already extracted
    if [ -d "${INSTALLDIR}/src" ]; then
        print_info "i-doit directory already exist at ${INSTALLDIR}"
    else
    # Download the ZIP file if it doesn't exist
        print_info "Downloading i-doit ${latest_version} from ${idoit_url}"
        download_file "$idoit_url" "$output"
        if [ $? -ne 0 ]; then
            print_fail "Failed to download ${idoit_url}"
        fi

        # Extract the ZIP file
        print_info "Extracting $output to $INSTALLDIR"
        extract_zip "$output" "$INSTALLDIR"
        if [ $? -ne 0 ]; then
            print_fail "Failed to extract ${idoit_zip}"
        fi

        # Change ownership of extracted files
        print_info "Changing ownership of ${INSTALLDIR} to ${APACHE_USER}:${APACHE_GROUP}"
        chown -R "${APACHE_USER}:${APACHE_GROUP}" "${INSTALLDIR}"
        if [ $? -ne 0 ]; then
            print_fail "Failed to change ownership of ${INSTALLDIR}"
            error=1
        fi
    fi

    
    echo -e "------------------------------"
    print_complete "${bold}${green}${commandaction} ${default}"
    echo ""
}

# Create the PHP configuration file, enable i-doit module, restart the PHP-FPM 
conf_php_fpm() {
    local commandaction="Configure PHP"
    local debug_mode=${DEBUG:-0}  # Default to 0 if DEBUG is not set
    local PHP_CONFIG_FILE="/etc/php/8.1/mods-available/i-doit.ini"  # Default config file path
    local PHP_FPM_UNIT="php8.1-fpm"  # Default PHP-FPM service unit

    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator

    # Create/update PHP configuration file
    if [ -f "$PHP_CONFIG_FILE" ]; then
        print_warn "PHP configuration file ${bold}${PHP_CONFIG_FILE##*/}${default} already exists. Renaming to ${bold}${PHP_CONFIG_FILE##*/}.bak${default}"
        warn=1
        #script_log "[ WARN ] ${PHP_CONFIG_FILE##*/} already exists. Renaming to $PHP_CONFIG_FILE.bak"
        cp $PHP_CONFIG_FILE $PHP_CONFIG_FILE.bak
    fi

    # PHP configuration options
    php_config=$(cat <<-EOF
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
)
    # Write configuration to file
    echo "$php_config" | sudo tee "$PHP_CONFIG_FILE" > /dev/null
    if [ $? -ne 0 ]; then
        print_fail "Failed to update ${PHP_CONFIG_FILE}"
        warn=1
    else
        print_ok "Writing i-doit PHP configuration file ${PHP_CONFIG_FILE} done"
    fi

    # Enable i-doit PHP module
    if [ "$debug_mode" -ge 1 ]; then
        sudo phpenmod i-doit
    else
        sudo phpenmod -q i-doit
    fi
    if [ $? -ne 0 ]; then
        print_fail "Failed to enable i-doit PHP module"
        error=1
    else
        print_ok "Enabled i-doit PHP module"
    fi

    # Restart PHP-FPM service
    if [ "$debug_mode" -ge 1 ]; then
        sudo systemctl restart "$PHP_FPM_UNIT"
    else
        sudo systemctl -q restart "$PHP_FPM_UNIT"
    fi
    if [ $? -ne 0 ]; then
        print_fail "Failed to restart ${PHP_FPM_UNIT}"
        error=1
    else
        print_ok "Restarted ${PHP_FPM_UNIT}"
    fi

    echo -e "------------------------------"
    print_complete "${bold}${green}${commandaction} ${default}"
    echo ""
}

conf_apache() {
    hostname="$(cat /etc/hostname)"
    commandaction="Configuring Apache2"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator
    
    if [ -f $APACHE_CONFIG_FILE ]; then
        print_warn "Apache2 configuration file ${bold}${APACHE_CONFIG_FILE##*/}${default} already exists. Renaming to ${bold}${APACHE_CONFIG_FILE##*/}.bak${default}"
        warn=1
        #script_log "[ WARN ] ${APACHE_CONFIG_FILE##*/} already exists. Renaming to $APACHE_CONFIG_FILE.bak"
        cp $APACHE_CONFIG_FILE $APACHE_CONFIG_FILE.bak
    fi
        apache_config=$(cat <<-EOF
ServerName ${hostname}

<VirtualHost *:80>
    ServerAdmin i-doit@example.net

    DirectoryIndex index.php
    DocumentRoot ${INSTALLDIR}/

    <Directory ${INSTALLDIR}/>
        AllowOverride All
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
    )
    # Write configuration to file
    echo "$apache_config" | tee "$APACHE_CONFIG_FILE" > /dev/null
    if [ $? -ne 0 ]; then
        print_fail "Failed to update ${APACHE_CONFIG_FILE}"
        warn=1
    else
        print_ok "Writing i-doit VHost configuration file ${APACHE_CONFIG_FILE} done"
    fi

    # disable default vhost config
    sudo a2dissite 000-default || print_fail
    print_ok "disable default virtual host configuration 000-default done"

    # enable i-doit vhost config
    sudo a2ensite i-doit || print_fail
    print_ok "enable i-doit virtual host configuration i-doit done"

    # enable mod_rewrite and proxy_fcgi and proxy
    sudo a2enmod rewrite proxy proxy_fcgi || print_fail
    print_ok "enable apache2 modules rewrite and proxy_fcgi done"

    # restart for changes to take affect
    sudo systemctl restart apache2 || 'print_fail;exit 1'
    print_ok "restarting apache2 done"

    echo -e "------------------------------"
    print_complete "${bold}${green}${commandaction} ${default}"
    echo ""
}

conf_mariadb() {
    mariadb_root_pass=""
    commandaction="Configuring MariaDB"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator

    if [ -f $MARIADB_CONFIG_FILE ]; then
        print_warn "MariaDB configuration file ${bold}${MARIADB_CONFIG_FILE##*/}${default} already exists. Renaming to ${bold}${MARIADB_CONFIG_FILE##*/}.bak${default}"
        warn=1
        #script_log "[ WARN ] ${APACHE_CONFIG_FILE##*/} already exists. Renaming to $MARIADB_CONFIG_FILE.bak"
        cp $MARIADB_CONFIG_FILE $MARIADB_CONFIG_FILE.bak
    fi
        mariadb_config=$(cat <<-EOF
[mysqld]
# This is the number 1 setting to look at for any performance optimization
# It is where the data and indexes are cached: having it as large as possible will
# ensure MySQL uses memory and not disks for most read operations.
# See https://mariadb.com/kb/en/innodb-buffer-pool/
# Typical values are 1G (1-2GB RAM), 5-6G (8GB RAM), 20-25G (32GB RAM), 100-120G (128GB RAM).
innodb_buffer_pool_size = 1G
# Redo log file size, the higher the better.
# MySQL/MariaDB writes one of these log files in a default installation.
innodb_log_file_size = 512M
innodb_sort_buffer_size = 64M
sort_buffer_size = 262144 # default
join_buffer_size = 262144 # default
max_allowed_packet = 128M
max_heap_table_size = 32M
query_cache_min_res_unit = 4096
query_cache_type = 1
query_cache_limit = 5M
query_cache_size = 80M
tmp_table_size = 32M
max_connections = 200
innodb_file_per_table = 1
# Disable this (= 0) if you have slow hard disks
innodb_flush_log_at_trx_commit = 1
innodb_flush_method = O_DIRECT
innodb_lru_scan_depth = 2048
table_definition_cache = 1024
table_open_cache = 2048
innodb_stats_on_metadata = 0
sql-mode = ""
EOF
    )
    # Write configuration to file
    echo "$mariadb_config" | tee "$MARIADB_CONFIG_FILE" > /dev/null
    if [ $? -ne 0 ]; then
        print_fail "Failed to update ${MARIADB_CONFIG_FILE}"
        warn=1
    else
        print_ok "Writing MariaDB configuration file ${MARIADB_CONFIG_FILE} done"
    fi
    # create mariadb root user password
    mariadb_root_pass="$({
            choose '!@#$%^\&'
            choose '0123456789'
            choose 'abcdefghijklmnopqrstuvwxyz'
            choose 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
            for i in $( seq 1 $(( 4 + RANDOM % 8 )) )
            do
                choose '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
            done
            } | sort -R | awk '{printf "%s",$1}' )" || print_fail
    # Echo mysql root password and save it to logfile
    script_log "MariaDB root password" >> $LOGFILE
    script_log "$mariadb_root_pass" >> $LOGFILE || print_fail
    print_ok "Created random password ${bold}${red}$mariadb_root_pass${default} created"
    print_info "Saved password to $LOGFILE"

    # Set password for mariadb
    if [ "$DEBUG" -ge 1 ]; then
        sudo mysql -e"ALTER USER root@localhost IDENTIFIED VIA mysql_native_password USING PASSWORD('${mariadb_root_pass}');"
        if [ "$?" -ge 1 ]; then
            print_warn "MariaDB root user password already set"
            warn=1
        else
        print_ok "Setting MariaDB root password done"
        fi
    else
        sudo mysql -e"ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${mariadb_root_pass}');" &> /dev/null || \
        if [ "$?" -ge 1 ]; then
            print_warn "MariaDB root user password already set"
            warn=1
        else
        print_ok "Setting MariaDB root password done"
        fi
    fi

    mariadb \
        -h"$MARIADB_HOSTNAME" \
        -u"$MARIADB_SUPERUSER_USERNAME" -p"$mariadb_root_pass" \
        -e"SET GLOBAL innodb_fast_shutdown = 0" || print_fail "Unable to prepare shutdown"

    # stop mariadb
    sudo systemctl stop mariadb || print_fail "Failed to stop MariaDB"
    print_ok "Stop MariaDB done"

    # remove old log file
    mv /var/lib/mysql/ib_logfile[01] "$TMP_DIR" || print_fail "Unable to remove old log files"
    print_ok "Removed MariaDB log file"

    # start mariadb
    sudo systemctl start mariadb || print_fail "Failed to stop MariaDB"
    print_ok "Stop MariaDB done"

    echo -e "------------------------------"
    print_complete "${bold}${green}${commandaction} ${default}"
    echo ""
    set +x
}

install_idoit() {
    local prefix="php"
    local console="${INSTALLDIR}/console.php"

    commandaction="Installing i-doit"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator

    # create mariadb idoit user password
    mariadb_idoit_pass="$({
        choose '!@#$%^\&'
        choose '0123456789'
        choose 'abcdefghijklmnopqrstuvwxyz'
        choose 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        for i in $( seq 1 $(( 4 + RANDOM % 8 )) )
        do
            choose '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
        done
        } | sort -R | awk '{printf "%s",$1}' )" || print_fail

        script_log "MariaDB idoit user password" >> $LOGFILE
        script_log "$mariadb_idoit_pass" >> $LOGFILE || print_fail
        print_ok "Random MariaDB idoit user password ${bold}${red}$mariadb_idoit_pass${default} created"
        print_info "Saved MariaDB idoit user to $LOGFILE"

    # create idoit admin center password
    admin_center_pass="$({
        choose '!@#$%^\&'
        choose '0123456789'
        choose 'abcdefghijklmnopqrstuvwxyz'
        choose 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        for i in $( seq 1 $(( 4 + RANDOM % 8 )) )
        do
            choose '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
        done
        } | sort -R | awk '{printf "%s",$1}' )" || print_fail

        script_log "i-doit Admin Center password" >> $LOGFILE
        script_log "$admin_center_pass" >> $LOGFILE || print_fail
        print_ok "Random i-doit Admin Center password ${bold}${red}$admin_center_pass${default} created"
        print_info "Saved i-doit Admin Center password to $LOGFILE"

    sudo -u "${APACHE_USER}" "${prefix}" "${console}" install \
        -u "$MARIADB_SUPERUSER_USERNAME" \
        -p "$mariadb_root_pass" \
        --host="$MARIADB_HOSTNAME" \
        -d idoit_system \
        -U "$MARIADB_IDOIT_USERNAME" \
        -P "$mariadb_idoit_pass" \
        --admin-password "$admin_center_pass" \
        -n || print_fail "Installation of i-doit failed"

    echo -e "------------------------------"
    print_complete "${bold}${green}${commandaction} ${default}"
    echo ""
}

function create_tenant {
    local prefix="php"
    local console="${INSTALLDIR}/console.php"

    commandaction="Creating i-doit tenant"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator

    sudo -u "${APACHE_USER}" "${prefix}" "${console}" tenant-create \
        -u "$MARIADB_SUPERUSER_USERNAME" \
        -p "$mariadb_root_pass" \
        -d idoit_data \
        -t "$TENANT_NAME" \
        -U "$MARIADB_IDOIT_USERNAME" \
        -P "$mariadb_idoit_pass" \
        -n || print_fail "Creating i-doit tenant failed"

    echo -e "------------------------------"
    print_complete "${bold}${green}${commandaction} ${default}"
    echo ""
}

# setup cron job or maybe systemd timer?
setup_cron() {
    
    commandaction="Setting up cron job"
    echo -e ""
    echo -e "${bold}${yellow}${commandaction}${default}"
    messages_separator
    #TODO
    #echo "0 2 * * * root ${INSTALLDIR}/backup.sh" >> /etc/cron.d/i-doit.conf
    
    echo -e "------------------------------"
    print_complete "${bold}${green}${commandaction} ${default}"
    echo ""
}

main() {
    commandaction="i-doit installation on Ubuntu 22.04"
    update_and_install_packages || print_error
    get_binaries 
    #secure_installation 
    download_and_extract_idoit || print_error
    conf_php_fpm || print_error
    conf_apache || print_error
    conf_mariadb || print_error

    install_idoit
    create_tenant    
    #setup_cron
    cleanup
    success_banner
    support_list
}
# =============
# main script

main "$@"
exit 0
# =============
