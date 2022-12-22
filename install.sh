#!/bin/bash

set -e

#############################################################################
#                                                                           #
# Project 'pterodactyl-installer'                                           #
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

SCRIPT_VERSION="v0.11.0"
GITHUB_BASE_URL="https://raw.githubusercontent.com/fokusdotid/pterodactyl-installer"

LOG_PATH="/var/log/pterodactyl-installer.log"

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

output() {
  echo -e "* ${1}"
}

error() {
  COLOR_RED='\033[0;31m'
  COLOR_NC='\033[0m'

  echo ""
  echo -e "* ${COLOR_RED}ERROR CUK${COLOR_NC}: $1"
  echo ""
}

execute() {
  echo -e "\n\n* pterodactyl-installer $(date) \n\n" >>$LOG_PATH

  bash <(curl -s "$1") | tee -a $LOG_PATH
  [[ -n $2 ]] && execute "$2"
}

done=false
clear
sleep 0.5
output "Pterodactyl installation script @ $SCRIPT_VERSION"
output
output "Original Script By @vilhelmprytz (Vilhelm Prytz)"
output "di Recode oleh @fokusdotid (Fokus ID)"
output
output "Skrip ini tidak terkait dengan Proyek Pterodactyl resmi."
output "Jika ingin menggunakan script resmi, silahkan kunjungi:"
output "https://github.com/vilhelmprytz/pterodactyl-installer"
output
output "Made with ❤️ by @fokusdotid (Fokus ID)"
output "https://github.com/fokusdotid/pterodactyl-installer"
output
output
output "Copyright (C) 2018 - 2022, Vilhelm Prytz, <vilhelm@prytznet.se>"
output

PANEL_LATEST="$GITHUB_BASE_URL/$SCRIPT_VERSION/install-panel.sh"

WINGS_LATEST="$GITHUB_BASE_URL/$SCRIPT_VERSION/install-wings.sh"

PANEL_CANARY="$GITHUB_BASE_URL/master/install-panel.sh"

WINGS_CANARY="$GITHUB_BASE_URL/master/install-wings.sh"

while [ "$done" == false ]; do
  options=(
    "Install panel"
    "Install Wings"
    "Install [0] dan [1] secara bersamaan (script wings berjalan setelah panel)\n"

    "Install panel dengan versi canary (versi yang ada di master, mungkin rusak!)"
    "Install Wings dengan versi canary (versi yang ada di master, mungkin rusak!)"
    "Install [6] dan [7] secara bersamaan (script wings berjalan setelah panel)"
  )

  actions=(
    "$PANEL_LATEST"
    "$WINGS_LATEST"
    "$PANEL_LATEST;$WINGS_LATEST"

    "$PANEL_CANARY"
    "$WINGS_CANARY"
    "$PANEL_CANARY;$WINGS_CANARY"
  )

  output "Apa yang ingin Anda lakukan?"

  for i in "${!options[@]}"; do
    output "[$i] ${options[$i]}"
  done

  echo -n "* Pilih 0-$((${#actions[@]} - 1)): "
  read -r action

  [ -z "$action" ] && error "Pilihan diperlukan!" && continue

  valid_input=("$(for ((i = 0; i <= ${#actions[@]} - 1; i += 1)); do echo "${i}"; done)")
  [[ ! " ${valid_input[*]} " =~ ${action} ]] && error "Opsi tidak valid!"
  [[ " ${valid_input[*]} " =~ ${action} ]] && done=true && IFS=";" read -r i1 i2 <<<"${actions[$action]}" && execute "$i1" "$i2"
done
