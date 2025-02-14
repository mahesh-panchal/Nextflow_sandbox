#! /usr/bin/env bash

# Upgrade Nextflow
nextflow self-update

# Install Pixi
sudo chown gitpod -R /home/gitpod/
curl -fsSL https://pixi.sh/install.sh | bash
. /home/gitpod/.bashrc

# Run workflow
nextflow run main.nf
