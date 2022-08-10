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
elementIn () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }

function cyan() {
  if [[ -z $2 ]]; then
    printf "\e[1;36m%s\e[0m" "$1"
  else
    printf "\\e[1;36m%s\\e[0m" "$1"
  fi
}

function magenta() {
  if [[ -n $2 ]]; then
    printf "\e[1;35m%s\e[0m" "$1"
  else
    printf "\\e[1;35m%s\\e[0m" "$1"
  fi
}

function green() {
  if [[ -n $2 ]]; then
    printf "\e[1;32m%s\e[0m" "$1"
  else
    printf "\\e[1;32m%s\\e[0m" "$1"
  fi
}

# https://unix.stackexchange.com/questions/225179/display-spinner-while-waiting-for-some-process-to-finish
function shutdown() {
  tput cnorm # reset cursor
}
trap shutdown EXIT

function cursorBack() {
  echo -en "\033[$1D"
}

function spinner() {
  # make sure we use non-unicode character type locale 
  # (that way it works for any locale as long as the font supports the characters)
  local LC_CTYPE=C

  local pid=$1 # Process Id of the previous running command

  case $(($RANDOM % 6)) in
  0)
    local spin='⠁⠂⠄⡀⢀⠠⠐⠈'
    local charwidth=3
    ;;
  1)
    local spin='-\|/'
    local charwidth=1
    ;;
  2)
    local spin='←↖↑↗→↘↓↙'
    local charwidth=3
    ;;
  3)
    local spin='▖▘▝▗'
    local charwidth=3
    ;;
  4)
    local spin='◐◓◑◒'
    local charwidth=3
    ;;
  5)
    local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
    local charwidth=3
    ;;
  esac

  local i=0
  tput civis # cursor invisible
  while kill -0 $pid 2>/dev/null; do
    local i=$(((i + $charwidth) % ${#spin}))
    printf "%s" "${spin:$i:$charwidth}"

    cursorBack 1
    sleep .2
  done
  tput cnorm
  wait $pid # capture exit code
  return $?
}

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
}

qparser () {
  server=$1
  if test -f $TEMP_DIR/$server.gpu_info; then
    printf '' > $TEMP_DIR/$server.line
    gpu_info=$(cat $TEMP_DIR/$server.gpu_info)
    load_avg=$(cat $TEMP_DIR/$server.load_avg)

    # truncate long / pad shorter host names into 8 characters
    this_server=${server}
    (( ${#this_server} > 8 )) && this_server="${this_server:0:3}..${this_server:(-3)}"
    this_server_show_name="$(printf '%-8s' $this_server)"
    
    gpu_num=$(echo "$gpu_info" | jq ".gpus | length")
    # retrieve statistics of each gpu
    for gpu in $(seq 0 $((gpu_num-1))) ; do
        _tmp=$(echo "$gpu_info" | jq ".gpus[$gpu] | .\"memory.total\", .\"memory.used\", .\"enforced.power.limit\", .\"power.draw\", .\"utilization.gpu\", .\"temperature.gpu\", .\"processes\" | length")
        IFS=$'\n' read -rd '' gpu_mem_total gpu_mem_used gpu_power_limit gpu_power_draw gpu_util gpu_temp proc_num <<< "$_tmp"
        gpu_mem_remain=$((gpu_mem_total-gpu_mem_used))
        proc_usr=""

        if [[ $proc_num -gt 0 ]] ; then
            # users=()
            for proc in $(seq 0 $(($proc_num-1))); do
                _tmp=$( echo $gpu_info | jq ".gpus[$gpu][\"processes\"][$proc] | .\"username\", .\"pid\"" )
                IFS=$'\n' read -rd '' this_usr this_pid <<< "$_tmp"

                if [[ $this_usr = *"$USER_NAME"* ]] ; then this_usr="$(green $this_usr escape)"; fi
                
                proc_usr="$proc_usr""${this_usr}(${this_pid}) "
            done
        fi

        if [[ $gpu_mem_remain -gt $GPU_MEM_THRES ]]; then
            gpu="$(cyan "$gpu" escape)"
            this_server_show_name="$(cyan "$this_server_show_name" escape)"
        fi

        printf "%b %b\t %5s/%-5s \t\t %-3s\t %-3s\t %4s/%-4s \t %s\t %b\n" \
        "$this_server_show_name" "$gpu" "$gpu_mem_remain" "$gpu_mem_total" \
        "$gpu_util" "$gpu_temp" "$gpu_power_draw" "$gpu_power_limit" "$load_avg" "$proc_usr" >> $TEMP_DIR/$server.line

    done
  fi
}

# Start
mkdir -p $TEMP_DIR

export -f qworker qparser timeout cyan green magenta
[[ INTERACTIVE -eq 1 ]] && echo -ne 'Working... '
printf %s\\n "${SERVER_LIST[@]}" | xargs -P${QUERY_BATCH_SIZE} -I{} bash -c "source ${config_file}; qworker {}" &
if [[ INTERACTIVE -eq 1 ]]; then spinner $! ; else wait; fi
[[ INTERACTIVE -eq 1 ]] && echo 'done!'
[[ INTERACTIVE -eq 1 ]] && echo -ne 'Parsing... '
printf %s\\n "${SERVER_LIST[@]}" | xargs -P${QUERY_BATCH_SIZE} -I{} bash -c "source ${config_file}; qparser {}" &
if [[ INTERACTIVE -eq 1 ]]; then spinner $! ; else wait; fi
[[ INTERACTIVE -eq 1 ]] && echo 'done!'

ssh_timeout_servers=()
ssh_failed_servers=()
target_failed_servers=()

echo 
echo 
printf -- "------   ---\t ----------------\t ----\t ----\t ------------\t ----\t ---------\n"
printf    "SERVER   GPU\t REMAIN_M/TOTAL_M\t UTIL\t TEMP\t POWER/MAXPWR\t LOAD\t USER(PID)\n"
printf -- "------   ---\t ----------------\t ----\t ----\t ------------\t ----\t ---------\n"
echo
for server in "${SERVER_LIST[@]}" ; do
    # if connected and GPU info is successfully retrieved
    if test -f $TEMP_DIR/$server.line ; then
        cat $TEMP_DIR/$server.line
    # else, check the return status
    elif test -f $TEMP_DIR/$server.timeout ; then 
        # ssh_timeout_servers+=("\\e[1;35m$server\\e[0m ")
        ssh_timeout_servers+=( "$(magenta $server)"" " )
    elif test -f $TEMP_DIR/$server.sshreject ; then
        ssh_failed_servers+=( "$(magenta $server)"" " )
    elif test -f $TEMP_DIR/$server.servererror; then
        target_failed_servers+=( "$(magenta $server)"" " )
    else
        echo "Info file $TEMP_DIR/$server* not found. "
    fi
done

printf "%b\n%b\n" "$(magenta 'Failed Servers')" "$(magenta '--------------')"
printf "%s " "Timed out: "
for fs in "${ssh_timeout_servers[@]}" ; do
    printf "%b" "$fs"
done
echo
printf "%s " "Rejected: "
for fs in "${ssh_failed_servers[@]}" ; do
    printf "%b" "$fs"
done
echo 
printf "%s " "Server-side error: "
for fs in "${target_failed_servers[@]}" ; do
    printf "%b" "$fs"
done

echo
date

rm -r $TEMP_DIR
