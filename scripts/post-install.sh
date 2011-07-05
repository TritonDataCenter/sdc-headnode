#!/bin/bash

# Copyright 2011 Joyent, Inc. All rights reserved.

# This is an example post-install script.
# Post-install scripts are not formally suported features
# and are not intended to be used for anything other than
# test purposes.


set -o errexit
set -o pipefail

# Do something here
# ex.
# uuid=`sysinfo | json UUID`
# callbackhost='1.2.3.4'
# curl -X POST http://$callbackhost/setup/complete?uuid=$uuid

exit 0;
