@{
    Title = 'Lab 3A: Automate Object Creation'
    Steps = @(
        @{ Desc = '3A-1: Modify A-SMS object, create host objects, publish + install-database'
           Type = 'bash'; Host = 'A-SMS'; UseApiSession = $true
           Commands = @'
__SESSION__
mgmt_cli --session-id "$SID" --format json set checkpoint-host name "A-SMS" color "pink" comments "Alpha Corporation Primary Security Management Server" management-blades.network-policy-management true management-blades.logging-and-status true management-blades.compliance true nat-settings.auto-rule true nat-settings.method "static" nat-settings.ipv4-address "203.0.113.101" logs-settings.alert-when-free-disk-space-below true logs-settings.free-disk-space-metrics "percent" logs-settings.alert-when-free-disk-space-below-threshold "15" logs-settings.alert-when-free-disk-space-below-type "popup alert" logs-settings.delete-when-free-disk-space-below true logs-settings.delete-when-free-disk-space-below-threshold "20" logs-settings.stop-logging-when-free-disk-space-below true logs-settings.stop-logging-when-free-disk-space-below-threshold "10"
mgmt_cli --session-id "$SID" --format json add host name "A-DMZ" ip-address "192.168.12.101" color "crete blue" comments "Alpha Corporation DMZ Server"
mgmt_cli --session-id "$SID" --format json add host name "A-DMZ-NAT" ip-address "203.0.113.121" color "firebrick" comments "Alpha Corporation DMZ Server NAT Object"
mgmt_cli --session-id "$SID" --format json publish
mgmt_cli --session-id "$SID" --format json install-database targets "A-SMS"
mgmt_cli --session-id "$SID" --format json logout
'@ }
        @{ Desc = '3A-2: Create network objects, publish + install-database'
           Type = 'bash'; Host = 'A-SMS'; UseApiSession = $true
           Commands = @'
__SESSION__
mgmt_cli --session-id "$SID" --format json add network name "A-DMZ-NET" color "crete blue" comments "Alpha Corporation DMZ Network" subnet4 "192.168.12.0" mask-length4 "24" nat-settings.auto-rule true nat-settings.method "hide" nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "203.0.113.12"
mgmt_cli --session-id "$SID" --format json add network name "A-EXT-NET" color "Firebrick" comments "Alpha Corporation Headquarters External Network" subnet4 "203.0.113.0" mask-length4 "24"
mgmt_cli --session-id "$SID" --format json add network name "A-INT-NET" color "crete blue" comments "Alpha Corporation Internal Network" subnet4 "192.168.11.0" mask-length4 "24" nat-settings.auto-rule true nat-settings.method "hide" nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "203.0.113.11"
mgmt_cli --session-id "$SID" --format json add network name "A-MGMT-NET" color "crete blue" comments "Alpha Corporation Management Network" subnet4 "10.1.1.0" mask-length4 "24" nat-settings.auto-rule true nat-settings.method "hide" nat-settings.hide-behind "ip-address" nat-settings.ipv4-address "203.0.113.10"
mgmt_cli --session-id "$SID" --format json publish
mgmt_cli --session-id "$SID" --format json install-database targets "A-SMS"
mgmt_cli --session-id "$SID" --format json logout
'@ }
        @{ Desc = '3A-3: Push verified groups script (bash_api_verified-Groups.sh) to A-SMS'
           Type = 'copy'; Host = 'A-SMS'
           Local  = 'bash_api_verified-Groups.sh'
           Remote = '/home/admin/bash_api.sh' }
        @{ Desc = '3A-3: Back up, prep and run the groups script'
           Type = 'bash'; Host = 'A-SMS'
           Commands = @'
dos2unix /home/admin/bash_api.sh
cp /home/admin/bash_api.sh /home/admin/bash_api.original.sh
chmod -v 755 /home/admin/bash_api.sh
/home/admin/bash_api.sh
'@ }
    )
}
