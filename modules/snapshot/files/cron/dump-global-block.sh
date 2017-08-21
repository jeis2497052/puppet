#!/bin/bash
#############################################################
# This file is maintained by puppet!
# modules/snapshot/cron/dump-global-block.sh
#############################################################

source /usr/local/etc/set_dump_dirs.sh

checkval() {
    setting=$1
    value=$2
    if [ -z "$value" -o "$value" == "null" ]; then
        echo "failed to retrieve value of $setting from $configfile" >& 2
        exit 1
    fi
}

getsetting() {
    results=$1
    section=$2
    setting=$3
    echo "$results" | /usr/bin/jq -M -r ".$section.$setting"
}

get_db_host() {
    apachedir=$1

    wmfconfigdir="${apachedir}/wmf-config"
    multiversionscript="${apachedir}/multiversion/MWScript.php"
    if [ -e "$multiversionscript" ]; then
        host=`php -q "$multiversionscript" extensions/CentralAuth/maintenance/getCentralAuthDBInfo.php --wiki="aawiki"` || (echo $host >& 2; host="")
    fi
    if [ -z "$host" ]; then
        echo "can't locate db server for centralauth, exiting." >& 2
        exit 1
    fi
    echo $host
}

get_db_user() {
    db_user=`echo 'echo $wgDBadminuser;' | php "$multiversionscript" eval.php $wiki`

    if [ -z "$db_user" ]; then
        echo "can't get db user name, exiting." >& 2
        exit 1
    fi
}

get_db_pass() {
    db_pass=`echo 'echo $wgDBadminpassword;' | php "$multiversionscript" eval.php $wiki`

    if [ -z "$db_pass" ]; then
        echo "can't get db password, exiting." >& 2
        exit 1
    fi
}

dump_tables() {
    tables=$1
    outputdir=$2
    mysqldump=$3
    gzip=$4
    db_user=$5
    db_pass=$6

    today=`date +%Y%m%d`
    dir="$outputdir/$today"
    mkdir -p "$dir"
    for t in $tables; do
        outputfile="${dir}/${today}-${t}.gz"
        if [ "$dryrun" == "true" ]; then
            echo "would run:"
            echo -n "$mysqldump" -u "$db_user" -p"$db_pass" -h "$host" --opt --quick --skip-add-locks --skip-lock-tables centralauth "$t"
            echo  "| $gzip > $outputfile"
        else
            # echo "dumping $t into $outputfile"
            "$mysqldump" -u "$db_user" -p"$db_pass" -h "$host" --opt --quick --skip-add-locks --skip-lock-tables centralauth "$t" | "$gzip" > "$outputfile"
        fi
    done
}

usage() {
    echo "Usage: $0 [--config <pathtofile>] [--dryrun]" >& 2
    echo >& 2
    echo "  --config   path to configuration file for dump generation" >& 2
    echo "             (default value: ${confsdir}/wikidump.conf" >& 2
    echo "  --dryrun   don't run dump, show what would have been done" >& 2
    exit 1
}

configfile="${confsdir}/wikidump.conf"
dryrun="false"

while [ $# -gt 0 ]; do
    if [ $1 == "--config" ]; then
        configfile="$2"
        shift; shift
    elif [ $1 == "--dryrun" ]; then
        dryrun="true"
        shift
    else
        echo "$0: Unknown option $1" >& 2
        usage
    fi
done

args="wiki:dir;tools:gzip,mysqldump"
results=`python "${repodir}/getconfigvals.py" --configfile "$configfile" --args "$args"`

apachedir=`getsetting "$results" "wiki" "dir"` || exit 1
gzip=`getsetting "$results" "tools" "gzip"` || exit 1
mysqldump=`getsetting "$results" "tools" "mysqldump"` || exit 1

for settingname in "apachedir" "gzip" "mysqldump"; do
    checkval "$settingname" "${!settingname}"
done

outputdir="${datadir}/public/other/globalblock"

host=`get_db_host "$apachedir"` || exit 1
db_user=`get_db_user` || exit 1
db_pass=`get_db_pass` || exit 1

dump_tables "globalblock" "$outputdir" "$mysqldump" "$gzip" "$db_user" "$db_pass"
