BASE_DOMAIN=devcluster.openshift.com
MOUNT_FLAGS=:z
PODMAN=sudo podman
PODMAN_RUN=${PODMAN} run --privileged --rm -v $(shell pwd):/output${MOUNT_FLAGS} --user $(shell id -u)
INSTALLER_IMAGE=registry.svc.ci.openshift.org/openshift/origin-v4.0:installer
ANSIBLE_IMAGE=quay.io/vrutkovs/openshift-40-centos
ADDITIONAL_PARAMS=-e INSTANCE_PREFIX="${USERNAME}" -e OPTS="-vvv -e openshift_install_config_path=/tmp/install-config.ansible.yaml"
PYTHON=/usr/bin/python3
LATEST_RELEASE=
ifneq ("$(LATEST_RELEASE)","")
	RELEASE_IMAGE=registry.svc.ci.openshift.org/openshift/origin-release:v4.0
endif
ifneq ("$(RELEASE_IMAGE)","")
	IGNITION_PARAMS=-e OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=${RELEASE_IMAGE}
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
	rm -rvf install-config.yaml install-config.ansible.yaml .openshift_install_state.json .openshift_install.log *.ign || true

pull-installer: ## Pull fresh installer image
	#${PODMAN} pull ${INSTALLER_IMAGE}

config: check ## Prepare a fresh bootstrap.ign
	${PODMAN_RUN} --rm -ti ${INSTALLER_IMAGE} version
	env BASE_DOMAIN=${BASE_DOMAIN} ansible all -i "localhost," --connection=local -e "ansible_python_interpreter=${PYTHON}" \
	  -m template -a "src=install-config.yaml.j2 dest=install-config.yaml"
	cp install-config{,.ansible}.yaml
	${PODMAN_RUN} ${IGNITION_PARAMS} -ti ${INSTALLER_IMAGE} create ignition-configs
	cp bootstrap.ign injected/

aws: check ## Create AWS cluster
	${PODMAN_RUN} --rm -ti ${INSTALLER_IMAGE} version
	env BASE_DOMAIN=${BASE_DOMAIN} ansible all -i "localhost," --connection=local -e "ansible_python_interpreter=${PYTHON}" \
	  -m template -a "src=install-config.yaml.j2 dest=install-config.yaml"
	cp install-config{,.ansible}.yaml
	${PODMAN_RUN} ${IGNITION_PARAMS} \
	  -e AWS_SHARED_CREDENTIALS_FILE=/tmp/.aws/credentials \
	  -v $(shell pwd)/injected/aws.conf:/tmp/.aws/credentials${MOUNT_FLAGS} \
	  -ti ${INSTALLER_IMAGE} create cluster --log-level debug

destroy-aws: ## Destroy AWS cluster
	cp install-config{.ansible,}.yaml
	${PODMAN_RUN} ${IGNITION_PARAMS} \
	  -e AWS_SHARED_CREDENTIALS_FILE=/tmp/.aws/credentials \
	  -v $(shell pwd)/injected/aws.conf:/tmp/.aws/credentials${MOUNT_FLAGS} \
	  -ti ${INSTALLER_IMAGE} destroy cluster --log-level debug
	make cleanup
	rm -rf terraform.tfstate terraform.tfvars tls/ metadata.json

shell: ## Open a shell in openshift-ansible container
	ADDITIONAL_PARAMS+=--entrypoint=/bin/sh
	make provision

pull-ansible-image: ## Pull latest openshift-ansible container
	#${PODMAN} pull ${ANSIBLE_IMAGE}

scaleup: check ## Scaleup AWS workers
	${PODMAN_RUN} \
	  ${ANSIBLE_MOUNT_OPTS} \
	  -v $(shell pwd)/root/usr/local/bin:/usr/local/bin${MOUNT_FLAGS} \
	  -v $(shell pwd)/injected:/usr/share/ansible/openshift-ansible/inventory/dynamic/injected${MOUNT_FLAGS} \
	  -v ~/.ssh:/usr/share/ansible/openshift-ansible/.ssh \
	  -v $(shell pwd)/install-config.ansible.yaml:/tmp/install-config.ansible.yaml${MOUNT_FLAGS} \
	  -v $(shell pwd)/auth:/auth${MOUNT_FLAGS} \
	  ${ADDITIONAL_PARAMS} \
	  -ti ${ANSIBLE_IMAGE}

provision: check ## Deploy GCE cluster
	${PODMAN_RUN} \
	  ${ANSIBLE_MOUNT_OPTS} \
	  -v ~/.ssh:
	  -v $(shell pwd)/injected:/usr/share/ansible/openshift-ansible/inventory/group_vars/new_workers${MOUNT_FLAGS} \
	  -v $(shell pwd)/auth:/tmp/artifacts/installer/auth${MOUNT_FLAGS} \
	  -v $(shell pwd)/install-config.ansible.yaml:/tmp/install-config.ansible.yaml${MOUNT_FLAGS} \
	  ${ADDITIONAL_PARAMS} \
	  -ti ${ANSIBLE_IMAGE}


deprovision: cleanup ## Remove GCE bits
	${PODMAN_RUN} \
	  ${ANSIBLE_MOUNT_OPTS} \
	  -v $(shell pwd)/injected:/usr/share/ansible/openshift-ansible/inventory/dynamic/injected${MOUNT_FLAGS} \
	  ${ADDITIONAL_PARAMS} \
	  -ti ${ANSIBLE_IMAGE} \
	  deprovision

pull-tests: ## Pull test image
	${PODMAN} pull registry.svc.ci.openshift.org/openshift/origin-v4.0:tests

test: ## Run openshift tests
	rm -rf test-artifacts/
	mkdir test-artifacts
	${PODMAN_RUN} \
	  ${ANSIBLE_MOUNT_OPTS} \
	  -v $(shell pwd)/auth:/auth${MOUNT_FLAGS} \
	  -v $(shell pwd)/test.sh:/usr/bin/test.sh \
	  -v $(shell pwd)/test-artifacts:/tmp/artifacts \
	  -v ~/.ssh:/usr/share/ansible/openshift-ansible/.ssh \
	  ${ADDITIONAL_PARAMS} \
	  --entrypoint=/bin/sh \
	  -ti registry.svc.ci.openshift.org/openshift/origin-v4.0:tests \
	  /usr/bin/test.sh
