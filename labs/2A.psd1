@{
    Title = 'Lab 2A: Prepare the Environment for API Configuration'
    Steps = @(
        @{ Desc = '2A-1: Create api_admin (API-key auth) and cache the key locally (recreates api_admin if it already exists)'
           Type = 'bash'; Host = 'A-SMS'
           # The API key is read from the APIKEY= line and stored in state.json.
           Capture = @{ Pattern = 'APIKEY=([A-Za-z0-9+/=]{10,})'; StateKey = 'apikey' }
           Commands = @'
SID=$(mgmt_cli login user "cpadmin" password '{{PASS}}' session-timeout 600 --format json | jq -r '.sid')
if [ -z "$SID" ] || [ "$SID" = "null" ]; then echo "LOGIN FAILED"; exit 1; fi
echo "Session: $SID"
if mgmt_cli --session-id "$SID" --format json show administrator name "api_admin" >/dev/null 2>&1; then
  echo "api_admin already exists - deleting it so a fresh API key can be issued"
  mgmt_cli --session-id "$SID" --format json delete administrator name "api_admin"
  mgmt_cli --session-id "$SID" --format json publish
fi
mgmt_cli --session-id "$SID" --format json add administrator name "api_admin" authentication-method "api key" permissions-profile "read write all" > /home/admin/api_admin.json
jq '{name, "authentication-method", "permissions-profile": ."permissions-profile".name}' /home/admin/api_admin.json
mgmt_cli --session-id "$SID" --format json publish
mgmt_cli --session-id "$SID" --format json logout
echo "APIKEY=$(jq -r '."api-key"' /home/admin/api_admin.json)"
'@ }
        @{ Desc = '2A-2: Accept API calls from all IPs and restart the API'
           Type = 'bash'; Host = 'A-SMS'; TimeoutNote = 5
           Commands = @'
SID=$(mgmt_cli login user "cpadmin" password '{{PASS}}' session-timeout 600 --format json | jq -r '.sid')
if [ -z "$SID" ] || [ "$SID" = "null" ]; then echo "LOGIN FAILED"; exit 1; fi
mgmt_cli --session-id "$SID" --format json set api-settings accepted-api-calls-from "All IP addresses"
mgmt_cli --session-id "$SID" --format json publish
mgmt_cli --session-id "$SID" --format json logout
api restart
api status
'@ }
    )
}
