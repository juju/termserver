#!/bin/bash

keyname=jujushell@`hostname`
keypath=~/.ssh/id_rsa

# Print usage information and exit with an error.
usage() {
    echo "usage: `basename $0` (setup|teardown)"
    exit 1
}

# Create SSH keys if not already present.
_jujushell_create_ssh_keys() {
    [ -f $keypath ] && return
    ssh-keygen -t rsa -b 4096 -N "" -C "$keyname" -f $keypath
}

# Upload SSH keys to all juju models.
_jujushell_add_ssh_keys() {
    key=`cat $keypath.pub`
    for model in `_jujushell_models`; do
        juju add-ssh-key -m "$model" "$key" &
    done
    wait
}

# Remove SSH keys from juju models.
_jujushell_remove_ssh_keys() {
    for model in `_jujushell_models`; do
        juju remove-ssh-key -m "$model" "$keyname" &
    done
    wait
}

# Return a newline separated list of current juju models.
_jujushell_models() {
    juju models --format json | jq -r .models[].name
}

# Initialize the jujushell session.
# Calling this function assumes juju has been already set up and authenticated
# against a controller.
setup() {
    _jujushell_create_ssh_keys
    _jujushell_add_ssh_keys
}

# Tear down the jujushell session.
teardown() {
    _jujushell_remove_ssh_keys
}

# Validate arguments.
[ "$#" -ne 1 ] && usage
case $1 in
setup) setup;;
teardown) teardown;;
*) usage;;
esac
