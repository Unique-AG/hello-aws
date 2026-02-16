#!/bin/bash
set -e
# shellcheck disable=SC2154,SC2086 # hostname is a Terraform template variable
hostnamectl set-hostname "${hostname}"
echo "Management server ready at $(date)" >> /var/log/user-data.log
