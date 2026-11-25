# CCAS Lab Runner V3

Menu-driven automation of the **Check Point CCAS R81.20 labs (1A–6A)**, run from
**A-GUI**. It brings a pod to the end of any lab: for instructor catch-up, pod
recovery, and lab validation.

## Two ways to get it

| | Standalone zip | GitHub |
|---|---|---|
| Start | Extract anywhere, double-click `Start-LabRunner.cmd` | `irm https://raw.githubusercontent.com/Don-Paterson/CCAS-LabRunner/main/run-labrunner.ps1 \| iex` |
| Lab scripts pushed to the hosts | Inside the zip (`payload\`) | Taken from the A-GUI Desktop folder `Check Point Tools\Configuration Scripts` |
| Internet needed | No | Yes, for the download |
| Share with | ATC staff and students on the course only (contains courseware) | Anyone (no courseware in the repo) |

The two are the same code. `Build-Release.ps1` makes the zip from this folder.

## Requirements on A-GUI

- Windows PowerShell 5.1 or PowerShell 7 (the launcher uses 7 if installed)
- PuTTY (`plink.exe`, `pscp.exe`) in PATH or `C:\Program Files\PuTTY`
- Network access to A-SMS 10.1.1.101, A-GW 10.1.1.1, B-GW 198.51.100.1, C-GW 192.0.2.1

## Using it

Run **p. Preflight check** first: it pings each host, tests the SSH login,
lists which lab files were found, and tests the cached API key.

Then run the labs in order. In **Paced** mode (default) you confirm, skip or
abort each step. **Auto** mode runs a whole lab and stops at the first failed
step.

From a command prompt you can run one lab unattended:

```
Start-LabRunner.cmd -Lab 3A -Auto
```

Menu extras: **k** shows the cached `api_admin` API key (for Postman), **h**
clears the cached SSH host keys, **r** clears the completion marks.

## Step results

Every step is checked and shown as:

- **PASS**: no errors in the output.
- **WARN**: only "already exists" type errors, which are normal when a lab is re-run.
- **FAIL**: login failure, mgmt_cli error, SSH failure, copy failure, `Failed:` from the bash_api scripts, a host that did not come back after a reboot, and similar.
- **SKIP**: you skipped it, or an optional file was missing.

After a FAIL, Paced mode offers retry / continue / abort. Each lab ends with a
summary table, and is marked `[done]` only if no step failed.

## What V3 changes from V2

- Step results are checked (V2 marked labs done even when commands failed).
- SSH host keys that change after a FTW, Blink or pod reset are replaced automatically.
- The cached API key is tested at start-up and in Preflight. Lab 2A deletes and recreates `api_admin` if it already exists, so a fresh key is always issued.
- API keys are masked in the console and the log (menu **k** shows it on request).
- Reboots are detected on the SSH port, not ping (a gateway policy can drop ping): the runner waits for the host to go down, then for SSH logins to work again.
- Steps that reboot their host (1A first-time setup, 1B Blink) treat the dropped SSH session as expected instead of FAIL.
- clish steps send one command per SSH call and check the login shell each time; under bash the command is wrapped in `clish -c`.
- `CLINFR` clish errors (expected in 1A-2's `load configuration` with on-failure continue) count as WARN.
- Runs on Windows PowerShell 5.1 as well as 7, from a `.cmd` launcher.
- Lab steps are in `labs\*.psd1`; settings (hosts, password, version, JHF and Blink file names, FTW wait) are in `config.psd1`.
- Fixes carried from the courseware: timezones `America/St_Johns` and `Pacific/Honolulu` (no spaces), "Internal" typo in 4A-2.
- Lab 1B pushes the prepared `answers.xml` from the payload, if present.
- State and logs move to `%USERPROFILE%\.ccas-labrunner-v3\`, so V2 state is left alone.

## Deviations from the literal lab files (unchanged from V2)

| Lab | Lab file says | Runner does |
|-----|---------------|-------------|
| 1A | copy the A-SMS scripts with WinSCP | `pscp` from the payload / Desktop folder |
| 1A/1B | `expert` (interactive) | sets the `admin` shell to `/bin/bash` |
| 1A-2 | interactive `clish` | clish script via `clish -i -f`; `cpconfig` skipped |
| 1B-2 | edit files in vim | `clish_commands.txt` copied from `A-GW_config.sh`; `install_content.sh` generated without the example RPM line; `answers.xml` shown with a manual checkpoint |
| 2A | SmartConsole admin creation, API settings | `mgmt_cli` as `cpadmin`; key captured |
| 3A-3 / 3B-1 | edit `bash_api.sh` in vim | pushes `bash_api_verified-Groups.sh` / `-Policy.sh` |
| 4A | original or `-mod` file | original `/25` routes |
| 5A-2 | `watch` / `tail -F` monitors | fixed wait (`FTW_WAIT_SECONDS`, default 300) before the reboot, then waits for SSH |
| 5A-4 | `watch clish show installer` | install runs synchronously; needs cloud access from A-SMS |
| SmartConsole tasks | GUI | manual checkpoints |

## Layout

```
CCAS-LabRunner\
  Start-LabRunner.cmd     double-click start
  LabRunner.ps1           engine and menu
  config.psd1             hosts, password, version and file names
  VERSION
  labs\1A.psd1 ... 6A.psd1
  payload\                files pushed to the hosts (empty on GitHub)
  Build-Release.ps1       builds ..\dist\CCAS-LabRunner-V3-<version>.zip
  run-labrunner.ps1       GitHub irm|iex bootstrap
```

To change a lab, edit its `labs\*.psd1` file. Commands are single-quoted
here-strings, so `$SID` and other bash variables are written as-is.
`{{TOKEN}}` values come from `config.psd1`, and `__SESSION__` is replaced by an
API-key login on A-SMS.

To build the zip (payload must be filled in):

```
powershell -ExecutionPolicy Bypass -File Build-Release.ps1
```

## Notes

- The lab password (`Chkp!234`) is in `config.psd1`, as it is in the courseware. Sandbox use only.
- Re-running a lab gives WARN results for objects that already exist. For a clean run, revert the pod snapshot first.
- The runner never touches the Border-Router.

---
*Lab content source: DOC-Lab Commands-CCAS-R81.20-V1.0 (Check Point Learning &
Training). For Authorized Training Center use.*
