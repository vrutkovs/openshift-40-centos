#!/bin/sh
mkdir /tmp/output
cd /tmp/output
export KUBECONFIG=/auth/kubeconfig
export TEST_SKIP='(\|nfs\|NFS\|affinity\|deploymentconfigs\|PVC\|iSCSI\|GlusterDynamicProvisioner\|\[Feature:Builds\]\|build\|StatefulSetBasic\|ImageAppend\|registry\|ImageExtract\|forwarding\|NetworkPolicy\|templateinstance\|\[Feature:ImageLayers\]|\[Feature:ImageExtract\])'
openshift-tests run "openshift/conformance/parallel" --dry-run | grep -v "${TEST_SKIP}" | openshift-tests run -f - --provider "" -o /tmp/artifacts/e2e.log --junit-dir /tmp/artifacts/junit
