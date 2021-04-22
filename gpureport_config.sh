#!/bin/bash
# shellcheck disable=SC2034 

# A list of hosts to query
SERVER_LIST=( hostname1 hostname2 hostname3 )

# A username will be highlighed in the report if it contains USER_NAME
USER_NAME="ziwei"

# GPUs with remaining memory higher than THRES(GB) will be highlighted.
# This value must be an integer.
THRES=6

# Classify a server as "SSH timeout" if a query is not completed within
# SSH_TIMEOUT seconds.
SSH_TIMEOUT=15