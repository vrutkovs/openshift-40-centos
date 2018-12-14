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
Run `make install USERNAME=<your username>`

It would do the following:
* Use openshift-installer to create install configs
* Update configs to start 3 masters and 3 workers
* Use openshift-installer to create Ignition configs for bootstrap node
* Run a playbook, which would convert Ignition files into ansible tasks and provisions the cluster

In the end the playbook would create `./auth/kubeconfig` file, which can be used to access the cluster:
```
export KUBECONFIG=./auth/kubeconfig
oc status
```

Deprovision the cluster by running `make deprovision USERNAME=<your username>`.

# Tips & tricks
* Mount your own version of openshift-ansible with `make ANSIBLE_REPO=local/path/to/openshift-ansible`

* Check `make help` for Makefile target descriptions

* If the playbook fails enter the container shell:
`make config shell`, adjust the playbook and run `/usr/local/bin/entrypoint-gcp /usr/local/bin/run` in the container
to start the deploy

# Where's my console?

Currently its tricky to get to the console:

* Get node port used by default router
```
$ oc get svc router-default -n openshift-ingress
NAME             TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
router-default   LoadBalancer   172.30.251.19   <pending>     80:30374/TCP,443:31306/TCP   17m
```

Note the port used for 443 - its 31306 in my case, but in other clusters its a random number between
30000 and 32000.

* Edit '<username>-ig-n' instance group in GCE console and set port mapping - e.g. `port-8443` to LB nodeport
* Go to Network Services - Load Balancer and create a load balancer for nodes
  * Create Load Balancer
  * TCP Load Balancing
    * From Internet to my machines
    * Multiple regions (or not sure yet)
    * Connection termination - Yes
  * Backend
    * Instance group - <username>-ig-n (check that named port is correct, GCE may take a while to apply changes)
    * Health check - create a TCP healthcheck pointing to node port number
  * Frontend
    * Protocol - TCP
    * IP address - reserve a new static address, make sure you specify this name
    * Port - 443
* Go to Network Services - Cloud DNS - <your managed zone>:
  * Create a new A entry for `*.apps.<cluster name>.<base DNS>.` pointing to the static address from previous step
* After a while console would be available at https://console-openshift-console.apps.<clustername>.<baseDNS>
* Now openshift-installer should have created a `kubeadmin` user - but it won't tell us the password yet, so it needs to be reset:
```
oc delete secret kubeadmin -n kube-system
oc create secret generic kubeadmin -n kube-system --from-literal=kubeadmin="$(htpasswd -bnBC 10 "" '5char-5char-5char-5char' | tr -d ':\n')"
```
Login in the console using kubeadmin/5char-5char-5char-5char
