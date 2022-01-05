#!/bin/bash
#
# description: MegaCLI script to configure and monitor LSI raid cards.

# Full path to the MegaRaid CLI binary
MegaCli="/usr/sbin/megacli"

ENCLOSURE="8"
ADAPTER="All"
COMMAND=""


if [ $# -eq 0 ]
   then
    echo ""
    echo "            OBPG  .:.  lsi.sh $arg1 $arg2"
    echo "-----------------------------------------------------"
    echo "status        = Status of Virtual drives (volumes)"
    echo "drives        = Status of hard drives"
    echo "ident \$slot   = Blink light on drive (need slot number)"
    echo "good \$slot    = Simply makes the slot \"Unconfigured(good)\" (need slot number)"
    echo "replace \$slot = Replace \"Unconfigured(bad)\" drive (need slot number)"
    echo "progress      = Status of drive rebuild"
    echo "errors        = Show drive errors which are non-zero"
    echo "bat           = Battery health and capacity"
    echo "batrelearn    = Force BBU re-learn cycle"
    echo "logs          = Print card logs"
    echo "checkNemail   = Check volume(s) and send email on raid errors"
    echo "allinfo       = Print out all settings and information about the card"
    echo "settime       = Set the raid card's time to the current system time"
    echo "setdefaults   = Set preferred default settings for new raid setup"
    echo ""
   exit
 fi

for i in "$@"
do
case $i in
    -a=*|--adapter=*)
    ADAPTER="${i#*=}"
    shift # past argument=value
    ;;
    -e=*|--enclosure=*)
    ENCLOSURE="${i#*=}"
    shift # past argument=value
    ;;
    *)
	COMMAND="${i#*=}"
	shift;
	;;
esac
done
# General status of all RAID virtual disks or volumes and if PATROL disk check
# is running.
if [ $COMMAND = "status" ]
   then
      $MegaCli -LDInfo -Lall -a$ADAPTER -NoLog
      echo "###############################################"
      $MegaCli -AdpPR -Info -a$ADAPTER -NoLog
      echo "###############################################"
      $MegaCli -LDCC -ShowProg -LALL -a$ADAPTER -NoLog
   exit
fi

# Shows the state of all drives and if they are online, unconfigured or missing.
if [ $COMMAND = "drives" ]
   then
      $MegaCli -PDlist -a$ADAPTER -NoLog | egrep 'Slot|state' | awk '/Slot/{if (x)print x;x="";}{x=(!x)?$0:x" -"$0;}END{print x;}' | sed 's/Firmware state://g'
   exit
fi
# Shows the state of all drives and if they are online, unconfigured or missing.
if [ $COMMAND = "driveinfo" ]
   then
      $MegaCli -PDinfo -a$ADAPTER -NoLog | egrep 'Slot|state' | awk '/Slot/{if (x)print x;x="";}{x=(!x)?$0:x" -"$0;}END{print x;}' | sed 's/Firmware state://g'
   exit
fi

# Use to blink the light on the slot in question. Hit enter again to turn the blinking light off.
if [ $COMMAND = "ident" ]
   then
      $MegaCli  -PdLocate -start -physdrv[$ENCLOSURE:$2] -a0 -NoLog
      logger "`hostname` - identifying enclosure $ENCLOSURE, drive $2 "
      read -p "Press [Enter] key to turn off light..."
      $MegaCli  -PdLocate -stop -physdrv[$ENCLOSURE:$2] -a0 -NoLog
   exit
fi

# When a new drive is inserted it might have old RAID headers on it. This
# method simply removes old RAID configs from the drive in the slot and make
# the drive "good." Basically, Unconfigured(bad) to Unconfigured(good). We use
# this method on our FreeBSD ZFS machines before the drive is added back into
# the zfs pool.
if [ $COMMAND = "good" ]
   then
      # set Unconfigured(bad) to Unconfigured(good)
      $MegaCli -PDMakeGood -PhysDrv[$ENCLOSURE:$2] -a0 -NoLog
      # clear 'Foreign' flag or invalid raid header on replacement drive
      $MegaCli -CfgForeign -Clear -a$ADAPTER -NoLog
   exit
fi

# Use to diagnose bad drives. When no errors are shown only the slot numbers
# will print out. If a drive(s) has an error you will see the number of errors
# under the slot number. At this point you can decided to replace the flaky
# drive. Bad drives might not fail right away and will slow down your raid with
# read/write retries or corrupt data. 
if [ $COMMAND = "errors" ]
   then
      echo "Slot Number: 0"; $MegaCli -PDlist -a$ADAPTER -NoLog | egrep -i 'error|fail|slot' | egrep -v ' 0'
   exit
fi

# status of the battery and the amount of charge. Without a working Battery
# Backup Unit (BBU) most of the LSI read/write caching will be disabled
# automatically. You want caching for speed so make sure the battery is ok.
if [ $COMMAND = "bat" ]
   then
      $MegaCli -AdpBbuCmd -aAll -NoLog
   exit
fi

# Force a Battery Backup Unit (BBU) re-learn cycle. This will discharge the
# lithium BBU unit and recharge it. This check might take a few hours and you
# will want to always run this in off hours. LSI suggests a battery relearn
# monthly or so. We actually run it every three(3) months by way of a cron job.
# Understand if your "Current Cache Policy" is set to "No Write Cache if Bad
# BBU" then write-cache will be disabled during this check. This means writes
# to the raid will be VERY slow at about 1/10th normal speed. NOTE: if the
# battery is new (new bats should charge for a few hours before they register)
# or if the BBU comes up and says it has no charge try powering off the machine
# and restart it. This will force the LSI card to re-evaluate the BBU. Silly
# but it works.
if [ $COMMAND = "batrelearn" ]
   then
      $MegaCli -AdpBbuCmd -BbuLearn -a$ADAPTER -NoLog
   exit
fi

# Use to replace a drive. You need the slot number and may want to use the
# "drives" method to show which drive in a slot is "Unconfigured(bad)". Once
# the new drive is in the slot and spun up this method will bring the drive
# online, clear any foreign raid headers from the replacement drive and set the
# drive as a hot spare. We will also tell the card to start rebuilding if it
# does not start automatically. The raid should start rebuilding right away
# either way. NOTE: if you pass a slot number which is already part of the raid
# by mistake the LSI raid card is smart enough to just error out and _NOT_
# destroy the raid drive, thankfully.
if [ $COMMAND = "replace" ]
   then
      logger "`hostname` - REPLACE enclosure $ENCLOSURE, drive $2 "
      # set Unconfigured(bad) to Unconfigured(good)
      $MegaCli -PDMakeGood -PhysDrv[$ENCLOSURE:$2] -a$ADAPTER -NoLog
      # clear 'Foreign' flag or invalid raid header on replacement drive
      $MegaCli -CfgForeign -Clear -a$ADAPTER -NoLog
      # set drive as hot spare
      $MegaCli -PDHSP -Set -PhysDrv [$ENCLOSURE:$2] -a$ADAPTER -NoLog
      # show rebuild progress on replacement drive just to make sure it starts
      $MegaCli -PDRbld -ShowProg -PhysDrv [$ENCLOSURE:$2] -a$ADAPTER -NoLog
   exit
fi

# Print all the logs from the LSI raid card. You can grep on the output.
if [ $COMMAND = "logs" ]
   then
      $MegaCli -FwTermLog -Dsply -a$ADAPTER -NoLog
   exit
fi

# Use to query the RAID card and find the drive which is rebuilding. The script
# will then query the rebuilding drive to see what percentage it is rebuilt and
# how much time it has taken so far. You can then guess-ti-mate the
# completion time.
if [ $COMMAND = "progress" ]
   then
      DRIVE=`$MegaCli -PDlist -a$ADAPTER -NoLog | egrep 'Slot|state' | awk '/Slot/{if (x)print x;x="";}{x=(!x)?$0:x" -"$0;}END{print x;}' | sed 's/Firmware state://g' | egrep build | awk '{print $3}'`
      $MegaCli -PDRbld -ShowProg -PhysDrv [$ENCLOSURE:$DRIVE] -a$ADAPTER -NoLog
   exit
fi

# Use to check the status of the raid. If the raid is degraded or faulty the
# script will send email to the address in the $EMAIL variable. We normally add
# this method to a cron job to be run every few hours so we are notified of any
# issues.
if [ $COMMAND = "checkNemail" ]
   then
      EMAIL="raidadmin@localhost"

      # Check if raid is in good condition
      STATUS=`$MegaCli -LDInfo -Lall -a$ADAPTER -NoLog | egrep -i 'fail|degrad|error'`

      # On bad raid status send email with basic drive information
      if [ "$STATUS" ]; then
         $MegaCli -PDlist -a$ADAPTER -NoLog | egrep 'Slot|state' | awk '/Slot/{if (x)print x;x="";}{x=(!x)?$0:x" -"$0;}END{print x;}' | sed 's/Firmware state://g' | mail -s `hostname`' - RAID Notification' $EMAIL
      fi
fi

# Use to print all information about the LSI raid card. Check default options,
# firmware version (FW Package Build), battery back-up unit presence, installed
# cache memory and the capabilities of the adapter. Pipe to grep to find the
# term you need.
if [ $COMMAND = "allinfo" ]
   then
      $MegaCli -AdpAllInfo -aAll -NoLog
   exit
fi

# Update the LSI card's time with the current operating system time. You may
# want to setup a cron job to call this method once a day or whenever you
# think the raid card's time might drift too much. 
if [ $COMMAND = "settime" ]
   then
      $MegaCli -AdpGetTime -a$ADAPTER -NoLog
      $MegaCli -AdpSetTime `date +%Y%m%d` `date +%H:%M:%S` -a$ADAPTER -NoLog
      $MegaCli -AdpGetTime -a$ADAPTER -NoLog
   exit
fi

# These are the defaults we like to use on the hundreds of raids we manage. You
# will want to go through each option here and make sure you want to use them
# too. These options are for speed optimization, build rate tweaks and PATROL
# options. When setting up a new machine we simply execute the "setdefaults"
# method and the raid is configured. You can use this on live raids too.
if [ $COMMAND = "setdefaults" ]
   then
      # Read Cache enabled specifies that all reads are buffered in cache memory. 
       $MegaCli -LDSetProp -Cached -LAll -a$ADAPTER -NoLog
      # Adaptive Read-Ahead if the controller receives several requests to sequential sectors
       $MegaCli -LDSetProp ADRA -LALL -a$ADAPTER -NoLog
      # Hard Disk cache policy enabled allowing the drive to use internal caching too
       $MegaCli -LDSetProp EnDskCache -LAll -a$ADAPTER -NoLog
      # Write-Back cache enabled
       $MegaCli -LDSetProp WB -LALL -a$ADAPTER -NoLog
      # Continue booting with data stuck in cache. Set Boot with Pinned Cache Enabled.
       $MegaCli -AdpSetProp -BootWithPinnedCache -1 -a$ADAPTER -NoLog
      # PATROL run every 672 hours or monthly (RAID6 77TB @60% rebuild takes 21 hours)
       $MegaCli -AdpPR -SetDelay 672 -a$ADAPTER -NoLog
      # Check Consistency every 672 hours or monthly
       $MegaCli -AdpCcSched -SetDelay 672 -a$ADAPTER -NoLog
      # Enable autobuild when a new Unconfigured(good) drive is inserted or set to hot spare
       $MegaCli -AdpAutoRbld -Enbl -a$ADAPTER -NoLog
      # RAID rebuild rate to 60% (build quick before another failure)
       $MegaCli -AdpSetProp \{RebuildRate -60\} -a$ADAPTER -NoLog
      # RAID check consistency rate to 60% (fast parity checks)
       $MegaCli -AdpSetProp \{CCRate -60\} -a$ADAPTER -NoLog
      # Enable Native Command Queue (NCQ) on all drives
       $MegaCli -AdpSetProp NCQEnbl -a$ADAPTER -NoLog
      # Sound alarm disabled (server room is too loud anyways)
       $MegaCli -AdpSetProp AlarmDsbl -a$ADAPTER -NoLog
      # Use write-back cache mode even if BBU is bad. Make sure your machine is on UPS too.
       $MegaCli -LDSetProp CachedBadBBU -LAll -a$ADAPTER -NoLog
      # Disable auto learn BBU check which can severely affect raid speeds
       OUTBBU=$(mktemp /tmp/output.XXXXXXXXXX)
       echo "autoLearnMode=1" > $OUTBBU
       $MegaCli -AdpBbuCmd -SetBbuProperties -f $OUTBBU -a0 -NoLog
       rm -rf $OUTBBU
   exit
fi

### EOF ###

