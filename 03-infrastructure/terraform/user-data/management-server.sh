#!/bin/bash
set -e
hostnamectl set-hostname ${hostname}
echo "Management server ready at $(date)" >> /var/log/user-data.log
