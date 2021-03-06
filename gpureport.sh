#!/bin/bash
# The MIT License

# Copyright (c) 2022 Ziwei Xu <ziweixu.zwx@gmail.com>

# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

### config file
# shellcheck source=gpureport_config.sh
config_file=${1:-gpureport_config.sh}
source "$config_file"

### constants and helpers
calc() { echo - | awk "{print $1}"; }

elementIn () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }

qworker() {
    server=$1
    info=$(timeout $SSH_TIMEOUT \
    ssh -q -o StrictHostKeyChecking=no -o PasswordAuthentication=no $server \
    "echo -n \$(gpustat --json 2>/dev/null) ; echo -n \| ;\
    uptime | sed -r 's/.+([0-9]+\.[0-9]+),? ([0-9]+\.[0-9]+),? ([0-9]+\.[0-9]+)/\2/'" 2>/dev/null)
    outcome=$?
    if [ $outcome -ne $TIME_OUT_CODE ]; then
        IFS=\| read -r gpu_info load_avg <<< "$info"
        if [ -z "$gpu_info" ]; then outcome=$SERVER_SIDE_ERROR_CODE; fi
        if [ -z "$load_avg" ]; then outcome=$SSH_AUTH_ERROR_CODE; fi
    fi

    if [ "$outcome" -eq "0" ] ; then
        echo "$gpu_info" > $TEMP_DIR/$server.gpu_info
        echo "$load_avg" > $TEMP_DIR/$server.load_avg
    elif [ "$outcome" -eq $TIME_OUT_CODE ] ; then
        echo $outcome > $TEMP_DIR/$server.timeout
    elif [ "$outcome" -eq $SSH_AUTH_ERROR_CODE ] ; then
        echo $outcome > $TEMP_DIR/$server.sshreject
    else
        echo $outcome > $TEMP_DIR/$server.servererror
    fi

    if test -f $TEMP_DIR/$server.gpu_info; then
        gpu_info=$(cat $TEMP_DIR/$server.gpu_info)
        load_avg=$(cat $TEMP_DIR/$server.load_avg)
        
        # truncate long / pad shorter host names into 8 characters
        this_server=${server}
        (( ${#this_server} > 8 )) && this_server="${this_server:0:3}..${this_server:(-3)}"
        this_server=$(printf "%-8b" "${this_server}")
        
        gpu_num=$(echo "$gpu_info" | jq ".gpus | length")
        # retrieve statistics of each gpu
        for gpu in $(seq 0 $((gpu_num-1))) ; do
            
            _tmp=$(echo "$gpu_info" | jq ".gpus[$gpu] | .\"memory.total\", .\"memory.used\", .\"enforced.power.limit\", .\"power.draw\", .\"utilization.gpu\", .\"processes\" | length")
            IFS=$'\n' read -rd '' gpu_mem_total gpu_mem_used gpu_power_limit gpu_power_draw gpu_util proc_num <<< "$_tmp"
            gpu_mem_remain=$((gpu_mem_total-gpu_mem_used))
            proc_usr=""

            if [[ $proc_num -gt 0 ]] ; then
                users=()
                for proc in $(seq 0 $(($proc_num-1))); do
                    _tmp=$( echo $gpu_info | jq ".gpus[$gpu][\"processes\"][$proc] | .\"username\", .\"pid\"" )
                    IFS=$'\n' read -rd '' this_usr this_pid <<< "$_tmp"

                    if elementIn "${this_usr}" "${users[@]}" ; then continue; fi
                    users+=("$this_usr")
                    if [[ $this_usr = *"$USER_NAME"* ]] ; then this_usr="\\e[32m$this_usr\\e[0m"; fi
                    
                    proc_usr="$proc_usr""${this_usr}(${this_pid}) "
                done
            fi

            this_server_show_name="$this_server"
            if [[ $gpu_mem_remain -gt $RAMAIN_MEMORY_LIMIT ]]; then
                gpu="\\e[1;36m$gpu\\e[0m"
                this_server_show_name="\\e[1;36m$this_server_show_name\\e[0m"
            fi

            printf "%b %b\t %5s/%-5s \t\t %-3s\t %4s/%-4s \t %s\t %b\n" \
            "$this_server_show_name" "$gpu" "$gpu_mem_remain" "$gpu_mem_total" \
            "$gpu_util" "$gpu_power_draw" "$gpu_power_limit" "$load_avg" "$proc_usr" >> $TEMP_DIR/$server.line
        
        done
    fi
}

# Start

mkdir -p $TEMP_DIR

RAMAIN_MEMORY_LIMIT=$((THRES*1024))
ssh_timeout_servers=()
ssh_failed_servers=()
target_failed_servers=()

echo -ne "Now processing: \n"
job_counter=0
for server in "${SERVER_LIST[@]}" ; do
    qworker $server &
    echo -ne "$server "
    job_counter=$((job_counter+1))
    if [ $job_counter -ge $QUERY_BATCH_SIZE ] ; then 
        wait
        job_counter=0
    fi
done
wait

echo 
echo 

printf -- "------   ---\t ----------------\t ----\t ------------\t ----\t ----\n"
printf    "SERVER   GPU\t REMAIN_M/TOTAL_M\t UTIL\t POWER/MAXPWR\t LOAD\t USER\n"
printf -- "------   ---\t ----------------\t ----\t ------------\t ----\t ----\n"

for server in "${SERVER_LIST[@]}" ; do
    # if connected and GPU info is successfully retrieved
    if test -f $TEMP_DIR/$server.line ; then
        cat $TEMP_DIR/$server.line
    # else, check the return status
    elif test -f $TEMP_DIR/$server.timeout ; then 
        ssh_timeout_servers+=("\\e[1;35m$server\\e[0m ")
    elif test -f $TEMP_DIR/$server.sshreject ; then
        ssh_failed_servers+=("\\e[1;35m$server\\e[0m ")
    elif test -f $TEMP_DIR/$server.servererror; then
        target_failed_servers+=("\\e[1;35m$server\\e[0m ")
    else
        echo "Info file $TEMP_DIR/$server* not found. "
    fi
done

rm -r $TEMP_DIR

echo
printf "%b\n%b\n" "\\e[1;35mFailed Servers\\e[0m" "\\e[1;35m--------------\\e[0m"
printf "%s " "SSH timeout: "
for fs in "${ssh_timeout_servers[@]}" ; do
    printf "%b" "$fs"
done
echo
printf "%s " "SSH rejected: "
for fs in "${ssh_failed_servers[@]}" ; do
    printf "%b" "$fs"
done
echo 
printf "%s " "Server-side error: "
for fs in "${target_failed_servers[@]}" ; do
    printf "%b" "$fs"
done

echo 

echo
date
# echo "$(curl -s --head http://google.com | grep ^Date: | sed 's/Date: //g')"
