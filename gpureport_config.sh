#!/bin/bash
# shellcheck disable=SC2034 

# A list of hosts to query
SERVER_LIST=( host1 host2 host3 )

# Spawn QUERY_BATCH_SIZE queries as a batch, wait until this batch is done, 
# spawn a new batch, repeat until finish.
QUERY_BATCH_SIZE=100

# GPUs with remaining memory higher than THRES(MB) will be highlighted.
# This value must be an integer.
GPU_MEM_THRES=5000

# A username will be highlighed in the report if it contains USER_NAME
# It has nothing to do with authentication.
USER_NAME="replace_with_perhaps_a_part_of_your_user_name"

# Classify a server as "SSH timeout" if a query is not completed within
# SSH_TIMEOUT seconds.
SSH_TIMEOUT=30

# Temp dir to write GPU info to. It must be at least rw- for the user.
TEMP_DIR="/tmp/.gpu_report/"

# Constants, no need to change in general.
TIME_OUT_CODE=142
SERVER_SIDE_ERROR_CODE=143
SSH_AUTH_ERROR_CODE=255
