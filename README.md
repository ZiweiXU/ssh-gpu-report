# ssh-gpu-report - Generating server utilization report with minimal configuration

**ssh-gpu-report** is a script that generates utility reports of remote host(s).
The purpose of this script is to enable an easy grasp of remote server statistics when you have access to a large pool of GPU computation nodes, with minimal extra configuration efforts on the remote side.

It has two implementations: [Python (recommended)](#use-the-python-version) and [Bash](#use-the-bash-version).

## What's good about it

1. Minimal configuration efforts: no extra daemon/service is needed on the remote host
2. Useful information: remaining memory, utility (%), power, cpu load, and user list
3. Fast query: queries are spawned as batches of parallel jobs (useful for a large pool)
4. Filter and highlight GPU by remaining memory
5. Feedback for failed cases

## What's in the report

The report consists of a table showing the statistics of GPUs on target hosts and a failure summary.
The table should be readable enough.
The failure summary contains servers that fall into the following categories:

- SSH timeout: the query command failed to complete within the configured time. There could be a network congestion or the target host was very busy.
- SSH rejected: the target host denied the connection. Check if key authentication is ready, or if the admin has reserved the target host for other uses.
- Server-side errors: the connection was successful, however, gpustat failed to query the GPU information. Further diagnosis is required on the target host.

Here is an example report (from Bash version):
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

## Use the Python Version

The executable `gpureport.py` can be configured by `gpureport_config.py`.
Environment variables can also be used to override configurations.

Besides all the features in the bash version, it has the following improvements:

- More control over output format, via `GPUR_COLUMNS`, `GPUR_TABLE_HEADER`, and `GPUR_TABLE_FORMAT`.
- Extra information: `cpu_count`, `mem_avail`, and `mem_total`.
- All the entries in the config can be overridden by environment variables.

### Prerequisites 

Local side:
- `python >= 3.3`, and two packages `tabulate` and `yaspin`.
The prerequisites can be installed by `pip install --user tabulate yaspin`.

Remote side:
- SSH access via key authentication to all target hosts (the hosts in `SERVER_LIST` in the configuration file), check [this](https://kb.iu.edu/d/aews) for instructions.
- Remote side: [gpustat](https://github.com/wookayin/gpustat) installed on all remote hosts. Note that `gpustat` must be runnable in non-interactive sessions. Test this with `ssh HOSTNAME "gpustat"`. If GPU information is properly displayed then it's good to go. Otherwise, you will need some [extra steps on the remote](https://superuser.com/questions/1468098/command-is-not-found-using-ssh-roothost-command).

### Usage

Before using, please edit `gpureport_config.py` according to your needs and put it in the same directory as `gpureport.py`.
The file is self-documented.

- Print the report to your terminal:
```shell
python gpureport.py
```

- Override defaults using environment variables:

For example, if you want to check host names, system load, and available memory, for a group of hosts different from defaults, and you want the result to be headerless and without highlight: 
```shell
GPUR_SERVER_LIST=host1,host2,tsoh1,tosh2 GPUR_COLUMNS=host,cpu_load,mem_avail GPUR_TABLE_HEADER=0 GPUR_TABLE_FORMAT=0 python gpureport.py
```


## Use the Bash Version

### Prerequisites 

Local side:
- `bash`, and a terminal simulator with xterm-256color support (usually shipped with your linux/unix).
- `perl` version 5 or higher installed on the host running `gpureport.sh` (usually shipped with your Linux/unix, check with `perl --version`).
- GNU `xargs>=4.7.0` (usually shipped with your linux/unix)
- [jq](https://github.com/stedolan/jq) installed on the host running `gpureport.sh` (download a [release](https://github.com/stedolan/jq/releases/latest) and make sure `jq` is in `$PATH`, or install with [anaconda](https://anaconda.org/conda-forge/jq)).

Remote side:
- SSH access via key authentication to all target hosts (the hosts in `SERVER_LIST` in the configuration file), check [this](https://kb.iu.edu/d/aews) for instructions.
- [gpustat](https://github.com/wookayin/gpustat) installed on all target hosts. Note that `gpustat` must be runnable in non-interactive sessions. Test this with `ssh HOSTNAME "gpustat"`. If GPU information is properly displayed then it's good to go. Otherwise you will need some [extra steps on the remote](https://superuser.com/questions/1468098/command-is-not-found-using-ssh-roothost-command).


### Configuration

The configuration template [gpureport_config.sh](gpureport_config.sh) provides all the required documentations and reasonable defaults.
Some defaults can be overriden by environment variables.

### Usage

- Print the report to your terminal:
```shell
bash gpureport.sh [config_file]
```
If no `config_file` is specified, `gpureport.sh` will look for `gpureport_config.sh` in the current working directory.

- Redirect the report to a file and `cat` it later on (`INTERACTIVE` is overriden to remove redundant messages):
```shell
INTERACTIVE=0 bash gpureport.sh [config_file] > report.txt ; cat report.txt
```

- Combine it with `watch` to get the latest updates without waiting:
```shell
# Run this in a tmux session
while true ; do IFS= ; report=$(INTERACTIVE=0 bash gpureport.sh) ; echo $report > report.txt ; sleep 60 ; done
# Detach from the session
```
and access the report at any time using `cat report.txt`.