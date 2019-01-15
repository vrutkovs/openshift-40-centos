#!/bin/sh
mkdir /tmp/output
cd /tmp/output
export KUBECONFIG=/auth/kubeconfig
export PROVIDER_ARGS="-provider=aws -gce-zone=eu-west-1"
# TODO: make openshift-tests auto-discover this from cluster config
export TEST_PROVIDER='{"type":"aws","region":"eu-west-1","zone":"eu-west-1a","multizone":true,"multimaster":true}'
export KUBE_SSH_USER=core
#export TEST_SKIP='(\|nfs\|NFS\|affinity\|deploymentconfigs\|PVC\|iSCSI\|GlusterDynamicProvisioner\|\[Feature:Builds\]\|build\|StatefulSetBasic\|ImageAppend\|registry\|ImageExtract\|forwarding\|NetworkPolicy\|templateinstance\|\[Feature:ImageLayers\]|\[Feature:ImageExtract\])'
#openshift-tests run "openshift/conformance/parallel" --dry-run | grep -v "${TEST_SKIP}" | openshift-tests run -f - --provider "" -o /tmp/artifacts/e2e.log --junit-dir /tmp/artifacts/junit
openshift-tests run "openshift/conformance/parallel" --provider "" -o /tmp/artifacts/e2e.log --junit-dir /tmp/artifacts/junit
