@{
    Title = 'Lab 1A: Deploy a Security Management Server'
    Steps = @(
        @{ Desc = '1A-1: Switch A-SMS admin shell to /bin/bash (needed before files can be copied with SCP)'
           Type = 'clish'; Host = 'A-SMS'
           Commands = @'
set user admin shell /bin/bash
save config
'@ }
        @{ Desc = '1A-1.12: Copy A-SMS_ftw.sh from A-GUI to A-SMS:/home/admin (WinSCP equivalent)'
           Type = 'copy'; Host = 'A-SMS'
           Local  = 'A-SMS_ftw.sh'
           Remote = '/home/admin/A-SMS_ftw.sh' }
        @{ Desc = '1A-1.12: Copy A-SMS_config.sh from A-GUI to A-SMS:/home/admin (WinSCP equivalent)'
           Type = 'copy'; Host = 'A-SMS'
           Local  = 'A-SMS_config.sh'
           Remote = '/home/admin/A-SMS_config.sh' }
        @{ Desc = '1A-1: First Time Configuration Wizard via config_system (dry-run, then live)'
           Type = 'bash'; Host = 'A-SMS'; TimeoutNote = 20
           Commands = @'
cd /home/admin
config_system -f A-SMS_ftw.sh --dry-run
config_system -f A-SMS_ftw.sh
fwm ver
'@ }
        @{ Desc = '1A-2: Import the Gaia configuration (load configuration A-SMS_config.sh)'
           Type = 'bash'; Host = 'A-SMS'
           Commands = @'
cd /home/admin
cat > /home/admin/ccas_1a2.clish <<'EOF'
show route
show hostname
show dns
show domainname
set clienv on-failure continue
load configuration /home/admin/A-SMS_config.sh
set clienv on-failure stop
save config
show route
show hostname
show dns
show domainname
EOF
clish -i -f /home/admin/ccas_1a2.clish
api status
'@ }
        @{ Desc = '1A-3: Update the Security Management Server (SmartConsole/GUI task - manual)'
           Type = 'manual'
           Text = 'Open SmartConsole and complete the SMS update as per the lab guide. No CLI commands.' }
    )
}
