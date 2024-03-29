import os
import copy

# All the keys are in the format GPUR_[NAME_OF_THE_KEY]
# All the values can be overriden by environment variables
config = dict(
    # A list of hosts to query
    # The list is comma-separated
    GPUR_SERVER_LIST = ",".join([f'host{i}' for i in range(11)]),
    
    # Absolute path to the ssh client
    GPUR_SSH_BIN = '/usr/bin/ssh',

    # Columns to display
    # Available columns:
    #   host,gpu,gpu_mem_avail,gpu_mem_total,gpu_util,gpu_temp,gpu_power,
    #   gpu_power_max,cpu_load,cpu_count,mem_avail,mem_total,users,comment
    # The list is comma-separated
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
    
    # A username will be ignored if it contains strings in the following list
    # The list is comma-separated
    GPUR_USER_MASK = 'gdm',
    
    # Controls how PID information is displayed
    # If `full', show all the PIDs of a user
    # If `count', show count of the user's processes
    # If `off', only show the user's name
    GPUR_SHOW_PID = 'count',

    # Whether to show table header
    # If set to 1, display the header
    # If set to 0, the header will be hidden
    GPUR_TABLE_HEADER = '1',

    # Whether to format table cells
    # If set to 0, the cells will not be formatted (no colour highlights etc.)
    GPUR_TABLE_FORMAT = '1',
    
    # The query times out if it is not completed after this seconds.
    GPUR_SSH_TIMEOUT = '5',
    
    # Constants, no need to modify in general. 
    GPUR_CODE_TIMEOUT = '142',
    GPUR_CODE_SERVER_SIDE_ERROR = '143',
    GPUR_CODE_AUTH_ERROR = '255'
)

def get_config():
    return copy.deepcopy(config)

def override_config(this, that):
    for key in this:
        if key in that:
            this[key] = that[key]
