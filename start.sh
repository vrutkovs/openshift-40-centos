#!/bin/sh
set -eux

if (( $# != 1 )); then
  echo "Usage: ./run.sh <username>"
  exit 1
fi

USERNAME=$1
# Replace with empty string to skip selinux relabel
MOUNT_FLAGS=":z"
# Update with docker if podman is not available
PODMAN="sudo podman"
# Add necessary flags, e.g. '--net=host --privileged' if needed
PODMAN_RUN="${PODMAN} run --rm -v $(pwd):/output${MOUNT_FLAGS} --user $(id -u)"
# Adjust installer params
PODMAN_PARAMS="-e OPENSHIFT_INSTALL_PLATFORM=libvirt \
-e OPENSHIFT_INSTALL_LIBVIRT_URI=qemu+tcp://192.168.122.1/system \
-e OPENSHIFT_INSTALL_LIBVIRT_IMAGE=file:///unused \
-e OPENSHIFT_INSTALL_CLUSTER_NAME=${USERNAME} \
-e OPENSHIFT_INSTALL_BASE_DOMAIN=origin-gce.dev.openshift.com \
-e OPENSHIFT_INSTALL_EMAIL_ADDRESS=whatever@redhat.com \
-e OPENSHIFT_INSTALL_PASSWORD=muchsecuritywow \
-e OPENSHIFT_INSTALL_PULL_SECRET_PATH=/output/pull_secret.json"

# Set local path of openshift-ansible repo to replace existing repo
ANSIBLE_REPO=""
ANSIBLE_MOUNT_OPTS=""
[ -z "${ANSIBLE_REPO}" ] || ANSIBLE_MOUNT_OPTS="-v ${ANSIBLE_REPO}:/usr/share/ansible/openshift-ansible${MOUNT_FLAGS}"

# Images
INSTALLER_IMAGE="registry.svc.ci.openshift.org/openshift/origin-v4.0:installer"
ANSIBLE_IMAGE="quay.io/vrutkovs/openshift-40-centos"

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
${PODMAN} pull ${INSTALLER_IMAGE}
${PODMAN_RUN} -rm -ti ${INSTALLER_IMAGE} version

echo
echo "Creating bootstrap.ign"
${PODMAN_RUN} $PODMAN_PARAMS -ti ${INSTALLER_IMAGE} create install-config

sed -i "/master/{n;s/1/3/}" .openshift_install_state.json
sed -i "/worker/{n;s/1/3/}" .openshift_install_state.json
sed -i "/master/{n;n;s/1/3/}" install-config.yml
sed -i "/worker/{n;n;s/1/3/}" install-config.yml

${PODMAN_RUN} $PODMAN_PARAMS -ti ${INSTALLER_IMAGE} create ignition-configs

cp bootstrap.ign injected/

echo
echo "Provisioning GCP cluster"
mkdir -p ./auth
chmod 777 ./auth
${PODMAN} pull ${ANSIBLE_IMAGE}
${PODMAN_RUN} \
  ${ANSIBLE_MOUNT_OPTS} \
  -v $(pwd)/injected:/usr/share/ansible/openshift-ansible/inventory/dynamic/injected${MOUNT_FLAGS} \
  -v $(pwd)/auth:/tmp/artifacts/installer/auth${MOUNT_FLAGS} \
  -e INSTANCE_PREFIX="${USERNAME}" \
  -e OPTS="-vvv" \
  -ti ${ANSIBLE_IMAGE}

export KUBECONFIG=./auth/kubeconfig
oc get nodes

echo "Cluster provisioned"
echo "Exit the shell to deprovision cluster"
sh

${PODMAN_RUN} \
  ${ANSIBLE_MOUNT_OPTS} \
  -v $(pwd)/injected:/usr/share/ansible/openshift-ansible/inventory/dynamic/injected${MOUNT_FLAGS} \
  -e INSTANCE_PREFIX="${USERNAME}" \
  -e OPTS="-vvv" \
  -ti ${ANSIBLE_IMAGE} \
  deprovision
