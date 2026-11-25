@{
    Title = 'Lab 5A: Configure Remote Security Gateways with APIs'
    Steps = @(
        @{ Desc = '5A-1: NAT settings, manual NAT rules, Management Rule destination Any'
           Type = 'bash'; Host = 'A-GW'; UseApiSession = $true; SessionExtra = '--management "10.1.1.101"'
           Commands = @'
__SESSION__
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" show checkpoint-host name "A-SMS" details-level "full"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set checkpoint-host name "A-SMS" nat-settings.auto-rule true nat-settings.method "static" nat-settings.ipv4-address "203.0.113.101" nat-settings.install-on "A-GW"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add nat-section package "Unified-Policy" position "top" name "Manual NAT Rules"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add nat-rule package "Unified-Policy" position "top" name "Internal No-NAT Rule" install-on "A-GW" original-source "Alpha-Nets" original-destination "Alpha-Nets" original-service "Any"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add nat-rule package "Unified-Policy" position.below "Internal No-NAT Rule" name "Inbound A-DMZ NAT Rule" method "static" install-on "A-GW" original-source "Any" original-destination "A-DMZ-NAT" original-service "http" translated-destination "A-DMZ"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set access-rule layer "Unified-Policy Network" name "Management Rule" destination "Any"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" publish
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" logout
'@ }
        @{ Desc = '5A-2: Remote FTW of B-GW via Gaia API (initial-setup, hostname, eth0, DNS, NTP, TZ)'
           Type = 'bash'; Host = 'A-GW'; TimeoutNote = 10
           Commands = @'
SID=$(mgmt_cli --management "198.51.100.1" --format json --context gaia_api login user "admin" password '{{PASS}}' | jq -r '.sid')
if [ -z "$SID" ] || [ "$SID" = "null" ]; then echo "LOGIN FAILED"; exit 1; fi
echo "B-GW Gaia session: $SID"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "198.51.100.1" set initial-setup security-gateway.activation-key '{{PASS}}' security-gateway.cluster-member false
sleep 30
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "198.51.100.1" set hostname name "B-GW"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "198.51.100.1" set physical-interface name "eth0" enabled true comments "Bravo Site Internal Network" ipv4-address "192.168.21.1" ipv4-mask-length "24"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "198.51.100.1" set dns primary "192.168.11.101" secondary "1.1.1.1" tertiary "1.0.0.1"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "198.51.100.1" set ntp enabled true
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "198.51.100.1" set time-and-date timezone "America/St_Johns"
echo "Waiting {{FTW_WAIT_SECONDS}}s for the B-GW FTW to complete before reboot..."
sleep {{FTW_WAIT_SECONDS}}
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "198.51.100.1" run-reboot
'@ }
        @{ Desc = '5A-2: Wait for B-GW reboot'
           Type = 'waitreboot'; Host = 'B-GW'; InitialSleep = 60; TimeoutMin = 25 }
        @{ Desc = '5A-2: Remote FTW of C-GW via Gaia API'
           Type = 'bash'; Host = 'A-GW'; TimeoutNote = 10
           Commands = @'
SID=$(mgmt_cli --format json --context gaia_api --version 1.6 --management "192.0.2.1" login user "admin" password '{{PASS}}' | jq -r '.sid')
if [ -z "$SID" ] || [ "$SID" = "null" ]; then echo "LOGIN FAILED"; exit 1; fi
echo "C-GW Gaia session: $SID"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "192.0.2.1" set initial-setup security-gateway.activation-key '{{PASS}}' security-gateway.cluster-member false
sleep 30
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "192.0.2.1" set hostname name "C-GW"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "192.0.2.1" set physical-interface name "eth0" enabled true comments "Charlie Site Internal Network" ipv4-address "192.168.31.1" ipv4-mask-length "24"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "192.0.2.1" set dns primary "192.168.11.101" secondary "1.1.1.1" tertiary "1.0.0.1"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "192.0.2.1" set ntp enabled true
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "192.0.2.1" set time-and-date timezone "Pacific/Honolulu"
echo "Waiting {{FTW_WAIT_SECONDS}}s for the C-GW FTW to complete before reboot..."
sleep {{FTW_WAIT_SECONDS}}
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.6 --management "192.0.2.1" run-reboot
'@ }
        @{ Desc = '5A-2: Wait for C-GW reboot'
           Type = 'waitreboot'; Host = 'C-GW'; InitialSleep = 60; TimeoutMin = 25 }
        @{ Desc = '5A-2: Post-FTW Gaia settings on B-GW (timeouts, expert auth)'
           Type = 'clish'; Host = 'B-GW'
           Commands = @'
set expert-authentication-method user-password
set inactivity-timeout 720
set web session-timeout 720
save config
'@ }
        @{ Desc = '5A-2: Post-FTW Gaia settings on C-GW (timeouts, expert auth)'
           Type = 'clish'; Host = 'C-GW'
           Commands = @'
set expert-authentication-method user-password
set inactivity-timeout 720
set web session-timeout 720
save config
'@ }
        @{ Desc = '5A-3: SMS objects for B/C sites, VPN community, rule updates'
           Type = 'bash'; Host = 'A-SMS'; UseApiSession = $true; SessionExtra = '--management "10.1.1.101"'; TimeoutNote = 5
           Commands = @'
__SESSION__
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add network name "B-INT-NET" color "aquamarine" comments "Bravo Site Internal Network" subnet4 "192.168.21.0" mask-length4 24 nat-settings.auto-rule true nat-settings.method "hide" nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "198.51.100.21"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add network name "C-INT-NET" color "orchid" comments "Charlie Site Internal Network" subnet4 "192.168.31.0" mask-length4 24 nat-settings.auto-rule true nat-settings.method "hide" nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "192.0.2.31"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add simple-gateway name "B-GW" ipv4-address "198.51.100.1" color "pink" comments "Bravo Site Perimeter Security Gateway" version "{{CP_VERSION}}" hardware "Open Server" one-time-password '{{PASS}}' firewall true vpn true application-control true url-filtering true content-awareness true interfaces.1.name "eth0" interfaces.1.ipv4-address "192.168.21.1" interfaces.1.ipv4-mask-length 24 interfaces.1.anti-spoofing true interfaces.2.name "eth1" interfaces.2.ipv4-address "198.51.100.1" interfaces.2.ipv4-mask-length 24 interfaces.2.anti-spoofing true
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add simple-gateway name "C-GW" ipv4-address "192.0.2.1" color "pink" comments "Charlie Site Perimeter Security Gateway" version "{{CP_VERSION}}" hardware "Open Server" one-time-password '{{PASS}}' firewall true vpn true application-control true url-filtering true content-awareness true interfaces.1.name "eth0" interfaces.1.ipv4-address "192.168.31.1" interfaces.1.ipv4-mask-length 24 interfaces.1.anti-spoofing true interfaces.2.name "eth1" interfaces.2.ipv4-address "192.0.2.1" interfaces.2.ipv4-mask-length 24 interfaces.2.anti-spoofing true
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" get-interfaces target-name "B-GW" with-topology true
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" get-interfaces target-name "C-GW" with-topology true
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set network name "A-DMZ-NET" nat-settings.auto-rule true nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "203.0.113.12" nat-settings.install-on "A-GW"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set network name "A-DMZ-EXT" nat-settings.auto-rule true nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "203.0.113.112" nat-settings.install-on "A-GW"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set network name "A-MGMT-NET" nat-settings.auto-rule true nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "203.0.113.10" nat-settings.install-on "A-GW"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set network name "A-INT-NET" nat-settings.auto-rule true nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "203.0.113.11" nat-settings.install-on "A-GW"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set network name "A-INT-EXT" nat-settings.auto-rule true nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "203.0.113.111" nat-settings.install-on "A-GW"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set network name "B-INT-NET" nat-settings.auto-rule true nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "198.51.100.21" nat-settings.install-on "B-GW"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set network name "C-INT-NET" nat-settings.auto-rule true nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "192.0.2.31" nat-settings.install-on "C-GW"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" publish
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set group name "SecurityGateways" members.add.1 "B-GW" members.add.2 "C-GW"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add group name "Bravo-Nets" color "aquamarine" comments "Bravo Site Internal Networks" members.1 "B-INT-NET"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add group name "Charlie-Nets" color "orchid" comments "Charlie Site Internal Networks" members.1 "C-INT-NET"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" publish
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add vpn-community-meshed name "Alpha-Corporate-VPN" color "sky blue" comments "Corporate Internal VPN Community" gateways.1 "A-GW" gateways.2 "B-GW" gateways.3 "C-GW" override-vpn-domains.1.gateway "A-GW" override-vpn-domains.1.vpn-domain "Alpha-Nets" override-vpn-domains.2.gateway "B-GW" override-vpn-domains.2.vpn-domain "Bravo-Nets" override-vpn-domains.3.gateway "C-GW" override-vpn-domains.3.vpn-domain "Charlie-Nets" encryption-method "prefer ikev2 but support ikev1" encryption-suite "custom" ike-phase-1.data-integrity "sha256" ike-phase-1.encryption-algorithm "aes-256" ike-phase-1.diffie-hellman-group "group 19" ike-phase-1.ike-p1-rekey-time 720 ike-phase-1.ike-p1-rekey-time-unit "minutes" ike-phase-2.data-integrity "aes-xcbc" ike-phase-2.encryption-algorithm "aes-gcm-256" ike-phase-2.ike-p2-use-pfs false ike-phase-2.ike-p2-rekey-time 1800 ike-phase-2.ike-p2-rekey-time-unit "seconds" tunnel-granularity "universal"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add access-rule layer "Unified-Policy Network" position.above "LDAP Rule" name "VPN Rule" source.1 "Alpha-Nets" source.2 "Bravo-Nets" source.3 "Charlie-Nets" destination.1 "Alpha-Nets" destination.2 "Bravo-Nets" destination.3 "Charlie-Nets" vpn "Alpha-Corporate-VPN" service.1 "LDAP-Services" service.2 "http" service.3 "https" service.4 "ssh_version_2" action "Accept" track.type "Log" track.accounting true track.enable-firewall-session true track.per-session true track.per-connection true
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set access-rule layer "Unified-Policy Network" name "LDAP Rule" source.add.1 "Bravo-Nets" source.add.2 "Charlie-Nets"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set access-rule layer "Unified-Policy Network" name "DNS Rule" source.add.1 "Bravo-Nets" source.add.2 "Charlie-Nets"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set access-rule layer "Unified-Policy Network" name "Outgoing Rule" source.add.1 "Bravo-Nets" source.add.2 "Charlie-Nets"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" set access-rule layer "Unified-Policy Network" name "Management Rule" destination "SecurityGateways"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" publish
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" logout
'@ }
        @{ Desc = '5A-4: Add JHF to repository, verify and install on B-GW & C-GW (long, needs cloud access)'
           Type = 'bash'; Host = 'A-SMS'; UseApiSession = $true; TimeoutNote = 45
           Commands = @'
__SESSION__
mgmt_cli --session-id "$SID" --format json add repository-package source "cloud" name "{{JHF_PACKAGE}}"
mgmt_cli --session-id "$SID" --format json verify-software-package name "{{JHF_PACKAGE}}" download-package true download-package-from "central" targets.1 "B-GW" targets.2 "C-GW"
mgmt_cli --session-id "$SID" --format json install-software-package name "{{JHF_PACKAGE}}" package-location "central" method "install" targets.1 "B-GW" targets.2 "C-GW"
mgmt_cli --session-id "$SID" --format json logout
cpinfo -y all
'@ }
        @{ Desc = '5A-4: Licenses (SmartUpdate/GUI task - manual)'
           Type = 'manual'
           Text = 'Install the lab license/contract files per the lab guide (SmartConsole / SmartUpdate).' }
    )
}
