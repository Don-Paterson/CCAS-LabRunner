# CCAS Lab Runner V3 - settings.
# Change these values to reuse the runner for another lab build or version;
# the lab step files in labs\ stay unchanged.
@{
    # SSH login used for every Gaia host (lab constant, as in the courseware)
    User     = 'admin'
    Password = 'Chkp!234'

    # Hosts the runner connects to (name used in labs\*.psd1 -> IP)
    Hosts = @{
        'A-SMS' = '10.1.1.101'
        'A-GW'  = '10.1.1.1'
        'B-GW'  = '198.51.100.1'
        'C-GW'  = '192.0.2.1'
    }

    # Values substituted for {{TOKEN}} placeholders in labs\*.psd1
    # ({{PASS}} is always the Password above)
    Tokens = @{
        CP_VERSION       = 'R81.20'
        JHF_PACKAGE      = 'Check_Point_R81_20_JUMBO_HF_MAIN_Bundle_T26_FULL.tgz'
        BLINK_IMAGE      = 'blink_image_1.1_Check_Point_R81.20_T631_JHF_T26_SecurityGateway.tgz'
        FTW_WAIT_SECONDS = '300'   # 5A-2: wait between remote FTW settings and reboot
    }

    # Where 'copy' steps look for files: payload\ beside the runner first,
    # then this folder on the A-GUI Desktop (the GitHub copy has no payload).
    FallbackScriptsDir = '%USERPROFILE%\Desktop\Check Point Tools\Configuration Scripts'

    # Order the labs appear in the menu (files in labs\)
    LabOrder = @('1A','1B','2A','3A','3B','4A','5A','6A')
}
