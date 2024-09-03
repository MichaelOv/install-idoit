#!/bin/bash
PATH="/bin:/usr/bin:/usr/sbin:$PATH"
set -eo pipefail
functions_version="v0.0.2"
shortname="Functions"
echo -e "Sourced ${shortname} version ${functions_version}"

handle_error() {
    local lineno=$1
    local msg=$2
    local exit_code=$?
    script_log "Installer version: ${installer_version}"
    script_log "${red}Error on line ${lineno}: ${msg} at commandaction: ${commandaction}${default}"
    echo -e "Installer version: ${installer_version}"
    echo -e "${red}Error on line ${lineno}: ${msg} at commandaction: ${commandaction}${default}"
    cleanup
    if [ "$?" -eq 127 ]; then
    echo -e "[ ${lightred}FAIL${default} ] Fehler in Zeile $line_number: Befehl '$command' kann nicht gefunden werden." >&2
    fi
    if [ "$?" -eq 130 ]; then
    echo -e "[ ${lightred}FAIL${default} ] Skript abgebrochen" >&2
    fi
    if [ "$?" -eq 2 ]; then
    echo -e "[ ${lightred}FAIL${default} ] Fehler in Zeile $line_number: Befehl '$command' kann nicht gefunden werden." >&2
    fi
    if [ "$?" -eq 1 ]; then
    echo -e "[ ${lightred}FAIL${default} ] Fehler in Zeile $line_number: Befehl '$command' kann nicht gefunden werden." >&2
    fi
    exit
}

#trap handle_error EXIT
trap 'handle_error "${LINENO}" "$BASH_COMMAND"' ERR

ansi_loader() {
	# carriage return.
	creeol="\r"
    # echo colors
    default="\e[0m"
    bold="\033[1m"
    black="\e[30m"
    red="\e[31m"
    lightred="\e[91m"
    green="\e[32m"
    lightgreen="\e[92m"
    yellow="\e[33m"
    lightyellow="\e[93m"
    blue="\e[34m"
    lightblue="\e[94m"
    magenta="\e[35m"
    lightmagenta="\e[95m"
    cyan="\e[36m"
    lightcyan="\e[96m"
    darkgrey="\e[90m"
    lightgrey="\e[37m"
    white="\e[97m"
    # erase to end of line.
    creeol+="\033[K"
}

# print a completion message
print_complete() {
	echo -en "${green}Complete!${default} $*"
    echo -e ""
}

# On-Screen - Automated functions
##################################

# [  OK  ]
print_ok() {
    echo -en "${creeol}[${green}  OK  ${default}] $*"
	echo -en "\n"
}

# [ FAIL ]
print_fail() {
    echo -en "${creeol}[${red} FAIL ${default}] $*"
    script_log "[ FAIL ] ${commandaction} $*"
	echo -en "\n"
    exit_code=$?
}

# [ ERROR ]
print_error() {
    echo -en "${creeol}[${red} ERROR ${default}] $*"
    script_log "[ ERROR ] ${commandaction} $*"
    echo -en "\n"
    handle_error "$@"
}

# [ WARN ]
print_warn() {
    echo -en "${creeol}[${lightyellow} WARN ${default}] $*"
    script_log "[ WARN ] ${commandaction} $*" 
    echo -en "\n"
}

# [ INFO ]
print_info() {
    echo -en "${creeol}[${cyan} INFO ${default}] $*"
	echo -en "\n"
}

# Separator
messages_separator() {
    echo -e "${bold}==============================${default}"
}

# ======================================================================
# Utility functions
warn=0
fail=0
error=0

success_banner() {
    exit_code=$?
    messages_separator
    if [ "$fail" -ge 1 ]; then
        echo -e "${bold}${red}Install Failed!${default}"
        script_log "Install Failed!"
        echo -e "Please check to logfile ${LOGFILE}"
    elif [ "$error" -ge 1 ]; then
        echo -e "${bold}${red}Install Completed with Errors!${default}"
        script_log "Install Completed with Errors!"
        echo -e "Please check to logfile ${LOGFILE}"
    elif [ "$warn" -ge 1 ]; then
        echo -e "${bold}${lightyellow}Install Completed with Warnings!${default}"
        echo -e "Please check to logfile ${LOGFILE}"
        script_log "Install Completed with Warnings!"

    elif [ -z "${exit_code}" ] || [ "${exit_code}" == "0" ]; then
        echo -e "${bold}${green}Install Complete!${default}"
        script_log "Install Complete!"
    fi

    ip_address=$(ip route get 1 | sed 's/^.*src \([^ ]*\).*$/\1/;q')
    echo -e ""
    messages_separator
    echo -e "${bold}Your installation is ready${default}. Navigate to"
    echo -e ""
    echo -e "    ${bold}${green}http://${ip_address}/${default}"
    echo -e ""
    echo -e "with your Web browser and debugin to i-doit with ${bold}${green}admin/admin${default}"
    echo -e "MariaDB ${bold}idoit${default} password is ${red}${mariadb_idoit_pass}${default}"
    echo -e "MariaDB ${bold}root${default} password is ${red}${mariadb_root_pass}${default}"
    echo -e "Admin center password is ${red}${admin_center_pass}${default}"
    echo -e ""
    echo -e "Official documentation can be found online at ${bold}${blue}https://kb.i-doit.com${default}"
    echo -e ""
    messages_separator
}

support_list() {
    messages_separator    
    echo -e "Join our community and connect with us on:"
    echo -e "  - GitHub: ${bold}${blue}https://github.com/i-doit/${default}"
    echo -e "  - Our community forums: ${bold}${blue}https://community.i-doit.com${default}"
    messages_separator
}

# Password gen from https://stackoverflow.com/a/26665585
choose() { 
    #commandaction="Generating a password"
    #echo -e ""
    #echo -e "${bold}${yellow}${commandaction}${default}"
    #messages_separator
    #echo -e ""

    ## is used with
    #
    # pass="$({
    #     choose '!@#$%^\&'
    #     choose '0123456789'
    #     choose 'abcdefghijklmnopqrstuvwxyz'
    #     choose 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    #     for i in $( seq 1 $(( 4 + RANDOM % 8 )) )
    #     do
    #         choose '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
    #     done
    # } | sort -R | awk '{printf "%s",$1}' )" || print_fail_nl
    # print_ok_nl "Created random password ${pass}"
    echo "${1:RANDOM%${#1}:1}" $RANDOM; 
    }


# could also use this https://stackoverflow.com/a/60126768 
# Password Generator Script
pass_gen() {
    PASS_LENGTH=12    
    for VAR in $(seq 1 3); #how many times password will generate, you can set range
    do
        openssl rand -base64 24 | cut -c1-"$PASS_LENGTH"
        #-base64(Encode) 24 is length 
        #cut is for user input column -c1 is column1
    done
}

# suggested
download_file() {
    local url="$1"
    local output="$2"
    wget -q "$url" -O "$output" || print_error "could not download"
    print_info "Downloaded $url to $output"
}

extract_zip() {
    commandaction="Extract ZIP"
    local file="$1"
    local dest="$2"
    sudo unzip -qo "$file" -d "$dest" || print_error "could not extract"
    print_info "Extracted $file to $dest"
}

get_latest_idoit_version() {
    local url="https://i-doit.com/updates.xml"
    latest_version=$(curl -s --fail -L "$url" | grep -oP '(?<=<directory>)[^<]+' | tail -n1)
}
