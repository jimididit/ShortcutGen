#!/bin/bash

: <<-'COMMENT'
Immediately enable "strict mode" so that:
    - any unbound variable causes an error (-u)
    - any failed command causes an exit (-e)
    - any failure in a pipeline causes the pipeline to fail (-o pipefail)
COMMENT
set -euo pipefail

# Set the WINEPREFIX_DIRECTORY to the user's home directory
WINEPREFIX_DIRECTORY="${HOME}/.wine"
GITHUB_REPOSITORY_API="https://api.github.com/repos"

function print() {
    local status="${1}"
    local message="${2}"
    local color

    case "${status}" in
        information) color="\033[1;34m[*]\033[0m" ;;    # Bold Blue
        completed) color="\033[1;32m[+]\033[0m" ;;      # Bold Green
        error) color="\033[1;31m[-]\033[0m" ;;          # Bold Red
    esac

    echo -e "${color} ${message}"
}

function quit() {
    local code="${1}"

    print "information" "Terminating program..."
    exit "${code}"
}

function check_program() {
    type -P "${1}" 2>/dev/null
}

function invoke_as() {
    local commands="${1}"

    if [[ -n $(check_program "sudo") ]]
    then
        eval "sudo ${commands}"
    elif [[ -n $(check_program "doas") ]]
    then
        eval "doas ${commands}"
    fi
}

function install_powershell() {
    local repository="${GITHUB_REPOSITORY_API}/PowerShell/PowerShell/releases/latest"
    local response=$(curl -s "${repository}")
    local installer
    local artifacts

    function setup_wineprefix() {
        if [[ ! -d "${WINEPREFIX_DIRECTORY}" ]]
        then
            print "information" "Creating a WINEPREFIX directory in '${WINEPREFIX_DIRECTORY}'"
            mkdir "${WINEPREFIX_DIRECTORY}"
        fi

        if [[ "${HOSTTYPE}" == "x86_64" ]]
        then
            print "information" "Configuring wine directory with the latest version of Windows..."
            eval "WINEDEBUG=-all WINEARCH=win64 WINEPREFIX='${WINEPREFIX_DIRECTORY}' winecfg /v win11 &>/dev/null"

            print "information" "Initializing wine directory..."
            eval "WINEDEBUG=-all WINEARCH=win64 WINEPREFIX='${WINEPREFIX_DIRECTORY}' wineboot -u &>/dev/null"
        else
            print "error" "x86_64 (64-bit) architecture is only supported!"
            quit 1
        fi
    }

    setup_wineprefix

    print "information" "Fetching latest PowerShell release URLs..."
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
            installer=$(basename "${url}")
            [[ -f "${installer}" ]] && rm -f "${installer}"
            invoke_as "curl -sLo '${installer}' '${url}'"
            break
        fi
    done

    if [[ -f "${installer}" ]]
	then
    	print "information" "Installing PowerShell..."
    	eval "WINEDEBUG=-all WINEARCH=win64 WINEPREFIX='${WINEPREFIX_DIRECTORY}' wine msiexec.exe /package \"${installer}\" /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1 &>/dev/null"
    	rm -f "${installer}"
    	print "completed" "PowerShell Installed!"
	else
        print "error" "PowerShell installer not found! Please try again."
		quit 1
	fi
}

function install_packages() {
    local -a programs=("${@}")

    if [[ -f "/etc/debian_version" ]]
    then
        invoke_as "DEBIAN_FRONTEND=noninteractive apt install -yqq ${programs[*]}"
    elif [[ -f "/etc/fedora-release" ]]
    then
        invoke_as "dnf install -y ${programs[*]}"
    elif [[ -f "/etc/redhat-release" ]]
    then
        invoke_as "yum install -y ${programs[*]}" || invoke_as "dnf install -y ${programs[*]}"
    elif [[ -f "/etc/arch-release" ]]
    then
        invoke_as "pacman -S --noconfirm ${programs[*]}"
    fi
}

function check_dependencies() {
    local -a programs=("desktop-file-edit" "wine")
    local -a powershell=("${WINEPREFIX_DIRECTORY}/drive_c/Program Files/PowerShell/"*/pwsh.exe)
    local -a packages

    if [[ ! -d "${WINEPREFIX_DIRECTORY}" ]]
    then
        print "information" "Creating directory: ${WINEPREFIX_DIRECTORY}."
        mkdir "${WINEPREFIX_DIRECTORY}"
    fi

    for program in "${programs[@]}"
    do
        if [[ -z $(check_program "${program}") ]]
        then
            if [[ "${program}" == "desktop-file-edit" ]]
            then
                packages+=("desktop-file-utils")
            else
                packages+=("${program}")
            fi
        fi
    done

    if ((${#packages[@]} > 0))
    then
        print "information" "Installing necessary packages..."
        install_packages "${packages[@]}"
    fi

    shopt -s nullglob
    [[ ! -f "${powershell[0]}" ]] && install_powershell
    shopt -u nullglob
}

function main() {
    local program="shortcutgen"
    local source="/usr/local/src/${program}.sh"
    local destination="/usr/local/bin/${program}"
    local pattern="${program}.sh"
    local repository="${GITHUB_REPOSITORY_API}/U53RW4R3/ShortcutGen/releases/latest"
    local response=$(curl -s "${repository}")
    local artifacts

    check_dependencies

    print "information" "Installing ShortcutGen..."
    [[ -f "${source}" ]] && sudo rm -f "${source}" 2>/dev/null

    while [[ "${response}" =~ \"browser_download_url\":\ *\"([^\"]+)\"(.*) ]]
    do
        artifacts+="${BASH_REMATCH[1]}"$'\n'
        response="${BASH_REMATCH[2]}"
    done

    artifacts=${artifacts%$'\n'}

    local -a urls=(${artifacts})

    for url in "${urls[@]}"
    do
        if [[ "${url}" == *"${pattern}"* ]]
        then
            file=$(basename "${url}")
            [[ -f ${source} ]] && rm -f "${source}"
            invoke_as "curl -sLo '${source}' '${url}'"
            break
        fi
    done

    invoke_as "chmod 755 '${source}'"

    if [[ -f "${destination}" || ! -f "${destination}" ]]
    then
        invoke_as "ln -sf '${source}' '${destination}'"
        invoke_as "chmod 755 '${destination}'"
    fi

    if [[ -f "${source}" && -f "${destination}" ]]
    then
        print "completed" "The installation is a success!"
    else
        print "error" "The installation has failed! Please try again."
    fi
}

main
