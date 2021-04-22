# ssh-gpu-report - Generating GPU utilization report with minimal effort

**ssh-gpu-report** is a bash script that generates utility report for GPUs on remote host(s).
It is built upon [gpustat](https://github.com/wookayin/gpustat) and [jq](https://github.com/stedolan/jq).
The purpose of this utility is to enable a easy grasp of GPU statistics when you have access to a large pool of GPU computation nodes, with minimal extra configuration efforts on the remote side.

## What's good about it

1. Minimal configuration (especially if you've got an NFS in your computation cluster)
2. Filter and highlight GPU by remaining memory
3. Feedbacks for failed cases

## Prerequisites

1. SSH access via key authentication to all target hosts (the hosts in `SERVER_LIST` in the configuration file).
2. A terminal simulator with xterm-256color support.
3. `gpustat` installed on all target hosts.
4. `jq` installed on the host running `gpureport.sh`.

## Usage

To prints the report to your terminal:
```shell
bash gpureport.sh [config_file]
```

You can also redirect the report to a file and `cat` it later on:
```shell
bash gpureport.sh [config_file] > report.txt ; cat report.txt
```

You can also combine it with `watch` to get the latest updates:
```shell
# Run this in a tmux session
while true ; do IFS= ; report=$(bash gpureport.sh) ; echo $report > report.txt ; sleep 60 ; done
# Detach from the session
```
and access the report at anytime using `cat report.txt`.

## Configuration

The configuration template [gpureport_config.sh](gpureport_config.sh) provides all the required documentations and reasonable defaults.

## How to read the report

The report consists of a table showing the statistics of GPUs on target hosts and a failure summary.
The table should be readable enough.
The failure summary contains servers that fall into the following categories:

- SSH timeout: the query command failed to complete within the configured time. There could be a network congestion or the target host was very busy.
- SSH rejected: the target host denied the connection. Check if key authentication is ready, or if the admin has reserved the target host for other uses.
- Server-side errors: the connection was successful, however, gpustat failed to query the GPU information. Further diagnosis is required on the target host.

Here is an example report (highlights are not shown):
```
SERVER   GPU   REMAIN_M/TOTAL_M  UTIL  POWER/MAXPWR  LOAD    USER
------   ---   ----------------  ----  ------------  ----    ----
host1    0     11019/11019       0        4/250      1.25
host1    1     11019/11019       0       17/250      1.25
host1    2     11019/11019       0       19/250      1.25
host1    3     11019/11019       0        0/250      1.25
host2    0     1165/11019        0       64/250      27.84   "user1"(7431) "user2"(4139)
host2    1     7249/11019        6       60/250      27.84   "user3"(40938) "user2"(22615)
host2    2     7332/11019        0       21/250      27.84   "user3"(40938)

Failed Servers
--------------
SSH timeout:
SSH rejected:
Server-side error:  host3

Wed Feb 32 24:61:61 +13 1900
```

## Disclaimer
