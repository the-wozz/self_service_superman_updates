#!/bin/bash

# What it do: S.U.P.E.R.M.A.N 4 [Jamf Pro] Self Service 'standalone' update check add-on with progressive windows and messages prior to being prompted with S.U.P.E.R.M.A.N.
# built-in failsafes and System Preferences fallback 
# Author: Zachary 'Woz'nicki
# Last updated: 11/21/24
# 1/22/24 - Calling S.U.P.E.R.M.A.N by full file location as opposed to 'symlink' due to possible issues and authentication?!
# 11/20/24 - optimizations to the script
# 11/21/24 - added macOS (15) Sequioa compatibility and SUPERMAN 5 support (with SUPERMAN 4 still in environment)
# 11/22/24 - added an additional measurement to determine if the user has an available 'soft count deferral' and writing a value to allow (to allow the Defer prompt to appear instead of right to install)
version="2.7"
date=11/22/24

############################## Assets Required ############################
# Jamf Pro 10.x
# macOS 11 [Big Sur] - macOS 14 [Sonoma], macOS 10 [Catalina] will only open System Preferences!
# S.U.P.E.R.M.A.N [x] https://github.com/Macjutsu/super
# SwiftDialog v2.3.2 [min] 2.5.2 + [recommended] https://github.com/swiftDialog/swiftDialog
# Icon image for Swift Dialog [OPTIONAL]
############################################################################

# Adjustable Variables #
# SUPER 5 Configuration Profile Name (used to determine IF SUPER 5 Policy can be used)
super5Profile='Super 5'
# SUPER 5 Policy
super5Policy="super5_mod"
# Swift Dialog Jamf Pro Policy, installs Swift Dialog via Github if this is left blank
swiftPolicy=""
# Swift Dialog icon location, icon used for Swift Dialog pop-up
swiftIcon=""
# Swift Dialog icon Jamf Pro Policy, to install if icon is missing [not required!]
iconPolicy=""
# S.U.P.E.R.M.A.N 4 Jamf Pro Policy
superPolicy="super"
# IBM Notifier Jamf Pro Policy [DEPRECATED]
#ibmNotifierPolicy="super_ibm_notifier"
# Fallback Method allows the script to open System Preferences/Settings if device does not have a Managed S.U.P.E.R.M.A.N plist
fallbackMethod=1
# Deployed S.U.P.E.R.M.A.N version in environment, used to verify if the local version is 'up-to-date', or will install the 'superPolicy' from Jamf Pro.
deployedSuperVersion="4.0.2"
# Swift Dialog Github URL (to download and install)
swiftDialogURL="https://github.com/swiftDialog/swiftDialog/releases/download/v2.5.4/dialog-2.5.4-4793.pkg"
# Swift Dialog version gathered from the URL
swiftVersion=$(echo "$swiftDialogURL" | cut -d '/' -f 8 | tr -d v)

# DO NOT TOUCH Variables #
# Swift Dialog binary
swiftDialogBin="/usr/local/bin/dialog"
# Swift Dialog Command File
commandFile="/var/tmp/dialog.log"
# S.U.P.E.R.M.A.N file
superBin="/Library/Management/super/super"
# S.U.P.E.R.M.A.N version
superVersion=$(defaults read /Library/Management/super/com.macjutsu.super.plist SuperVersion)
# S.U.P.E.R.M.A.N log file
superLog="/Library/Management/super/logs/super.log"
# S.U.P.E.R.M.A.N plist
#realSuperPlist="/Library/Management/super/com.macjutsu.super.plist"
# MANAGED (Jamf) S.U.P.E.R.M.A.N plist
superPlist="/Library/Managed Preferences/com.macjutsu.super.plist"
# macOS version
osVersion=$(sw_vers -productVersion)
osVersionSimple=$(sw_vers -productVersion | cut -d'.' -f1)
# End Variables #

## Start Functions ##
# checks if the Swift Dialog icon exists, if not, downloads it via the iconPolicy from Jamf Pro
iconCheck() {
    echo "* SWIFT DIALOG ICON CHECK *"
        if [[ ! -f "$swiftIcon" ]]; then
            echo "*** WARNING: Icon image set but icon NOT found at location. ***"
                if [[ -z "$iconPolicy" ]]; then
                    echo "* WARNING: No icon policy set! Using default 'Swift Dialog' System Preferences/Settings icon. *"
                elif [[ -n "$iconPolicy" ]]; then
                    echo "Calling Jamf Pro Policy: $iconPolicy"
                    jamf policy -event "$iconPolicy"
                fi
        elif [[ -f "$swiftIcon" ]]; then
            echo "* CHECK PASSED: Icon found. Continuing... *"
        elif [[ -z "$swiftIcon" ]]; then
            echo "* INFO: No Swift Dialog icon set. Bypassing 'iconPolicy' variable. Using default 'Swift Dialog' System Preferences/Settings icon. *"
        fi
}

# checks if Swift Dialog is installed AND the version desired, if older, deletes and downloads, installs the latest via the 'swiftPolicy' from Jamf Pro.
swiftDialogCheck() {
    echo "* SWIFT DIALOG CHECK *"
        if [[ ! -e "$swiftDialogBin" ]]; then
            echo "Swift Dialog NOT FOUND! Unable to prompt user."
                if [[ -z "$swiftPolicy" ]]; then
                    echo "* WARNING: Swift Dialog Jamf Pro Policy NOT set! *"
                        echo "Using Github as download source"
                            downloadSwiftDialog
                                wait
                elif [[ -n "$swiftPolicy" ]]; then
                    echo  "Calling Swift Dialog policy"
                    jamf policy -event "$swiftPolicy"
                fi
        else
            echo "INITIAL CHECK PASSED: Swift Dialog found. Checking version..."
            swiftDInstalledVersion=$("$swiftDialogBin" --version | cut -c1-5)
            echo "Swift Dialog version: $swiftDInstalledVersion"
                if [[ "$swiftDInstalledVersion" < "$swiftVersion" ]]; then
                    echo "Swift Dialog version too old! $swiftVersion required."
                            # these commands make sure that any currently open Swift Dialog prompt is closed
                            /bin/echo quit: >> /var/tmp/dialog.log
                            pkill -f dialog
                        if [[ -n "$swiftPolicy" ]]; then
                            echo  "Calling Swift Dialog policy"
                            jamf policy -event "$swiftPolicy"
                        elif [[ -z "$swiftPolicy" ]]; then
                            echo "* WARNING: Swift Dialog Jamf Pro Policy NOT set! *"
                            echo "Using Github as download source"
                            downloadSwiftDialog
                                wait
                            #echo "*** ERROR: Unable to prompt user because of Swift Dialog failure above ***"
                            #exit 1
                        fi
                else
                    echo "* Swift Dialog version PASSED *"
                fi
        fi
}

# downloads Swift Dialog via GitHub
downloadSwiftDialog(){
    echo "* SWIFT DIALOG: Flagged for DOWNLOAD! *"

    if [[ -n "$swiftDialogURL" ]]; then
        echo "SWIFT DIALOG: URL Provided: $swiftDialogURL"

        local filename
            filename=$(basename "$swiftDialogURL")
        local temp_file
            temp_file="/tmp/$filename"
        previous_umask=$(umask)
        umask 077

        /usr/bin/curl --retry 5 --retry-max-time 120 -Ls "$swiftDialogURL" -o "$temp_file" 2>&1
            if [[ $? -eq 0 ]]; then
                echo "SWIFT DIALOG: DOWNLOADED successfully! Installing..."
                        /usr/sbin/installer -verboseR -pkg "$temp_file" -target / 2>&1
                            if [[ $? -eq 0 ]]; then
                                echo "SWIFT DIALOG: INSTALLED!"
                            else
                                echo "**** ERROR: SWIFT DIALOG: Unable to instal! Can NOT continue! Exiting... *****"
                                exit 1
                            fi

                rm -Rf "${temp_file}" >/dev/null 2>&1
                umask "${previous_umask}"
                return
            else
                echo "**** ERROR: SWIFT DIALOG: Download FAILED!! Can NOT continue! Exiting... *****"
                exit 1
            fi
    else
        echo "* SWIFT DIALOG: ERROR: NO swiftDialogURL provided! *"
        echo "Exiting..."
        exit 1
    fi
}

# # DEPRECATED 11/20/24. Swift Dialog is more suited for my desired effect
# removes IBM Notifier
# deleteIBMNotifier() {
#     echo "1 Time Run: Delete IBM Notifier and reinstall if found..."
#     if [[ -e "/Library/Management/super/IBM Notifier.app" ]]; then
#         echo "IBM Notifier found. Deleting..."
#         rm -rf "/Library/Management/super/IBM Notifier.app" & sleep 2
#     else
#         echo "IBM Notifier not found, continuing..."
#     fi
# }

# # DEPRECATED 11/20/24. Swift Dialog is more suited for my desired effect
# checks for IBM Notifier and downloads and installs the latest if not
# ibmNotifierCheck(){
#     echo "* IBM NOTIFIER CHECK *"
#     ibmNotifier_Bin="/Library/Management/super/IBM Notifier.app/Contents/MacOS/IBM Notifier"
#     ibmNotifier="/Library/Management/super/IBM Notifier.app"
#     if [[ -e "$ibmNotifier" ]]; then
#         ibmNotifierVersion=$("$ibmNotifier_Bin" --version | awk '{print $4}')
#         echo "IBM Notifier version: $ibmNotifierVersion"
#             if [[ "$ibmNotifierVersion" < "3.0.2" ]]; then
#                 echo "** CHECK FAILED: IBM Notifier version too old! **"
#                     if [[ -n "$ibmNotifierPolicy" ]]; then
#                         echo "Calling Jamf Pro Policy: $ibmNotifierPolicy"
#                         jamf policy -event "$ibmNotifierPolicy"
#                     elif [[ "$ibmNotifierPolicy" == "X" ]]; then
#                         echo "Passing IBM Notifier download to S.U.P.E.R.M.A.N / GitHub"
#                     elif [[ -z "$ibmNotifierPolicy" ]]; then
#                         echo "ERROR: No IBM Notifier Policy set! Exiting..."
#                         exit 1
#                     fi
#             elif [[ "$ibmNotifierVersion" > "3.0.1" ]]; then
#                 echo "* CHECK PASSED: IBM Notifier version 3.0.2 or greater! *"
#             fi
#     elif [[ ! -e "$ibmNotifier" ]] && [[ -n "$ibmNotifierPolicy" ]]; then
#         echo "IBM Notifier does not exist! Calling Jamf Pro Policy: $ibmNotifierPolicy"
#         ibmNotifierPolicy
#     elif [[ ! -e "$ibmNotifier" ]] && [[ -z "$ibmNotifierPolicy" ]]; then
#         echo "* CHECK FAILED: IBM Notifier not found! *"
#         echo "* ERROR: No IBM Notifier Policy set! Exiting... *"
#         exit 1
#     fi
# }

# DEPRECATED 11/20/24. Swift Dialog is more suited for my desired effect
# Jamf Pro policy call for IBM Notifier.
# ibmNotifierPolicy () {
#     jamf policy -event "$ibmNotifierPolicy"
#     wait
#     ibmNotifierCheck
# }

# initial Self Service Swift Dialog prompt when running the 'Check for Updates' policy
ssWindow() {
    "$swiftDialogBin" -o -p --progress --progresstext "Searching for compatible required updates..." \
    --button1disabled --centericon -i "$swiftIcon" -iconsize 80 \
    --title "Checking for macOS Updates" --titlefont size="17" \
    --message "macOS version: $osVersion" --messagefont size="11" --messagealignment center \
    --position bottomright --width 400 --height 220 & sleep 0.1
        # Exit button handling when enabled --button2enabled
        # case $? in
        #     2)
        #         echo "User pressed Exit button"
        #         exit 2
        #     ;;
        # esac
}

# generates the Swift Dialog prompt for the update list array
updatesAvailable_Win() {
    "$swiftDialogBin" -o -p --progress --hideicon --button1text none \
    --title "Available Updates:" --titlefont size="18" \
    --message "" --messagefont size="15" \
    --position bottomright --width 400 --height 220 & sleep 0.1
}

# checks for updates via Software Update and then notifies the user that an update is available and SUPER will start it's update process 
checkUpdates() {
    echo "Current macOS version: $osVersion"
    #echo "Targeting updates on macOS version: $updateVersion"

    # added Sequoia support - 11/21/24
        if [[ "$osVersionSimple" == "15" ]]; then
            echo "Checking softwareupdate on Sequoia..."
            availableUpdates=$(softwareupdate -l | grep "Title:" | cut -d ',' -f1 | awk -F ':' '{print $2}' | sed 's/ //' | grep -v "Sonoma" | sort -r)
        elif [[ "$osVersionSimple" == "14" ]]; then
            echo "Checking softwareupdate on Sonoma..."
            availableUpdates=$(softwareupdate -l | grep "Title:" | cut -d ',' -f1 | awk -F ':' '{print $2}' | sed 's/ //' | grep -v "Sequoia" | sort -r)
        elif [[ "$osVersionSimple" == "13" ]]; then
            echo "Checking softwareupdate on Ventura..."
            availableUpdates=$(softwareupdate -l | grep "Title:" | cut -d ',' -f1 | awk -F ':' '{print $2}' | sed 's/ //' | grep -v "Monterey" | grep -v "Sonoma" | sort -r)
        elif [[ "$osVersionSimple" == "12" ]] && [[ "$updateVersion" == "X" ]]; then
            echo "Checking softwareupdate on Monterey...(No upgrades allowed)"
            availableUpdates=$(softwareupdate -l | grep "Title:" | cut -d ',' -f1 | awk -F ':' '{print $2}' | sed 's/ //' | grep -v "Ventura" | grep -v "Sonoma" | sort -r)
        elif [[ "$osVersionSimple" == "12" ]] && [[ "$updateVersion" == "13" ]]; then
            echo "Checking softwareupdate on Ventura..."
            availableUpdates=$(softwareupdate -l | grep "Title:" | cut -d ',' -f1 | awk -F ':' '{print $2}' | sed 's/ //' | grep -v "Monterey" | grep -v "Sonoma" | sort -r)
        elif [[ "$osVersionSimple" == "11" ]]; then
            echo "Checking softwareupdate on Ventura..."
            availableUpdates=$(softwareupdate -l | grep "Title:" | cut -d ',' -f1 | awk -F ':' '{print $2}' | sed 's/ //' | grep -v "Monterey" | grep -v "Sonoma" | sort -r)
        elif [[ "$osVersionSimple" == "10" ]]; then
            echo "*** WARNING: macOS version too old [10/Catalina] to update via S.U.P.E.R.M.A.N! Sending to System Preferences... ***"
            sysPreferences
        fi

            if [[ "$availableUpdates" == *"macOS"* ]]; then
                echo "progresstext: macOS update found! ✅" >> ${commandFile}
                sleep 3
            fi

            if [[ "$availableUpdates" == *"Safari"* ]]; then
                safariUpdate=1
                echo "progresstext: Safari update found! ✅" >> ${commandFile}
                echo "Safari update available, grabbing version.."
                safariUpdateVersion=$(softwareupdate -l | grep "Title" | grep "Safari" | awk '{print $4}' | cut -d ',' -f1)
                safariUpdateComp=$(echo "Safari $safariUpdateVersion")
                sleep 3
            fi

            if [[ -n "$availableUpdates" ]]; then
                echo "quit:" >> ${commandFile} && updatesAvailable_Win
                echo "* SOFTWAREUPDATE: Update(s) available! *"
                IFS=$'\n'
                availableUpdates=("$availableUpdates")

                    for (( i=0; i<${#availableUpdates[@]}; i++ ))
                        do
                                if [[ "$safariUpdate" -eq 1 ]]; then
                                    for value in "${availableUpdates[@]}"
                                        do
                                        [[ $value != Safari ]] && new_array+=($availableUpdates)
                                        done
                                    availableUpdates=("${new_array[@]}")
                                    availableUpdates+=("$safariUpdateComp")
                                    echo "$i: ${availableUpdates[$i]}"
                                    safariUpdate=0
                                else
                                    echo "$i: ${availableUpdates[$i]}"
                                fi
                        done

                totalUpdates=${#availableUpdates[*]}
                echo "Total updates: $totalUpdates"
                echo "progresstext: Preparing to download updates..." >> ${commandFile}

                    if [[ "$totalUpdates" -eq 1 ]]; then
                        echo "height: 180" >> ${commandFile} &
                        echo "list: ${availableUpdates[0]}" >> ${commandFile}
                        echo "listitem: ${availableUpdates[0]}: wait" >> ${commandFile}
                    elif [[ "$totalUpdates" -eq 2 ]]; then
                        echo "height: 230" >> ${commandFile} &
                        echo "list: ${availableUpdates[0]}, ${availableUpdates[1]}" >> ${commandFile}
                        echo "listitem: ${availableUpdates[0]}: wait" >> ${commandFile} &
                        echo "listitem: ${availableUpdates[1]}: wait" >> ${commandFile}
                    elif [[ "$totalUpdates" -eq 3 ]]; then
                        echo "height: 280" >> ${commandFile} &
                        echo "list: ${availableUpdates[0]}, ${availableUpdates[1]}, ${availableUpdates[2]}" >> ${commandFile}
                        echo "listitem: ${availableUpdates[0]}: wait" >> ${commandFile} &
                        echo "listitem: ${availableUpdates[1]}: wait" >> ${commandFile} &
                        echo "listitem: ${availableUpdates[2]}: wait" >> ${commandFile}
                    fi
                sleep 5
            else
                echo "* SOFTWAREUPDATE: No updates available/found. *"
                echo "Running S.U.P.E.R.M.A.N just in-case..."
                /Library/Management/super/super
                sleep 3
                echo "Notifying user that 0 updates are available."
                echo "quit:" >> ${commandFile}
                noUpdateMessage
            fi
}

# message to show user [via Swift Dialog] when there is no updates available so they are not left with Self Service policy completed with no messages of what happened
noUpdateMessage() {
    $swiftDialogBin -o -p -i "$swiftIcon" --iconsize 65 --centericon \
    --title "macOS Up-to-Date" --titlefont size="18" \
    --message "No available updates found.<br>Please allow a few minutes for any other possible updates that may be preparing." --messagefont size="15" --messageposition center --messagealignment center \
    --button1text: "OK" --helpmessage "If you were expecting updates, please try restarting this Mac and running the policy again." \
    --position bottomright  --width 400 --height 220 & sleep 0.1
        echo "activate:" >> ${commandFile} & exit 0
}

# checks to make sure there is SUPERMAN Configuration Profile or SUPER will not work
checkSuperPlist() {
    profiles=$(profiles show)
    # checks for which version of SUPER is supported on the machine (determined by the Configuration Profile name, needs to be more dynamic but working for the moment)
        if [[ "$profiles" == *"$super5Profile"* ]]; then
            superV='5.0.0'
        else
            superV='4.0.2'
        fi
            echo "SUPER $superV"

        # check for SUPER plists
        # if SUPER plist is NOT FOUND and fallbackMethod is NOT ENABLED (0) then we have to exit as nothing can be done
        if [[ ! -f "$superPlist" ]] && [[ "$fallbackMethod" -eq 0 ]]; then
            echo "*** CRITICAL: S.U.P.E.R.M.A.N plist NOT found AND 'Fallback Method disabled' ! ***"
            echo "*** CHECK FAILED: Machine not scoped for S.U.P.E.R.M.A.N or possibly needs reboot! ***"
            echo "title: Unable To Find Updates" >> ${commandFile} &
            echo "progresstext: Exiting..." >> ${commandFile}
            echo "progress: 1" >> ${commandFile}
            sleep 15
            echo "quit:" >> ${commandFile}
            exit 1
        # if SUPER plist is NOT FOUND and fallbackMethod is ENABLED (1) we can open System Preferences/Settings for user
        elif [[ ! -f "$superPlist" ]] && [[ "$fallbackMethod" -eq 1 ]]; then
            echo "* Fallback Method Enabled *"
            echo "*** WARNING: Machine not scoped for S.U.P.E.R.M.A.N or possibly needs reboot! ***"
            sysPreferences
            exit 0
        # NORMAL PROCESSING HERE! If we find a SUPER plist we can use SUPER to prompt the user
        elif [[ -f "$superPlist" ]]; then
            echo "* CHECK PASSED: Managed S.U.P.E.R.M.A.N Preferences found. Continuing... *"
            updateVersion=$(defaults read "$superPlist" InstallMacOSMajorVersionTarget)
        fi
}

# command to open System Preferences/Settings 'Software Updates' section
sysPreferences(){
            echo "progresstext: Opening System Preferences to update..." >> ${commandFile}
            echo "Opening System Settings for user and exiting prompt..."
            open -b com.apple.systempreferences "/System/Library/PreferencePanes/SoftwareUpdate.prefPane"
            sleep 5
            echo "quit:" >> ${commandFile}
}

# 11/22/24 addition
# this checks for the number of 'deferrals' available to the user and writes a new value if the user has no 'deferrals' available (to show the SUPERMAN defer prompt)
# this was created to stop users from going right-to-install when they have no more 'Soft Count deferrals' available
superCounter(){
    echo "Checking S.U.P.E.R.M.A.N 'Deferral counts'..."
    superlocalPlist=/Library/Management/super/com.macjutsu.super.plist

    # check to make sure the local SUPER plist exists, no need to write any values if it does not
    if [[ -e "$superlocalPlist" ]]; then
        echo "FOUND S.U.P.E.R.M.A.N plist! Able to proceeed..."
    else
        return
    fi

    # this is the max number of 'deferrals' [count]
    deadlineCount=$(defaults read $superlocalPlist DeadlineCountSoft)
        #echo "Deadline Count: $deadlineCount"

    # this is the current number of 'deferrals' [counter]
    deadlineCounter=$(defaults read $superlocalPlist DeadlineCounterSoft)
        echo "Deadline Counter Soft: $deadlineCounter"

        # check to make sure the user has a 'deferral' available (1) to allow the SUPER screen to show up without going straight to install
        if [[ "$deadlineCounter" -ge 4 ]]; then
            echo "** CAUTION: USER has NO (0) deferrals left! **"
            echo "Setting 'DeadlineCounterSoft' (in /Library/Management/super/com.macjutsu.super.plist) to '3' to allow for SUPER deferral window for 1 time..."
                set -x 
            defaults write $superlocalPlist DeadlineCounterSoft 3
                set +x
        else
            echo "CHECK COMPLETE: Deferral count will not impede the 'workflow'."
        fi
    }

# checks for local install of SUPERMAN and installs the latest version via the 'superPolicy' IF not installed
superCheck() {
    echo "* INITIAL CHECK: S.U.P.E.R.M.A.N *"

        # checks for versioning of SUPER[MAN] between the script version and Configuration Profile version
        # a bit extra but with multiple versions of SUPER in the environment, this is a good 'failsafe' to have (in my non-expert opinion)
        # SUPER found and Configuration File version matches the version found in Profiles
        if [[ -e "$superBin" ]] && [[ "$superV" == "$superVersion" ]]; then
            echo "* CHECK PASSED: S.U.P.E.R.M.A.N found! *"
            echo "STATUS: Calling S.U.P.E.R.M.A.N and tailing super.log"
            echo "progresstext: Preparing to download updates..." >> ${commandFile}
            sleep 5
            /Library/Management/super/super | superTail
        # SUPER found BUT Configuration File version does NOT match the version found in the Profiles
        elif [[ -e "$superBin" ]] && [[ "$superV" != "$superVersion" ]]; then
            echo "* WARNING: S.U.P.E.R.M.A.N found BUT version out-of-date! Removing... *"
            rm -rf "/Library/Management/super"
            echo "Calling S.U.P.E.R.M.A.N: $superVersion Jamf Pro Policy"
                superInstall
        # SUPER does NOT exist
        elif [[ ! -e "$superBin" ]]; then
            echo "* CHECK FAILED: S.U.P.E.R.M.A.N NOT found! *"
                # superPolicy not blank
                if [[ -n "$superPolicy" ]]; then
                    superInstall
                # superPolicy IS BLANK, can NOT continue!
                elif [[ -z "$superPolicy" ]]; then
                    echo "superPolicy not set! Unable to download S.U.P.E.R.M.A.N. Exiting..."
                    echo "title: Unable To Complete Updates" >> ${commandFile} &
                    echo "progresstext: Update tool [SUPER] not found! Exiting..." >> ${commandFile} &
                    echo "progress: 1" >> ${commandFile}
                    sleep 12
                    echo "quit:" >> ${commandFile}
                    exit 1
                fi
        fi
}

# tails the super.log and provides updates to the user on what is happening in the background via Swift Dialog update messages until SUPER pops-up for the user
superTail() {
    while IFS= read -r line; do
            echo "progresstext: Downloading update(s)..." >> ${commandFile}

            # found previously downloaded update(s)
            if [[ $line == *"Previously downloaded macOS minor update is prepared"* ]]; then
                echo "title: Download Complete" >> ${commandFile} &
                echo "progresstext: Updates downloaded! Preparing..." >> ${commandFile} &
                echo "progress: complete" >> ${commandFile}
                echo "S.U.P.E.R.M.A.N: Previous download found!"
            fi

            # downloading update(s)
            if [[ $line == *"Downloading:"* ]]; then
                echo "title: Downloading Updates" >> ${commandFile} &
                echo "progresstext: $line" >> ${commandFile} &
                echo "progress: 50" >> ${commandFile}
                # Add ability to show progress from download to live progress percent
                #echo "progress: $downloadProgress" >> ${commandFile}
            fi

            # downloading update(s) alternate wording
            if [[ $line == *"downloading..."* ]]; then
                echo "title: Downloading Updates" >> ${commandFile} &
                echo "progresstext: Downloading update..." >> ${commandFile}
                echo "progress: 50" >> ${commandFile}
            fi

            # update is downloaded and preparing
            if [[ $line == *"Downloaded:"* ]] || [[ $line == *"downloaded"* ]] || [[ $line == *"download and preperation complete"* ]]; then
                echo "progresstext: Downloaded! Preparing updates..." >> ${commandFile} &
                echo "progress: 75" >> ${commandFile}
            fi

            # SUPER is about to prompt the user
            if [[ $line == *"IBM Notifier: Restart or defer dialog with no timeout"* ]] || [[ $line == *"IBM Notifier: User authentication deadline count dialog"* ]] || [[ $line == *"User choice dialog with no timeout."* ]]; then
                echo "title: Updates Ready To Install" >> ${commandFile}
                    # set the icon for each update item in the array item to a checkmark (success)
                    if [[ "$totalUpdates" -eq 1 ]]; then
                        echo "listitem: ${availableUpdates[0]}: success" >> ${commandFile}
                    elif [[ "$totalUpdates" -eq 2 ]]; then
                        echo "listitem: ${availableUpdates[0]}: success" >> ${commandFile} &
                        echo "listitem: ${availableUpdates[1]}: success" >> ${commandFile}
                    elif [[ "$totalUpdates" -eq 3 ]]; then
                        echo "listitem: ${availableUpdates[0]}: success" >> ${commandFile} &
                        echo "listitem: ${availableUpdates[1]}: success" >> ${commandFile} &
                        echo "listitem: ${availableUpdates[2]}: success" >> ${commandFile}
                    fi
                echo "progresstext: Preparing update notification" >> ${commandFile} &
                echo "progress: complete" >> ${commandFile}
                echo "Download complete. User prompted with SUPER."
                sleep 4
                echo "quit:" >> ${commandFile}
                    exit 0
            fi

        done
}

# installs SUPER and updates the user via the Swift Dialog window
superInstall() {
    echo "progresstext: Downloading update & notification tool..." >> ${commandFile}
    # depending on which superVersion was found earlier, the policy will call the correct SUPER version policy
    if [[ $superV -eq 5 ]]; then
        echo "STATUS: SUPER 5 detected."
        echo "STATUS: Calling Jamf Pro Policy: $super5Policy"
            jamf policy -event "$super5Policy" &>/dev/null & disown;
    else
        echo "STATUS: SUPER 4 detected."
        echo "STATUS: Calling Jamf Pro Policy: $superPolicy"
            jamf policy -event "$superPolicy" &>/dev/null & disown;
    fi
        # wait for super Log File to be found
        until [[ -e "$superLog" ]]; do
            #echo "S.U.P.E.R.M.A.N does not exist yet..."
            echo "progresstext: Installing update & notification tool..." >> ${commandFile}
            sleep 1
        done

    echo "progresstext: Update & notification tool installed!" >> ${commandFile}
    echo "S.U.P.E.R.M.A.N installed successfully!"
    sleep 5
    echo "progresstext: Preparing to download updates..." >> ${commandFile}
    tail -f "$superLog" | superTail
}
## End Functions

### Begin Main Body ###
echo "Script Version: $version [Last Update: $date]"

iconCheck
    swiftDialogCheck
#deleteIBMNotifier
    #ibmNotifierCheck
ssWindow
    checkSuperPlist
checkUpdates
    superCounter
superCheck
# End Body
#exit 0
