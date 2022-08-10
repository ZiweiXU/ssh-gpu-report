#!env python

import os
import copy
import json
import subprocess
from multiprocessing import Pool
from functools import partial
from typing import List

try:
    import tabulate, yaspin
except:
    print("Please install tabulate and yaspin using ``pip install --user tabulate yaspin''")

from gpureport_config import get_config

class bcolors:
    HEADER = '\033[95m'
    BLUE = '\033[34m'
    CYAN = '\u001b[36m'
    GREEN = '\033[32m'
    WARNING = '\033[33m'
    MAGENTA = '\033[35m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def query_worker(host, config):

    proc = subprocess.Popen([
                config['GPUR_SSH_BIN'], '-q', 
                '-o', 'StrictHostKeyChecking=no', 
                '-o', 'PasswordAuthentication=no',
                f'{host}',
                r"echo $(gpustat --json 2>/dev/null);"
                r"uptime | sed -r 's/.+([0-9]+\.[0-9]+),? ([0-9]+\.[0-9]+),? ([0-9]+\.[0-9]+)/\2/';"
                r"getconf _NPROCESSORS_ONLN;",
                r"free | grep Mem | awk '{print $2}{print $3}'",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True)
    
    try:
        outcome = proc.communicate(timeout=int(config['GPUR_SSH_TIMEOUT']))[0]
        result = {'host': host, 'successful': True, 'comment': '', 'payload': outcome}
    except subprocess.TimeoutExpired:
        proc.terminate()
        return {'host': host, 'successful': False, 'comment': 'Timeout', 'payload': None}

    return_code = proc.returncode
    if return_code != 0:
        if return_code == int(config['GPUR_CODE_SERVER_SIDE_ERROR']):
            result.update({'successful': False, 'comment': 'Server Side Err'})
        elif return_code == int(config['GPUR_CODE_AUTH_ERROR']):
            result.update({'successful': False, 'comment': 'SSH Rej'})
        else:
            result.update({'successful': False, 'comment': f'Unknown Err {return_code}'})

    return result

def host_info_parser(host_result) -> List[List]:
    host = host_result['host']
    gpu_info, cpu_load, cpu_count, mem_total, mem_used = host_result['payload'].split('\n')[:-1]
    
    host_rows = []
    
    host_info = copy.deepcopy(host_result)
    host_info['host'] = host
    host_info['cpu_load'] = cpu_load
    host_info['cpu_count'] = cpu_count
    host_info['mem_total'] = int(int(mem_total)/1024/1024)
    host_info['mem_avail'] = int((int(mem_total) - int(mem_used))/1024/1024)

    try:
        gpu_info = json.loads(gpu_info)
    except json.decoder.JSONDecodeError:
        row_info = copy.deepcopy(host_info)
        row_info['comment'] = host_result['comment'] + 'GPU Err'
        host_rows.append(row_info)
        return host_rows
    
    gpu_num = len(gpu_info['gpus'])
    for gpu in range(gpu_num):
        this_gpu = gpu_info['gpus'][gpu]
        row_info = {}
        row_info['host'] = host
        row_info['gpu'] = gpu
        
        row_info['gpu_mem_used'] = this_gpu['memory.used']
        row_info['gpu_mem_total'] = this_gpu['memory.total']
        row_info['gpu_mem_avail'] = row_info['gpu_mem_total'] - row_info['gpu_mem_used']

        row_info['gpu_power_max'] = this_gpu['enforced.power.limit']
        row_info['gpu_power'] = this_gpu['power.draw']
        row_info['gpu_util'] = this_gpu['utilization.gpu']
        row_info['gpu_temp'] = this_gpu['temperature.gpu']
        
        process_num = len(this_gpu['processes'])
        proc_usr = []
        for proc in range(process_num):
            this_user = this_gpu['processes'][proc]['username']
            this_pid = this_gpu['processes'][proc]['pid']
            proc_usr.append((this_user, this_pid))

        row_info['users'] = proc_usr

        row_info.update(host_info)
        host_rows.append(row_info)
    
    return host_rows


def column_filter(host_row, columns, formatter=lambda x, y, z: x):
    """From host_row, filter out requested columns.
    Optionally, apply format to the columns.
    """
    this_row = []
    for col in columns:
        if col in host_row:
            this_row.append(formatter(host_row[col], col, host_row))
        else:
            this_row.append('-')
    return this_row


def context_formatter(original, col, row_context, config):
    """Format each column based on its content or the row context.
    
    Args:
    - original: the original value
    - col: the name of the column
    - row_context: a dictionary of a row
    - config: a dictionary of configuration

    Returns:
    - the formatted value
    """
    def compose(*funcs):
        def funcs_composed(x):
            for func in funcs:
                x = func(x)
            return x
        return funcs_composed

    def format_failure(original, row_context=row_context, config=config):
        if not row_context['successful']:
            return f'{bcolors.MAGENTA}{bcolors.BOLD}{original}{bcolors.ENDC}'
        return original

    def format_gpu(original, row_context=row_context, config=config):
        try:
            if float(row_context['gpu_mem_avail']) > float(config['GPUR_MEM_THRES']):
                return f'{bcolors.CYAN}{bcolors.BOLD}{original}{bcolors.ENDC}'
        except KeyError:
            pass
        return original
    
    def format_user(original, row_context=row_context, config=config):
        proc_usr = {}
        for user_list in original:
            this_user, this_pid = user_list
            for user_mask in config['GPUR_USER_MASK'].split(','):
                if user_mask in this_user:
                    break
            else:
                if this_user not in proc_usr:
                    proc_usr[this_user] = []
                proc_usr[this_user].append(this_pid)
        
        proc_usr_str = ""
        for this_user in proc_usr.keys():
            if config['GPUR_SHOW_PID'] == 'full':
                this_pids = "(" + ",".join([str(i) for i in proc_usr[this_user]]) + ")"
            elif config['GPUR_SHOW_PID'] == 'num':
                this_pids = "[" + str(len(proc_usr[this_user])) + "]"
            elif config['GPUR_SHOW_PID'] == 'off':
                this_pids = ""
            for user_hl in config['GPUR_USER_NAME'].split(','):
                if user_hl in this_user:
                    proc_usr_str += f'{bcolors.GREEN}{this_user}{this_pids}{bcolors.ENDC} '
                    break
            else:
                proc_usr_str += f'{this_user}{this_pids} '
        return proc_usr_str
    
    dispatcher = {
        'host': compose(format_failure, format_gpu),
        'gpu': format_gpu,
        'gpu_mem_avail': format_gpu,
        'users': format_user,
        'comment': format_failure,
        '*': lambda x:x
    }

    return dispatcher.get(col, dispatcher['*'])(original)


if __name__ == '__main__':
    config = get_config()
    for key in config:
        if key in os.environ:
            config[key] = os.environ[key]

    columns = config['GPUR_COLUMNS'].split(',')

    worker_pool = Pool(int(config['GPUR_QUERY_BATCH_SIZE']))
    server_list = config['GPUR_SERVER_LIST'].split(',')
    
    if bool(int(config['GPUR_PBAR'])):
        with yaspin.yaspin(text='Querying...'):
            results = worker_pool.map(partial(query_worker, config=config), server_list)
    else:
        results = worker_pool.map(partial(query_worker, config=config), server_list)
    
    worker_pool.close()
    
    host_rows = []
    for res in results:
        if res['successful']:
            host_rows += host_info_parser(res)
        else:
            host_rows += [res]

    all_rows = []
    for row in host_rows:
        all_rows.append(column_filter(row, columns, formatter=partial(context_formatter, config=config)))
        
    print(tabulate.tabulate(all_rows, headers=columns))
