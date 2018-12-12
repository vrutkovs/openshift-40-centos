BASE_DOMAIN=origin-gce.dev.openshift.com
MOUNT_FLAGS=:z
PODMAN=sudo podman
PODMAN_RUN=${PODMAN} run --privileged --rm -v $(shell pwd):/output${MOUNT_FLAGS} --user $(shell id -u)
INSTALLER_IMAGE=registry.svc.ci.openshift.org/openshift/origin-v4.0:installer
ANSIBLE_IMAGE=quay.io/vrutkovs/openshift-40-centos
ADDITIONAL_PARAMS=-e INSTANCE_PREFIX="${USERNAME}" -e OPTS="-vvv"
LATEST_RELEASE=
ifneq ("$(LATEST_RELEASE)","")
	RELEASE_IMAGE=registry.svc.ci.openshift.org/openshift/origin-release:v4.0
endif
ANSIBLE_REPO=
ifneq ("$(ANSIBLE_REPO)","")
	ANSIBLE_MOUNT_OPTS=-v ${ANSIBLE_REPO}:/usr/share/ansible/openshift-ansible${MOUNT_FLAGS}
endif

all: help
install: check cleanup pull-installer config pull-ansible-image provision ## Start install from scratch

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

check: ## Verify all necessary files exist
	if [ -z ${USERNAME} ]; then                 \
		echo "Make sure USERNAME env var is set " \
		exit 1;                                   \
	fi;
	if [ ! -f ./pull_secret.json ]; then   \
	  echo "Pull secret not found!"        \
	  exit 1;                              \
	fi;
	if [ ! -d injected ]; then             \
	  echo "injected directory not found!" \
	  exit 1;                              \
	fi;

cleanup: ## Remove remaining installer bits
	rm -rvf install-config.yml .openshift_install_state.json .openshift_install.log *.ign || true

pull-installer: ## Pull fresh installer image
	${PODMAN} pull ${INSTALLER_IMAGE}

config: check ## Prepare a fresh bootstrap.ign
	${PODMAN_RUN} --rm -ti ${INSTALLER_IMAGE} version
	env BASE_DOMAIN=${BASE_DOMAIN} ansible all -i "localhost," --connection=local -e "ansible_python_interpreter=/usr/bin/python3" \
	  -m template -a "src=install-config.yml.j2 dest=install-config.yml"
	${PODMAN_RUN} ${PODMAN_PARAMS} -ti ${INSTALLER_IMAGE} create ignition-configs
	cp bootstrap.ign injected/

shell: ## Open a shell in openshift-ansible container
	ADDITIONAL_PARAMS="${ADDITIONAL_PARAMS} --entrypoint=/bin/sh"
	make provision

pull-ansible-image: ## Pull latest openshift-ansible container
	${PODMAN} pull ${ANSIBLE_IMAGE}

provision: check ## Deploy GCE cluster
	mkdir -p ./auth
	chmod 777 ./auth
	${PODMAN_RUN} \
	  ${ANSIBLE_MOUNT_OPTS} \
	  -v $(shell pwd)/injected:/usr/share/ansible/openshift-ansible/inventory/dynamic/injected${MOUNT_FLAGS} \
	  -v $(shell pwd)/auth:/tmp/artifacts/installer/auth${MOUNT_FLAGS} \
	  ${ADDITIONAL_PARAMS} \
	  -ti ${ANSIBLE_IMAGE}

deprovision: cleanup ## Remove GCE bits
	${PODMAN_RUN} \
	  ${ANSIBLE_MOUNT_OPTS} \
	  -v $(shell pwd)/injected:/usr/share/ansible/openshift-ansible/inventory/dynamic/injected${MOUNT_FLAGS} \
	  ${ADDITIONAL_PARAMS} \
	  -ti ${ANSIBLE_IMAGE} \
	  deprovision
