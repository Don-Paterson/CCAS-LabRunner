@{
    Title = 'Lab 3B: Automate Security Policy and Gateway Connection'
    Steps = @(
        @{ Desc = '3B-1: Push verified policy script (bash_api_verified-Policy.sh) to A-SMS'
           Type = 'copy'; Host = 'A-SMS'
           Local  = 'bash_api_verified-Policy.sh'
           Remote = '/home/admin/bash_api_policy.sh' }
        @{ Desc = '3B-1: Prep and run the policy script (objects, package, layers, rules)'
           Type = 'bash'; Host = 'A-SMS'; TimeoutNote = 5
           Commands = @'
dos2unix /home/admin/bash_api_policy.sh
chmod -v +x /home/admin/bash_api_policy.sh
/home/admin/bash_api_policy.sh
'@ }
        @{ Desc = '3B-2: Connect A-GW as a simple-gateway, add extension networks, publish'
           Type = 'bash'; Host = 'A-SMS'; UseApiSession = $true
           Commands = @'
__SESSION__
mgmt_cli --session-id "$SID" --format json add simple-gateway name "A-GW" ipv4-address "10.1.1.1" color "pink" comments "Alpha Corporation Headquarters Perimeter Gateway" version "{{CP_VERSION}}" one-time-password '{{PASS}}' firewall true vpn true application-control true url-filtering true content-awareness true interfaces.1.name "eth0" interfaces.1.ipv4-address "10.1.1.1" interfaces.1.ipv4-mask-length "24" interfaces.1.anti-spoofing true interfaces.1.topology "INTERNAL" interfaces.2.name "eth1" interfaces.2.ipv4-address "203.0.113.1" interfaces.2.ipv4-mask-length "24" interfaces.2.anti-spoofing true interfaces.2.topology "EXTERNAL" groups "SecurityGateways"
mgmt_cli --session-id "$SID" --format json add network name "A-INT-EXT" color "crete blue" comments "Alpha Internal Extension Network" subnet "192.168.111.0" mask-length 24 nat-settings.auto-rule true nat-settings.method "hide" nat-settings.ip-address "203.0.113.111" groups "Alpha-Nets"
mgmt_cli --session-id "$SID" --format json add network name "A-DMZ-EXT" color "crete blue" comments "Alpha DMZ Extension Network" subnet "192.168.112.0" mask-length 24 nat-settings.auto-rule true nat-settings.method "hide" nat-settings.ip-address "203.0.113.112" groups "Alpha-Nets"
mgmt_cli --session-id "$SID" --format json get-interfaces target-name "A-GW" with-topology true
mgmt_cli --session-id "$SID" --format json publish
mgmt_cli --session-id "$SID" --format json logout
'@ }
        @{ Desc = '3B-3: Verify and install Unified-Policy on A-GW'
           Type = 'bash'; Host = 'A-SMS'; UseApiSession = $true; TimeoutNote = 10
           Commands = @'
__SESSION__
mgmt_cli --session-id "$SID" --format json verify-policy policy-package "Unified-Policy"
mgmt_cli --session-id "$SID" --format json install-policy policy-package "Unified-Policy" targets "A-GW" access true
mgmt_cli --session-id "$SID" --format json logout
'@ }
    )
}
