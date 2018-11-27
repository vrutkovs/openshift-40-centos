[![Docker Repository on Quay](https://quay.io/repository/vrutkovs/openshift-40-centos/status "Docker Repository on Quay")](https://quay.io/repository/vrutkovs/openshift-40-centos)

# Getting started with Openshift 4.0 on GCP

Note, that this is a development version, alpha-stage.

This repo would create a container with openshift-ansible fork and necessary tools to provision CentOS machines on GCP and 
use Ignition files to bootstrap the cluster.

# Create `bootstrap.ign`
Put your pull secret in `pull_secret.json` and run:
```
# Pull the latest installer image and create install configs
sudo podman pull registry.svc.ci.openshift.org/openshift/origin-v4.0:installer
sudo podman run --rm \
  -v $(pwd):/output \
  -e OPENSHIFT_INSTALL_PLATFORM="libvirt" \
  -e OPENSHIFT_INSTALL_LIBVIRT_URI="qemu+tcp://192.168.122.1/system" \
  -e OPENSHIFT_INSTALL_LIBVIRT_IMAGE="file:///unused" \
  -e OPENSHIFT_INSTALL_CLUSTER_NAME="<yourname>" \
  -e OPENSHIFT_INSTALL_BASE_DOMAIN="origin-gce.dev.openshift.com" \
  -e OPENSHIFT_INSTALL_EMAIL_ADDRESS="<yourname>@redhat.com" \
  -e OPENSHIFT_INSTALL_PASSWORD="muchsecuritywow" \
  -e OPENSHIFT_INSTALL_PULL_SECRET_PATH="/output/pull_secret.json" \
  -ti registry.svc.ci.openshift.org/openshift/origin-v4.0:installer \
  create install-config

# Update install configs to set 3 masters and 3 workers
sed -i "/master/{n;s/1/3/}" .openshift_install_state.json
sed -i "/worker/{n;s/1/3/}" .openshift_install_state.json
sed -i "/master/{n;n;s/1/3/}" install-config.yml
sed -i "/worker/{n;n;s/1/3/}" install-config.yml

# Create ignition configs
sudo podman run --rm \              
  -v $(pwd):/output \
  -e OPENSHIFT_INSTALL_PLATFORM="libvirt" \
  -e OPENSHIFT_INSTALL_LIBVIRT_URI="qemu+tcp://192.168.122.1/system" \
  -e OPENSHIFT_INSTALL_CLUSTER_NAME="<yourname>" \      
  -e OPENSHIFT_INSTALL_BASE_DOMAIN="origin-gce.dev.openshift.com" \
  -e OPENSHIFT_INSTALL_EMAIL_ADDRESS="<yourname>@redhat.com" \              
  -e OPENSHIFT_INSTALL_PASSWORD="muchsecuritywow" \        
  -e OPENSHIFT_INSTALL_PULL_SECRET_PATH="/output/pull_secret.json" \
  -ti registry.svc.ci.openshift.org/openshift/origin-v4.0:installer \
  create ignition-configs
```

This would create three files - `bootstrap.ign`, `master.ign`, `worker.ign`

# Prepare GCP creds
Prepare a folder which consists the following files (see `example-injected` folder):
* `gce.json` - this is the JSON which GCP uses to authenticate
* `ssh-privatekey` - private key which would be used to access instances
* `vars.yaml` - GCP-related vars - projects, instances to provision etc.
* `vars-origin.yaml` - Origin-related vars
* `bootstrap.ign` - bootstrap ignition file from previous step

This folder would be used by playbooks

# Start the install
Create folder which would hold artifacts (most notably - kubeconfig to access the cluster) - say, `/tmp/gcp-cluster`.
Ansible would run as user `1001`, so make sure it would be able to write the kubeconfig:
```
mkdir -p /tmp/gcp-cluster/auth
chmod 777 /tmp/gcp-cluster/auth
sudo podman pull quay.io/vrutkovs/openshift-40-centos
sudo podman run --rm \
  -v /path/to/folder/from/previous/step:/usr/share/ansible/openshift-ansible/inventory/dynamic/injected \
  -v /tmp/gcp-cluster/auth:/tmp/artifacts/installer/auth \
  -e INSTANCE_PREFIX="<yourname>" \
  -e OPTS="-vvv" \
  -ti quay.io/vrutkovs/openshift-40-centos
```

The cluster should be ready in 20 mins, so once its done run:
```
export KUBECONFIG=/tmp/gcp-cluster/auth/kubeconfig
kubectl get nodes
```

# Deprovision

To deprovisoin the cluster and remove most of the GCP infra run:
```
sudo podman run --rm \
  -v /path/to/folder/from/previous/step:/usr/share/ansible/openshift-ansible/inventory/dynamic/injected \
  -e INSTANCE_PREFIX=vrutkovs \
  -e OPTS="-vvv" \
  -ti quay.io/vrutkovs/openshift-40-centos \
  deprovision
```
