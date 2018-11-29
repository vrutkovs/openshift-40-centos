[![Docker Repository on Quay](https://quay.io/repository/vrutkovs/openshift-40-centos/status "Docker Repository on Quay")](https://quay.io/repository/vrutkovs/openshift-40-centos)

# Getting started with Openshift 4.0 on GCP

Note, that this is a development version, alpha-stage.

This repo would create a container with openshift-ansible fork and necessary tools to provision CentOS machines on GCP and
use Ignition files to bootstrap the cluster.

Requirements:
* `podman`
* `oc`
* Pull secret for images
* GCP account credentials in a json
* SSH private key

# Prepare GCP creds
Put your pull secret in `pull_secret.json`

Prepare "injected/" directory which contains the following files (see `example-injected` folder):
* `gce.json` - this is the JSON which GCP uses to authenticate
* `ssh-privatekey` - private key which would be used to access instances (e.g. `libra.pem`)
* `vars.yaml` - GCP-related vars - projects, instances to provision etc.
* `vars-origin.yaml` - Origin-related vars

# Start the install
Run `./start.sh <your username>`

It would do the following:
* Use openshift-installer to create install configs
* Update configs to start 3 masters and 3 workers
* Use openshift-installer to create Ignition configs for bootstrap node
* Run a playbook, which would convert Ignition files into ansible tasks and provisions the cluster

In the end the playbook would create `./auth/kubeconfig` file, which can be used to access the cluster
and start 'sh' shell.
Exit the shell (Ctrl+D) to start cluster deprovision.
