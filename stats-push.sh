#!/bin/bash

HOST=localhost
PORT=8086
BUCKET=telegraf


PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/root/bin"

TIMESTAMP=`date +%s`
HOSTNAME=`hostname -s`
OS=`uname -a | head -1 | awk '{print $1}'`


IS_TELEGRAF_ACTIVE=`systemctl is-active --quiet telegraf 2>/dev/null && echo 1 || echo 0`
LINES=


# CPU Load

if [[ "$IS_TELEGRAF_ACTIVE" -eq 0 ]]; then  # only send if telegraf is not active
    LOAD=`uptime | rev | cut -d' ' -f1-3 | rev | tr -d ','`
    LOAD_1M=`echo $LOAD | cut -d' ' -f1`
    LOAD_5M=`echo $LOAD | cut -d' ' -f2`
    LOAD_15M=`echo $LOAD | cut -d' ' -f3`
    LINES="$LINES""system,host=$HOSTNAME load1=${LOAD_1M},load5=${LOAD_5M},load15=${LOAD_15M} $TIMESTAMP"$'\n'

    if [[ "$OS" == "FreeBSD" ]]; then
        CPU_IDLE_PERCENT=`vmstat 1 2 | tail -1 | awk '{print $19}'`
    else
        CPU_IDLE_PERCENT=`vmstat 1 2 | tail -1 | awk '{print $15}'`
    fi
    if [[ "$CPU_IDLE_PERCENT" != "" ]]; then
        CPU_BUSY_PERCENT=`echo $CPU_IDLE_PERCENT | awk '{print 100-$1}'`
        LINES="$LINES""cpu,host=$HOSTNAME,cpu=cpu-total usage_idle=${CPU_IDLE_PERCENT},usage_busy=${CPU_BUSY_PERCENT} $TIMESTAMP"$'\n'
    fi
fi


# Temperature

if [[ "$IS_TELEGRAF_ACTIVE" -eq 0 ]]; then  # only send if telegraf is not active
    if [[ "$OS" == "FreeBSD" ]]; then
        CPU_TEMPERATURE=`sysctl -a 2>/dev/null | grep "dev.cpu." | grep ".temperature" | awk '{print $2}' | cut -d. -f1 | sort -rn | head -1`
    else
        while read -r CPU_TEMPERATURE_INPUT_PATH; do
            CPU_TEMPERATURE_LABEL_PATH=`echo "$CPU_TEMPERATURE_INPUT_PATH" | sed 's/_input$/_label/'`
            CPU_TEMPERATURE_LABEL=`cat "$CPU_TEMPERATURE_LABEL_PATH" 2>/dev/null`
            if [[ "$CPU_TEMPERATURE_LABEL" == "Package id 0" ]] || [[ "$CPU_TEMPERATURE_LABEL" == "Tdie" ]]; then
                CPU_TEMPERATURE=`cat "$CPU_TEMPERATURE_INPUT_PATH" 2>/dev/null | awk '{print $1/1000}'`
            fi
        done <<< $(find '/sys/devices' -name 'temp*_input' -print)
        if [[ "$CPU_TEMPERATURE" == "" ]]; then  # fallback is to capture all temperatures and select max
            CPU_TEMPERATURE=`{ cat /sys/class/thermal/thermal_zone*/temp ; find /sys/devices -name "temp*_input" -exec cat '{}' \; ; } 2>/dev/null | sort -rn | head -1 | awk '{print $1/1000}'`
        fi
    fi
    if [[ "$CPU_TEMPERATURE" != "" ]]; then
        LINES="$LINES""temp,host=$HOSTNAME,sensor=cpu temp=${CPU_TEMPERATURE} $TIMESTAMP"$'\n'
    fi
fi


# Memory

if [[ "$IS_TELEGRAF_ACTIVE" -eq 0 ]]; then  # only send if telegraf is not active
    if [[ "$OS" == "FreeBSD" ]]; then
        MEMORY_FREE=`sysctl -n vm.stats.vm.v_free_count vm.stats.vm.v_page_size 2>/dev/null | xargs | awk '{print $1*$2}'`
        MEMORY_TOTAL=`sysctl -n vm.stats.vm.v_page_count vm.stats.vm.v_page_size 2>/dev/null | xargs | awk '{print $1*$2}'`
        MEMORY_USED=$(( MEMORY_TOTAL - MEMORY_FREE ))
        LINES="$LINES""mem,host=$HOSTNAME available=${MEMORY_FREE}i,free=${MEMORY_FREE}i,used=${MEMORY_USED}i,total=${MEMORY_TOTAL}i $TIMESTAMP"$'\n'
    else
        MEMORY_AVAILABLE=`free -b 2>/dev/null | grep Mem | awk '{print $7}'`
        MEMORY_FREE=`free -b 2>/dev/null | egrep '^Mem:' | awk '{print $4}'`
        MEMORY_USED=`free -b 2>/dev/null | egrep '^Mem:' | awk '{print $3}'`
        MEMORY_TOTAL=`free -b 2>/dev/null | egrep '^Mem:' | awk '{print $2}'`
        SWAP_FREE=`free -b 2>/dev/null | egrep '^Swap:' | awk '{print $4}'`
        SWAP_USED=`free -b 2>/dev/null | egrep '^Swap:' | awk '{print $3}'`
        SWAP_TOTAL=`free -b 2>/dev/null | egrep '^Swap:' | awk '{print $2}'`
        LINES="$LINES""mem,host=$HOSTNAME available=${MEMORY_AVAILABLE}i,free=${MEMORY_FREE}i,used=${MEMORY_USED}i,total=${MEMORY_TOTAL}i,swap_free=${SWAP_FREE}i,swap_used=${SWAP_USED}i,swap_total=${SWAP_TOTAL}i $TIMESTAMP"$'\n'
        LINES="$LINES""swap,host=$HOSTNAME free=${SWAP_FREE}i,used=${SWAP_USED}i,total=${SWAP_TOTAL}i $TIMESTAMP"$'\n'
    fi
fi


# Disk


if [[ "$IS_TELEGRAF_ACTIVE" -eq 0 ]]; then  # only send if telegraf is not active
    while read -r LINE; do
        DISK_DEVICE=$(basename `echo "$LINE" | awk '{print $1}'`)
        DISK_FSTYPE=`echo "$LINE" | awk '{print $2}'`
        DISK_FREE=`echo "$LINE" | awk '{printf "%.0f", $5 * 1024}'`
        DISK_USED=`echo "$LINE" | awk '{printf "%.0f", $4 * 1024}'`
        DISK_TOTAL=`echo "$LINE" | awk '{printf "%.0f", $3 * 1024}'`
        DISK_PATH=`echo "$LINE" | awk '{print $7}'`
        LINES="$LINES""disk,host=$HOSTNAME,path=$DISK_PATH,device=$DISK_DEVICE,fstype=$DISK_FSTYPE free=${DISK_FREE}i,used=${DISK_USED}i,total=${DISK_TOTAL}i $TIMESTAMP"$'\n'
    done <<< $(df -PTk | egrep -v "\s(tmpfs|devtmpfs|devfs|iso9660|overlay|aufs|squashfs)\s" | tail -n+2)
fi


# ZFS

if [[ "$IS_TELEGRAF_ACTIVE" -eq 0 ]]; then  # only send if telegraf is not active
    while read -r LINE; do
        POOL_NAME=`echo $LINE | cut -d' ' -f1`
        POOL_FREE=`echo $LINE | cut -d' ' -f2`
        POOL_ALLOCATED=`echo $LINE | cut -d' ' -f3`
        POOL_SIZE=`echo $LINE | cut -d' ' -f4`
        LINES="$LINES""zfs,host=$HOSTNAME,pools=$POOL_NAME free=${POOL_FREE}i,used=${POOL_ALLOCATED}i,total=${POOL_SIZE}i $TIMESTAMP"$'\n'
    done <<< $(zpool list -pH -o name,free,allocated,size)
fi

if [[ "$OS" != "FreeBSD" ]] || [[ "$IS_TELEGRAF_ACTIVE" -eq 0 ]]; then  # only send if telegraf is not active / and always on Linux
    while read -r LINE; do
        DATASET_NAME=`echo $LINE | cut -d' ' -f1`
        DATASET_AVAILABLE=`echo $LINE | cut -d' ' -f2`
        DATASET_USED=`echo $LINE | cut -d' ' -f3`
        DATASET_USED_SNAPSHOT=`echo $LINE | cut -d' ' -f4`
        DATASET_USED_DATASET=`echo $LINE | cut -d' ' -f5`
        LINES="$LINES""zfs_dataset,host=$HOSTNAME,dataset=$DATASET_NAME avail=${DATASET_AVAILABLE}i,used=${DATASET_USED}i,usedsnap=${DATASET_USED_SNAPSHOT}i,usedds=${DATASET_USED_DATASET}i $TIMESTAMP"$'\n'
    done <<< $(zfs list -pH -o name,available,used,usedbysnapshots,usedbydataset)
fi


# Send

if [[ "$LINES" != "" ]]; then
    echo "$LINES"
    CONTENT_LEN=$(echo -en ${LINES} | wc -c)
    echo -ne "POST /api/v2/write?bucket=${BUCKET}&precision=s HTTP/1.0\r\nHost: $HOST\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: ${CONTENT_LEN}\r\n\r\n${LINES}" | nc -w 15 $HOST $PORT
fi
