@{
    Title = 'Lab 1B: Deploy a Security Gateway with Blink'
    Steps = @(
        @{ Desc = '1B-prep: Switch A-GW admin shell to /bin/bash (replaces interactive expert)'
           Type = 'clish'; Host = 'A-GW'
           Commands = @'
set expert-authentication-method user-password
set user admin shell /bin/bash
save config
'@ }
        @{ Desc = '1B-0: Copy the prepared answers.xml to A-GW:/home/admin (skipped if not in payload)'
           Type = 'copy'; Host = 'A-GW'; Optional = $true
           Local  = 'answers.xml'
           Remote = '/home/admin/answers.xml' }
        @{ Desc = '1B-1: Organize the Blink package files'
           Type = 'bash'; Host = 'A-GW'
           Commands = @'
mkdir -p /var/log/blink_working/
mv /home/admin/* /var/log/blink_working/ 2>/dev/null
cd /var/log/blink_working
tar -zxvf blink.tgz
chmod -v +x blink
ls -lah
'@ }
        @{ Desc = '1B-2: Build clish_commands.txt and install_content.sh (scripted equivalent of the vim steps)'
           Type = 'bash'; Host = 'A-GW'
           Commands = @'
cd /var/log/blink_working
cp A-GW_config.sh clish_commands.txt
cat > install_content.sh <<'EOF'
#!/bin/bash
Log_File="/var/log/user_main_script.log"
echo "Configuring Mgmt interface..." >> $Log_File
clish -i -s -f "clish_commands.txt" >> $Log_File
exit 0
EOF
echo '--- answers.xml as staged (review below) ---'
cat answers.xml
'@ }
        @{ Desc = '1B-2: CHECKPOINT - confirm answers.xml is fully prepared'
           Type = 'manual'
           Text = @'
The official lab has students hand-edit answers.xml in vim (grub2 hash + base64
password). The answers.xml shown above is either the prepared copy pushed in step 1B-0
or the one staged in the ATC image. If it still contains placeholders, edit it on A-GW before
continuing:  vim /var/log/blink_working/answers.xml
Base64 of Chkp!234:  echo -n 'Chkp!234' | base64
Grub hash:           grub2-mkpasswd-pbkdf2
'@ }
        @{ Desc = '1B-3: Package custom content and run Blink (long: image deploy + reboot)'
           Type = 'bash'; Host = 'A-GW'; TimeoutNote = 25
           # Blink reboots A-GW; the wait is the next step
           ExpectDisconnect = $true
           Commands = @'
cd /var/log/blink_working
dos2unix answers.xml clish_commands.txt install_content.sh
chmod 755 install_content.sh
ls -lah
tar -zcvf blink_custom_content.tgz install_content.sh clish_commands.txt
./blink -i {{BLINK_IMAGE}} -u blink_custom_content.tgz -a answers.xml
'@ }
        @{ Desc = '1B-3: Wait for A-GW to reboot after Blink'
           Type = 'waitreboot'; Host = 'A-GW'; InitialSleep = 120; TimeoutMin = 40 }
        @{ Desc = '1B-3: Verify A-GW configuration (route / NTP / interfaces)'
           # clish type: works whether Blink left the admin shell as clish or bash
           Type = 'clish'; Host = 'A-GW'
           Commands = @'
show route
show ntp servers
show interfaces
'@ }
    )
}
