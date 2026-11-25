@{
    Title = 'Lab 4A: Modify and Examine Configuration with Gaia API'
    Steps = @(
        @{ Desc = '4A-1: Gaia API on A-GW - interface comments and static routes (original /25 version)'
           Type = 'bash'; Host = 'A-GW'; TimeoutNote = 5
           Commands = @'
SID=$(mgmt_cli --format json login --context gaia_api --version 1.7 user "admin" password '{{PASS}}' session-timeout 3600 | jq -r '.sid')
if [ -z "$SID" ] || [ "$SID" = "null" ]; then echo "LOGIN FAILED"; exit 1; fi
echo "Gaia session: $SID"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.7 show interfaces
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.7 set physical-interface name "eth0" comments "Headquarters Management Network interface"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.7 set physical-interface name "eth1" comments "Headquarters External Network interface"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.7 set physical-interface name "eth2" comments "Headquarters Internal Network interface"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.7 set physical-interface name "eth3" comments "Headquarters DMZ Network interface"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.7 show interfaces
clish -c "set static-route 192.168.211.0/25 nexthop gateway address 192.168.11.254 priority 8 on"
clish -c "set static-route 192.168.211.128/25 nexthop gateway address 192.168.11.254 priority 8 on"
clish -c "save config"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.7 show routes
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.7 show static-routes
mgmt_cli --session-id "$SID" --context gaia_api --version 1.7 --format json set static-route address "192.168.111.0" mask-length 24 next-hop.add.gateway "192.168.11.254" next-hop.add.priority 1 rank 1 type "gateway" comment "Headquarters First Internal Extension Network route"
mgmt_cli --session-id "$SID" --context gaia_api --version 1.7 --format json set static-route address "192.168.211.0" mask-length 25 next-hop.add.gateway "192.168.11.254" next-hop.add.priority 1 rank 1 type "gateway" comment "Headquarters Second Internal Extension Network route"
mgmt_cli --session-id "$SID" --context gaia_api --version 1.7 --format json set static-route address "192.168.211.128" mask-length 25 next-hop.add.gateway "192.168.11.254" next-hop.add.priority 1 rank 1 type "gateway" comment "Headquarters Third Internal Extension Network route"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.7 set static-route address "192.168.112.0" mask-length 24 next-hop.add.gateway "192.168.12.254" next-hop.add.priority 1 rank 1 type "gateway" comment "Headquarters DMZ First Extension Network route"
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.7 show static-routes
mgmt_cli --session-id "$SID" --format json --context gaia_api --version 1.7 logout
'@ }
        @{ Desc = '4A-2: From A-GW, update the SMS over the Management API (EXT2/EXT3 networks, install policy)'
           Type = 'bash'; Host = 'A-GW'; UseApiSession = $true; SessionExtra = '--management "10.1.1.101"'; TimeoutNote = 10
           Commands = @'
__SESSION__
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add network name "A-INT-EXT2" color "crete blue" comments "Alpha Corporation Internal Network Extension 2" subnet4 "192.168.211.0" mask-length4 "25" nat-settings.auto-rule true nat-settings.method "hide" nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "203.0.113.211"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" add network name "A-INT-EXT3" color "crete blue" comments "Alpha Corporation Internal Network Extension 3" subnet4 "192.168.211.128" mask-length4 "25" nat-settings.auto-rule true nat-settings.method "hide" nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "203.0.113.218"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" get-interfaces target-name "A-GW" with-topology true
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" publish
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" verify-policy policy-package "Unified-Policy"
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" install-policy policy-package "Unified-Policy" targets "A-GW" access true
mgmt_cli --session-id "$SID" --format json --management "10.1.1.101" logout
'@ }
        @{ Desc = '4A-3: View configuration on the SMS (SmartConsole task - manual)'
           Type = 'manual'
           Text = 'Review the new networks and routes in SmartConsole as per the lab guide.' }
    )
}
