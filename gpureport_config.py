import os
import copy
from collections import defaultdict

config =dict(
    # A list of hosts to query
    GPUR_SERVER_LIST = [f'host{i}' for i in range(11)],
    
    # Path to the ssh client
    GPUR_SSH_BIN = '/usr/bin/ssh',

    # Columns to display as a comma-separated list
    # Available columns:
    # host,gpu,gpu_mem_avail,gpu_mem_total,gpu_util,gpu_temp,gpu_power,
    # gpu_power_max,cpu_load,cpu_count,mem_avail,mem_total,users,comment
    GPUR_COLUMNS = "host,gpu,gpu_mem_avail,gpu_mem_total,gpu_util,gpu_temp,gpu_power,cpu_load,cpu_count,mem_avail,mem_total,users,comment",
    
    # Maximum simultaneous query
    GPUR_QUERY_BATCH_SIZE = str(os.cpu_count()),
    
    # If set to 1, display progress message and wheel
    GPUR_PBAR = '1',
    
    # GPUs with remaining memory higher than THRES(MB) will be highlighted.
    GPUR_MEM_THRES = '5000',
    
    # A username will be highlighed if it contains strings in the following list
    # The list is comma-separated
    GPUR_USER_NAME = 'ziwei',
    # A username will not be shown if it contains strings in the following list
    # The list is comma-separated
    GPUR_USER_MASK = 'gdm',
    
    # Classify a server as "SSH timeout" if a query is not completed within
    # SSH_TIMEOUT seconds.
    GPUR_SSH_TIMEOUT = '5',
    
    # Constants, no need to change in general. 
    GPUR_CODE_TIMEOUT = '142',
    GPUR_CODE_SERVER_SIDE_ERROR = '143',
    GPUR_CODE_AUTH_ERROR = '255'
)

def get_config():
    return copy.deepcopy(config)
