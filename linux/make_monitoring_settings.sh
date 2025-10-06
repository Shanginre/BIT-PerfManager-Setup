#!/bin/bash

adddate() {
    while IFS= read -r line; do
        printf '%s,%s\n' "$(date +'%m/%d/%Y %T')" "$line";
    done
}

while IFS= read -r pid; do
        kill -9 $pid;
done < <( pgrep 'vmstat|iostat|ifstat|pidstat' -u root )

sleep 1

root_directory="/var/log/bit_monitoring"
if [ ! -d "$root_directory" ]; then
        mkdir -p "$root_directory";
        chmod 777 "$root_directory";
fi

current_date=$(date +"%y%m%d%H%M%S")

# vmstat
stdbuf -o0 vmstat -n 30 |
stdbuf -o0 grep -Ev "procs" | stdbuf -o0 tr -s ' '| stdbuf -o0 sed -r -e 's/^ //g' -e 's/,/\./g' -e 's/ /,/g' |
adddate > "${root_directory}/vmstat_${current_date}.csv" &

# iostat
# add single string with headers in the new file iostat
iostat -xyzd | grep -Eh 'Device' | stdbuf -o0 tr -s ' '| stdbuf -o0 sed -r -e 's/^ //g' -e 's/ /,/g' |
adddate > "${root_directory}/iostat_${current_date}.csv"

stdbuf -o0 iostat -xyzd 30 |
stdbuf -o0 grep -Ev "Linux|Device|^$|:" | stdbuf -o0 tr -s ' '| stdbuf -o0 sed -r -e 's/^ //g' -e 's/,/\./g' -e 's/ /,/g' |
adddate >> "${root_directory}/iostat_${current_date}.csv" &

# ifstat
stdbuf -o0 ifstat -nl 30 |
stdbuf -o0 tr -s ' '| stdbuf -o0 sed -r -e 's/\/s /\/s_/g' -e 's/^ //g' -e 's/,/\./g' -e 's/ /,/g' -e 's/\/s_/\/s /g' |
adddate > "${root_directory}/ifstat_${current_date}.csv" &

# pidstat
# add single string with headers in the new file pidstat
pidstat -G "empty_process_name" -rudl -h | grep -E 'Time' | sed -r 's/# Time/Time/' |
stdbuf -o0 tr -s ' '| stdbuf -o0 sed -r -e 's/^ //g' -e 's/,/\./g' -e 's/ /,/g' |
adddate > "${root_directory}/pidstat_${current_date}.csv"

stdbuf -o0 pidstat -G "postgres|ragent|rmngr|rphost" -rudl -h 30 | stdbuf -o0 grep -E "postgres|ragent|rmngr|rphost" |  stdbuf -o0 grep -Ev 'grep|pidstat' |
stdbuf -o0 grep -Ev "Time" |
stdbuf -o0 tr -s ' '| stdbuf -o0 sed -r -e 's/^ //g' -e 's/,/\./g' | sed ':x; s/\([0-9]\) \+\([0-9a-z\/-]\)/\1,\2/g; tx' |
adddate >> "${root_directory}/pidstat_${current_date}.csv" &
