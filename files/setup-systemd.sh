#!/bin/sh

# Disable systemd services that are not required to start on boot.

systemctl -a | awk '{print $1}' | grep \.service | \
    grep -v apparmor | \
    grep -v cloud-init | \
    grep -v dbus | \
    grep -v network | \
    grep -v resolvconf | \
    grep -v termserver | \
    grep -v systemd | \
    while read line; do systemctl mask ${line}; done
