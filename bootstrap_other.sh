#!/bin/bash

# Install Tailscale
echo "====== [ Install Tailscale ] ======"
ansible-playbook /opt/scripts/ansible/tailscale/install_tailscale_ubuntu.yml
