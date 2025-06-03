#!/bin/bash

WINEPREFIX_DIRECTORY="${HOME}/.wine"

function check_privileges() {
    ((EUID != 0)) && return 0
}

function print() {
    local status="${1}"
    local message="${2}"
    local color

    case "${status}" in
        information) color="\033[34m[*]\033[0m" ;;  # Blue
        progress) color="\033[1;34m[*]\033[0m" ;;   # Bold Blue
        completed) color="\033[1;32m[+]\033[0m" ;;  # Bold Green
        error) color="\033[1;31m[-]\033[0m" ;;      # Bold Red
    esac

    echo -e "${color} ${message}"
}

function quit() {
    local code="${1}"

    print "information" "Terminating program..."
    exit "${code}"
}

function install_powershell() {
    local file
    local github_repository_api_url="https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
    local artifacts

    function setup_wineprefix() {
        if [[ ! -d "${WINEPREFIX_DIRECTORY}" ]]
        then
            print "progress" "Creating a WINEPREFIX directory in '${WINEPREFIX_DIRECTORY}'"
            mkdir "${WINEPREFIX_DIRECTORY}"
        fi

        if [[ "${HOSTTYPE}" == "x86_64" ]]
        then
            print "progress" "Configuring wine directory with the latest version of Windows..."
            eval "WINEDEBUG=-all WINEARCH=win64 WINEPREFIX='${WINEPREFIX_DIRECTORY}' winecfg /v win11"

            print "progress" "Initializing wine directory..."
            eval "WINEDEBUG=-all WINEARCH=win64 WINEPREFIX='${WINEPREFIX_DIRECTORY}' wineboot -u"
        else
            print "error" "x86_64 (64-bit) architecture is only supported!"
            quit 1
        fi
    }

    setup_wineprefix

    print "progress" "Fetching latest PowerShell release URLs..."
    local response=$(curl -s "${github_repository_api_url}")
    while [[ "${response}" =~ \"browser_download_url\":\ *\"([^\"]+)\"(.*) ]]
    do
        artifacts+="${BASH_REMATCH[1]}"$'\n'
        response="${BASH_REMATCH[2]}"
    done

    # Remove trailing newline
    artifacts=${artifacts%$'\n'}

    # Extract version from URL path and remove the 'v' prefix
    local latest_version=$(cut -d '/' -f 8 <<< "${artifacts}" | head -n 1)
    latest_version=${latest_version#v}

    local pattern="PowerShell-${latest_version}-win-x64.msi"

    # Convert artifacts to array for proper iteration
    local -a urls=(${artifacts})

    for url in "${urls[@]}"
    do
        if [[ "${url}" == *"${pattern}"* ]]
        then
            file=$(basename "${url}")
            [[ -f ${file} ]] && rm -f "${file}"
            print "progress" "Downloading ${url}"
            curl -sLo "${file}" "${url}"
            [[ -f ${file} ]] && print "completed" "Download completed: ${file}"
            break
        fi
    done

    print "progress" "Installing Powershell..."
    eval "WINEDEBUG=-all WINEARCH=win64 WINEPREFIX='${WINEPREFIX_DIRECTORY}' wine msiexec.exe /package ${file} /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1"
    rm -f "${file}"
    print "completed" "Powershell Installed!"
}

function install_packages() {
    local -a programs=("${@}")

    if [[ -f "/etc/debian_version" ]]
    then
        DEBIAN_FRONTEND=noninteractive apt install -yqq "${programs[@]}"
    elif [[ -f "/etc/fedora-release" ]]
    then
        dnf install -y "${programs[@]}"
    elif [[ -f "/etc/redhat-release" ]]
    then
        yum install -y "${programs[@]}" || dnf install -y "${programs[@]}"
    elif [[ -f "/etc/arch-release" ]]
    then
        pacman -S --noconfirm "${programs[@]}"
    fi
}

function check_dependencies() {
    local -a programs=("desktop-file-edit" "wine")
    local -a powershell=("${WINEPREFIX_DIRECTORY}/drive_c/Program Files/PowerShell/"*/pwsh.exe)
    local -a packages

    if [[ ! -d "${WINEPREFIX_DIRECTORY}" ]]
    then
        print "progress" "Creating directory: ${WINEPREFIX_DIRECTORY}."
        mkdir "${WINEPREFIX_DIRECTORY}"
    fi

    for program in "${programs[@]}"
    do
        if [[ -z $(type -P "${program}" 2>/dev/null) ]]
        then
            if [[ "${program}" == "desktop-file-edit" ]]
            then
                packages+=("desktop-file-utils")
            else
                packages+=("${program}")
            fi
        fi
    done

    print "progress" "Installing necessary packages..."
    install_packages "${packages[*]}"

    shopt -s nullglob
    [[ ! -f "${powershell[0]}" ]] && install_powershell
    shopt -u nullglob
}

function main() {
    local program="shortcutgen"
    local source="/usr/local/src/${program}.sh"
    local destination="/usr/local/bin/${program}"
    local url="https://raw.githubusercontent.com/U53RW4R3/ShortcutGen/main/shortcutgen.sh"

    if [[ ! $(check_privileges) ]]
    then
        print "error" "Run as root!"
        quit 1
    fi

    check_dependencies

    print "information" "[*] Installing ShortcutGen..."
    if [[ -f "${source}" || ! -f "${source}" ]]
    then
        rm -f "${source}" 2>/dev/null

        curl -sLo "${source}" "${url}"
        chmod 755 "${source}"
    fi

    if [[ -f "${destination}" || ! -f "${destination}" ]]
    then
        ln -sf "${source}" "${destination}"
        chmod 755 "${destination}"
    fi

    if [[ -f "${source}" && -f "${destination}" ]]
    then
        print "completed" "The installation is a success!"
    else
        print "error" "The installation has failed! Please try again."
    fi
}

main
