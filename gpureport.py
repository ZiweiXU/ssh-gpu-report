import os
import json
import subprocess
from multiprocessing import Pool
from functools import partial
from typing import List

try:
    import tabulate, yaspin
except:
    raise ModuleNotFoundError("Please install tabulate and yaspin using ``pip install --user tabulate yaspin''")

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
            result.update({'successful': False, 'comment': 'Server Side'})
        elif return_code == int(config['GPUR_CODE_AUTH_ERROR']):
            result.update({'successful': False, 'comment': 'Auth Err'})
        else:
            result.update({'successful': False, 'comment': f'Unk Err {result.returncode}'})

    return result

def host_info_generator(host_result) -> List[List]:
    host = host_result['host']
    gpu_info, cpu_load, cpu_count = host_result['payload'].split('\n')[:-1]
    gpu_info = json.loads(gpu_info)

    host_rows = []
    gpu_num = len(gpu_info['gpus'])
    for gpu in range(gpu_num):
        this_gpu = gpu_info['gpus'][gpu]
        row_gpu_info = {}
        row_gpu_info['host'] = host
        row_gpu_info['gpu'] = gpu
        
        row_gpu_info['gpu_mem_used'] = this_gpu['memory.used']
        row_gpu_info['gpu_mem_total'] = this_gpu['memory.total']
        row_gpu_info['gpu_mem_avail'] = row_gpu_info['gpu_mem_total'] - row_gpu_info['gpu_mem_used']

        if float(row_gpu_info['gpu_mem_avail']) > float(config['GPUR_MEM_THRES']):
            row_gpu_info['gpu'] = f'{bcolors.CYAN}{bcolors.BOLD}{gpu}{bcolors.ENDC}'
            row_gpu_info['host'] = f'{bcolors.CYAN}{bcolors.BOLD}{host}{bcolors.ENDC}'
            row_gpu_info['gpu_mem_avail'] = f'{bcolors.CYAN}{bcolors.BOLD}{row_gpu_info["gpu_mem_avail"]}{bcolors.ENDC}'

        row_gpu_info['gpu_power_max'] = this_gpu['enforced.power.limit']
        row_gpu_info['gpu_power'] = this_gpu['power.draw']
        row_gpu_info['gpu_util'] = this_gpu['utilization.gpu']
        row_gpu_info['gpu_temp'] = this_gpu['temperature.gpu']
        
        process_num = len(this_gpu['processes'])
        proc_usr = ""
        for proc in range(process_num):
            this_user = this_gpu['processes'][proc]['username']
            this_pid = this_gpu['processes'][proc]['pid']
            for user_mask in config['GPUR_USER_MASK'].split(','):
                if user_mask in this_user:
                    break
            else:
                for user_hl in config['GPUR_USER_NAME'].split(','):
                    if user_hl in this_user:
                        proc_usr += f'{bcolors.GREEN}{this_user}({this_pid}){bcolors.ENDC} '
                        break
                else:
                    proc_usr += f'{this_user}({this_pid}) '

        row_gpu_info['users'] = proc_usr
        row_gpu_info['cpu_load'] = cpu_load
        row_gpu_info['cpu_count'] = cpu_count
        row_gpu_info['comment'] = host_result['comment']

        host_rows.append(row_gpu_info)
    
    return host_rows


def column_filter(host_row, columns):
    this_row = []
    for col in columns:
        if col in host_row:
            this_row.append(host_row[col])
        else:
            this_row.append('-')
    return this_row


if __name__ == '__main__':
    config = get_config()
    for key in config:
        if key in os.environ:
            config[key] = os.environ[key]

    columns = config['GPUR_COLUMNS'].split(',')

    worker_pool = Pool(int(config['GPUR_QUERY_BATCH_SIZE']))
    server_list = config['GPUR_SERVER_LIST']
    
    if bool(int(config['GPUR_PBAR'])):
        with yaspin.yaspin(text='Querying... ', side='right', timer=True):
            results = worker_pool.map(partial(query_worker, config=config), server_list)
    else:
        results = worker_pool.map(partial(query_worker, config=config), server_list)
    
    worker_pool.close()

    host_rows = []
    for res in results:
        if res['successful']:
            host_rows += host_info_generator(res)
        else:
            host_rows += [res]

    all_rows = []
    for row in host_rows:
        all_rows.append(column_filter(row, columns))
        
    print(tabulate.tabulate(all_rows, headers=columns))
