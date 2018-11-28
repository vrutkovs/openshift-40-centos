#!/bin/sh
set -eux

if (( $# != 1 )); then
  echo "Usage: ./run.sh <username>"
  exit 1
fi

USERNAME=$1
INSTALLER_IMAGE="registry.svc.ci.openshift.org/openshift/origin-v4.0:installer"
ANSIBLE_IMAGE="quay.io/vrutkovs/openshift-40-centos"
PODMAN="sudo podman"
PODMAN_PULL="${PODMAN} pull"
PODMAN_RUN="${PODMAN} run"


if [ ! -f ./pull_secret.json ]; then
  echo "Pull secret not found!"
  exit 1
fi

if [ ! -d injected ]; then
  echo "injected directory not found!"
  exit 1
fi

echo "Removing existing artifacts"
rm -rvf install-config.yml .openshift_install_state.json .openshift_install.log *.ign || true

echo
echo "Fetching installer"
${PODMAN_PULL} ${INSTALLER_IMAGE}
${PODMAN_RUN} -rm -ti ${INSTALLER_IMAGE} version

echo
echo "Creating bootstrap.ign"
${PODMAN_RUN} --rm \
  -v $(pwd):/output \
  -e OPENSHIFT_INSTALL_PLATFORM="libvirt" \
  -e OPENSHIFT_INSTALL_LIBVIRT_URI="qemu+tcp://192.168.122.1/system" \
  -e OPENSHIFT_INSTALL_LIBVIRT_IMAGE="file:///unused" \
  -e OPENSHIFT_INSTALL_CLUSTER_NAME="${USERNAME}" \
  -e OPENSHIFT_INSTALL_BASE_DOMAIN="origin-gce.dev.openshift.com" \
  -e OPENSHIFT_INSTALL_EMAIL_ADDRESS="whatever@redhat.com" \
  -e OPENSHIFT_INSTALL_PASSWORD="muchsecuritywow" \
  -e OPENSHIFT_INSTALL_PULL_SECRET_PATH="/output/pull_secret.json" \
  -ti ${INSTALLER_IMAGE} \
  create install-config

sed -i "/master/{n;s/1/3/}" .openshift_install_state.json
sed -i "/worker/{n;s/1/3/}" .openshift_install_state.json
sed -i "/master/{n;n;s/1/3/}" install-config.yml
sed -i "/worker/{n;n;s/1/3/}" install-config.yml

${PODMAN_RUN} --rm \
  -v $(pwd):/output \
  -e OPENSHIFT_INSTALL_PLATFORM="libvirt" \
  -e OPENSHIFT_INSTALL_LIBVIRT_URI="qemu+tcp://192.168.122.1/system" \
  -e OPENSHIFT_INSTALL_CLUSTER_NAME="${USERNAME}" \
  -e OPENSHIFT_INSTALL_BASE_DOMAIN="origin-gce.dev.openshift.com" \
  -e OPENSHIFT_INSTALL_EMAIL_ADDRESS="whatever@redhat.com" \
  -e OPENSHIFT_INSTALL_PASSWORD="muchsecuritywow" \
  -e OPENSHIFT_INSTALL_PULL_SECRET_PATH="/output/pull_secret.json" \
  -ti ${INSTALLER_IMAGE} \
  create ignition-configs

cp bootstrap.ign injected/

echo
echo "Provisioning GCP cluster"
mkdir -p ./auth
chmod 777 ./auth
${PODMAN_PULL} ${ANSIBLE_IMAGE}
${PODMAN_RUN} --rm \
  -v $(pwd)/injected:/usr/share/ansible/openshift-ansible/inventory/dynamic/injected \
  -v $(pwd)/auth:/tmp/artifacts/installer/auth \
  -e INSTANCE_PREFIX="${USERNAME}" \
  -e OPTS="-vvv" \
  -ti ${ANSIBLE_IMAGE}

export KUBECONFIG=./auth/kubeconfig
oc get nodes

echo "Cluster provisioned"
