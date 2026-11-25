@{
    Title = 'Lab 6A: View and Filter Information with JSON and jq'
    Steps = @(
        @{ Desc = '6A-1: Generate tcp.json and B-GW.json on A-SMS (B-GW uid resolved automatically)'
           Type = 'bash'; Host = 'A-SMS'; UseApiSession = $true
           Commands = @'
__SESSION__
mgmt_cli --session-id "$SID" --format json show objects limit 250 type "service-tcp" details-level full > /home/admin/tcp.json
head -c 500 /home/admin/tcp.json; echo
BGWUID=$(mgmt_cli --session-id "$SID" --format json show-simple-gateways filter "B-GW" details-level "uid" | jq -r '.objects[0]')
echo "B-GW uid: $BGWUID"
mgmt_cli --session-id "$SID" --format json show object uid "$BGWUID" details-level full > /home/admin/B-GW.json
mgmt_cli --session-id "$SID" --format json logout
ls -lah /home/admin/*.json
'@ }
        @{ Desc = '6A-2: Filter B-GW.json with jq'
           Type = 'bash'; Host = 'A-SMS'
           Commands = @'
cd /home/admin
jq '.object.interfaces' B-GW.json
jq '.object.interfaces [] |.name' B-GW.json
jq '.object.interfaces [] | select (.name =="eth0")' B-GW.json
jq '.object.interfaces [] | select (.name =="eth1")' B-GW.json
jq '.object.interfaces[] | (.name +"," + ."ipv4-address")' B-GW.json
jq -r '.object.interfaces[] | [.name, ."ipv4-address"] |@csv' B-GW.json
jq -r '.object.interfaces[] | [.name, ."ipv4-address"] |@csv' B-GW.json | tr ',' ';'
jq -r '.object.interfaces[] | [.name, ."ipv4-address", ."ipv4-mask-length"] |@csv' B-GW.json | tr ',' ';'
'@ }
        @{ Desc = '6A-3: Filter the larger tcp.json dataset'
           Type = 'bash'; Host = 'A-SMS'
           Commands = @'
cd /home/admin
ls -lah *.json
jq '.objects[] .name' tcp.json
jq '.objects[] .port' tcp.json
jq '.objects[] | select(.color | contains("red" , "green")) |.name' tcp.json
jq '.objects[] | select(.color | contains("red" , "green")) | [.name, .port, ."color"] |@csv' tcp.json | tr ',' ';'
'@ }
        @{ Desc = '6A-4: Group queries with jq over the Management API'
           Type = 'bash'; Host = 'A-SMS'; UseApiSession = $true
           Commands = @'
__SESSION__
mgmt_cli --session-id "$SID" --format json show groups | jq -r '.objects[] .name'
mgmt_cli --session-id "$SID" --format json show group name "SecurityGateways" | jq -r '.members |length'
mgmt_cli --session-id "$SID" --format json show group name "SecurityGateways" | jq -r '.members[] | [.name, .type]'
mgmt_cli --session-id "$SID" --format json show group name "SecurityGateways" | jq -r '.members[] | [.name, .uid, .type, .color] |@csv' | tr ',' ';'
mgmt_cli --session-id "$SID" --format json logout
'@ }
    )
}
