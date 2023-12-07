# cloud-computing-project

## Base steps

### Deploying the original application in GKE

We started by creating a GKE cluster in order to deploy the application in it.
As explained in the lab assignment, there are 2 types of Kubernetes clusters we
can use in this case when working with the GKE service: standard GKE clusters,
and Autopilot GKE clusters.

The difference between these 2 types of clusters is that in the former, workers
are managed by the user, while in the latter, they are managed by GCP in a
transparent way with respect to the cluster users. The main advantages of
autopilot clusters compared to standard ones are:

- That it eases the admistration
of the Kubernetes cluster because the administrator doesn't need to manage the
compute capacity of the cluster.
- That it can be more cost effectif since the user doesn't pay for any unused
compute capacity in the workers.

While working on this lab, we noticed that while the scale out operations where
completely automated and transparent to us as users of GKE, it had a big impact
on the time needed for Kubernetes resources to be scheduled and assigned to a
worker node. This, in addition to the other inconvenients mentionned in the lab,
is why we decided to work with standard Kubernetes clusters for this lab, while
making sure that we don't over-provision compute resources.

The commands we typically used to create the Kubernetes cluster is as follows:

```bash
# the GCP project ID
export PROJECT_ID=xxxxxxxxxxxxx
# the type of the worker nodes
export M_TYPE=e2-standard-2
# the zone in which to create the cluster
export ZONE=us-central1-b

gcloud container clusters create $CLUSTER_NAME \
  --cluster-version latest \
  --machine-type=$M_TYPE \
  --num-nodes 3 \
  --zone $ZONE \
  --project $PROJECT_ID --enable-network-policy
```

The syntax we use here is specific to Unix systems, it may need to be adapted
for non compatible environments, such as Powershell or CMD on Windows. Moreover, It can be executed either
on a cloud shell instance of the GCP project you are working with, or in a
personal machine where the `gcloud` CLI tool is installed and authenticated.

We can then execute the following command in order to setup the Kubernetes
credentials to use the `kubectl` CLI tool:

```bash
gcloud container cluster get-credentials $CLUSTER_NAME --zone=$ZONE
```

The following steps will require the `kubectl` tool to be installed on the machine
you are currently using.

In order to deploy the application on the newly created GKE cluster we need to
execute the following command, which is going to apply each one of the YAMl
resource definitions in the referenced file:

```bash
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml
```

We then execute the following command that watches the state of the deployments
created on the cluster, and we wait until all the deployments are ready (1/1) before
moving to the next steps:

```bash
kubectl get deploy -w
```

Now that all the microservices of the application are deployed and ready, we can
fetch the IP addresse that was assigned to the LoadBalancer service (named `frontend-external`) that exposes
the application's frontend on the internet:

```bash
kubectl get svc frontend-external | awk '{print $4}' | tail -1
```

If the result is `<pending>`, this means that the load balancer is still getting created
and that the public IP adresse wasn't assigned to the service yet. This process can take
some time.

We can then check if the application is working by visiting the IP adresse we just
got in a web browser. We can also verify the logs of the load generation microservice
by executing the following command:

```bash
kubectl logs -f $(kubectl get -l app=loadgenerator -o name)
```

This command contains a sub-command that fetches the name of the pod that was
created for the `loadgenerator` deployment, which will then be passed to another
`kubectl` command that fetches and follows its logs. If everything's working as
should, you will find a low (possibly 0) failure rate in the load generator
statistics.

### Analyzing the provided configuration

We choose the service `cartservice` for which the configuration is as follows:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cartservice
spec:
  type: ClusterIP
  selector:
    app: cartservice
  ports:
  - name: grpc
    port: 7070
    targetPort: 7070
```

Similarly to every other kind of Kubernetes resource, this YAML manifest starts
by definition the version of the API it's referecing, in this case it's `v1`, which
references the [version 1 of the core API](https://pkg.go.dev/k8s.io/api/core/v1#Service).
Then, we have the kind of Kubernetes resource which is defined, a service, followed by
the metadata that will be associated to it, which in this case is its name.
The last element is the spec of this service which contains all of its core configuration.
Detailed information about all the possible configurations can be obtained by
executing the following command:

```bash
kubectl explain service.spec
```

In our case:
- The `type` of this service is `ClusterIP`, which means that it will be accessible
only from inside the Kubernetes cluster, by other workloads that are deployed on it.
- The `selector` of this service is a map containing 1 key-value pair `app: cartservice`.
This will instruct the service to register all the pods that have the label `app: cartservice`
as endpoints, and balance the incoming load between those pods.
- The `ports` of this service are the ports that are going to be exposed by it. In our case
we only have one port, which is defined by its name `grpc`, its port `7070` and its target port
(meaning the port on which it forward incoming traffic on the registered pods) is also `7070`.


### Targeting a minimal deployment

After carefully testing the application and removing selected microservices, we
settled on the following minimal configuration composed of the following microservices:
- checkoutservice
- frontend
- paymentservice
- productcatalogservice
- cartservice
- currencyservice
- shippingservice
- redis-cart

We removed the deployment and service resources of all the other microservices,
and were left with [this YAML manifest](./minimal-manifest.yaml).
(this file also contains declarations of a second version of the productcatalog Service
and the Orderlog service that we will discuss in the rest of this report).

We then apply this minimal manifest after deleting the old one:

```bash
kubectl delete -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml
kubectl apply -f ./minimal-manifest.yaml
```

The second command should be executed in a location where the current git repository
is cloned.

### Deploying the load generator on a local machine

As the lab explains, we are going to deploy the load generator separately from the
GKE cluster were the rest of the application resides. For this step, we chose to deploy
locally using Docker.

In order to do this, and to simplify some of the tasks in the next steps of this lab,
we chose to [make some minor changes](./loadgenerator-dockerfile) to the Dockerfile that's provided in the
[application repository](https://github.com/GoogleCloudPlatform/microservices-demo).
The main change we made was removing the `ENTRYPOINT` of the docker image,
because we wanted to customize the command that will be passed to the container
upon its creation.

This new Dockerfile should be put instead of the old Dockerfile (in the same location),
and built using the following command:

```bash
docker build -t newloadgenerator .
```

In order to easily share this image and to simplify its usage in the following steps,
we chose to push it to [DockerHub](https://hub.docker.com/repository/docker/hamza13/loadgen2/general)
using the name `hamza13/loadgen2`.


The docker container can then be launched locally using the following command:

```bash
export FRONTEND_IP=$(kubectl get svc frontend-external | awk '{print $4}' | tail -1)
docker run -d hamza13/loadgen2 locust --headless --host=http://$FRONTEND_IP
```

The first command fetches the public IP address of the application's frontend
and stores it in the variable `FRONTEND_IP` which will then be used by the second
command, in which we start a docker container using the docker image we built before
and we pass to it the Locust CLI command to run it in headless mode and to specify the host.

### Deploying automatically the load generator in Google cloud

As explained by the lab, it will be better to deploy the load generator on the cloud
since that will provide more consistant and replicable results, but outside of the
GKE cluster in which we deployed the application so that it doesn't consume
compute resources that are destined for the application itself.

To do this we decided to deploy the load generator automatically on a GCE virtual
machine that is provisionned using Terraform. This VM will then be configured
using ansible playbooks.

NB: There were many changes to the code that was written at this step of the project
because of the requirements of the next steps. In order to view the state of the code
at this particular step, switch to the branch BRANCH_NAME. TODO: add branch from old commit.

The setup we made functions as follows:
- We start by creating a service account using the following commands:
```bash
# the name of the service account to create
export SERVICE_ACCOUNT=terraform
# the GCP project ID
export $PROJECT_ID=xxxxxxxxxxxxx

gcloud iam service-accounts create $SERVICE_ACCOUNT
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:$SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com \
    --role roles/editor
gcloud iam service-accounts keys create ./$SERVICE_ACCOUNT.json \
    --iam-account $SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com
```

NB: this is a one time setup, meaning that it should only be done once per GCP project,
with the exception of the last `gcloud` command, that should be executed once in
every local machine used to provision cloud resources, since the resulting JSON
file *should not* be commited into source control.

- The rest of the process is largly automated, since we only have to execute one
bash script in order to trigger the provisionning and configuration of the
GCE virtual machine used to run the load generator. The following command shows
how this can be done:
```bash
bash ./main.sh
```

The `main.sh` file (TODO: add link to the file) does the following (in this order):
1. Initializes Terraform, by fetching all the necessary providers.
2. Generates an ssh key-pair that will be used to access the GCE virtual machine
that we will be creating.
3. Applies the terraform resources that are described in the terraform files that
exist in the current working directory of the shell, which should be the root of
the project. These files are:
    - simple_deployment.tf (TODO: add link to this file): which declares the
    following cloud resources:
        - A firewall: to restrict the access to the machine to the port 22 (for ssh),
        with the TCP protocol.
        - A Google compute instance which is the VM we're creating, to which we
        give the ssh public key we created before. We chose to make this VM a spot
        instance since this will help us reduce the costs of our tests whithout
        having any effect on the Online boutique application that runs independently
        from the load generation infrastructure.
    - variables.tf (TODO: add link to this file): which contains declarations of
    some the variables used by terraform, such as the GCP project ID and the
    region in which the resources will be deployed.
4. Executes a `setup.sh` bash file that is responsible for configuring the newly
created VM. This script does the following:
    1. Creates an ansible inventory file containing the public IP of the newly created
    VM. This IP is provided by terraform as an output.
    2. Fetches the IP address of the Online Boutique using `kubectl` and stores
    it in the variable `FRONTEND_ADDR`. It will be used by ansible in the following steps.
    3. Executes the ansible playbook `docker.yaml` that is responsible for installing
    docker on the VM.
    4. Executes the ansible playbook `loadgen.yaml` that is responsible for
    creating the docker container that runs the image `hamza13/loadgen2` that we
    built earlier. This is done using the [`docker_container`](https://docs.ansible.com/ansible/2.9/modules/docker_container_module.html)
    ansible module.

After the execution of the script finishes, we can ssh into the VM and fetch the
logs of the running Locust container:
```bash
ssh -i ./gcp gcp@$(terraform output -raw locust_ip) \
    "docker logs $(docker ps | grep "hamza13/loadgen2" | awk '{ print $1 }')"
```

NB: The file `./gcp` is the private key that was generated by `main.sh`, it was
associated to the user `gcp` on the created VM. It is *not* committed into source control.

After we're done using the load generator, we can destroy it, as well as all the
other cloud resources we created using terraform, by executing the following command:
```bash
terraform destroy -auto-approve
```

## Advanced steps

### Monitoring the application and the infrastructure

### Performance evaluation

This part is an extension of the part [Deploying automatically the load generator in Google cloud](###Deploying-automatically-the-load-generator-in-Google-cloud).
That's why we will be keeping the same provisionning and configuration strategy,
with some added improvements.

The strategy we followed in order to evaluate the performances of the Online boutique
application is centered around the following key points:
- The load generator is deployed outside the GKE cluster where the application
runs, but in the same GCP zone, meaning in the same datacenter. This allows us
to decouple the load generator's metrics of the varying state of the network as
much as possible.
- Similarly to what we did in the section [Deploying automatically the load generator in Google cloud](###Deploying-automatically-the-load-generator-in-Google-cloud),
we automated the whole process (with some minor details that should still be done manually and that we will discuss later)
using bash scripts.
- The load generator is deployed in a distributed manner, as described in the
[Locust documentation](https://docs.locust.io/en/stable/running-distributed.html).
A cluster of Locust nodes is formed by creating a Locust master node (the master
is created by launching the `locust` CLI with the `--master` flag) and, in our
case, 2 Locust workers (created with the `--worker` flag). The number of workers
can be changed easily by adjusting the value of the terraform variable `worker_no`
(TODO: insert link to the variable).
- Separate playbooks are created for the Locust master node and for the workers,
since they require different configurations that go beyond the flags passed to
the `locust` CLI throught the docker container.
- In addition to the Locust container,the master node hosts a custom container that we implemented, and that
takes the csv statistics files generated by the locust container and uploads
them to a Google storage Bucket. The code for this container can be found in
the file `./performance/statshandler/`.

NB: While researching this subject, we found an alternative way of handling the
deployment of a distributed Locust load generator that can be done in Kubernetes
using the [Locust operator](https://abdelrhmanhamouda.github.io/locust-k8s-operator/).
However, since the load generator should be deployed outside of the application
GKE cluster, we will need a separate GKE cluster for it, which will introduce a
significantely higher cloud cost when compared to working with GCE VMs directly.

In the following sections, we explain in more detail the main implementation choices
we made for each of these key points.

#### Launching the Load generator

This can be done by executing the following command:
```bash
bash ./main.sh
```
This will trigger the provisionning of the cloud resources by Terraform and then
the execution of the ansible playbooks necessary to configure the VMs.

The resources can be destroyed simply by executing the following command:

```bash
terraform destroy -auto-approve
```

#### Infrastructure as Code

TODO: make a diagram to simplify this

The infrastructure needed to run the performance evaluation
is provisionned using Terraform. The cloud resources we created are described in
the file `simple_deployment.tf` (TODO: insert link to this file). The main ones are:
- A google compute instance representing the Locust master.
- 2 google compute instances representing each one of the workers. This number can
be customized simply by changing the value of the terraform variable `worker_no`.
- A google compute instance representing a bastion host, that allows us to ssh into the
other VMs (master and workers) throught the private network. We chose to use a bastion
in order to avoid having to assign public IPs to the other VMs because that might
lead to us consuming all the quota of public IPs that can be given to us by GCP
(this will not be the case in we stick to using only 2 Locust workers, but it
allows greater flexibility overall). We are aware that other methods of connecting
with ssh to machines with private IP only (such as [CLoud IAP](https://cloud.google.com/iap?hl=en))
but these can be very platform dependant (specific to the cloud provider) and can
introduce their own bugs to the system.
- A firewall allowing external ssh connectivity, and another one allowing all
communication internally (in the network).


After the provisionning of these resources, the following ansible playbooks are
uploaded to the bastion host (using the `scp` CLI tool) and are executed (in
this order):
1. `docker.yaml` which runs against all the hosts (except except the bastion)
and installs docker on each one of them.
2. `locust_master.yaml` which runs against the master host, and starts the containers:
    - `hamza13/loadgen2` which gets the `--master` flag, in addition to other
    flags to enable customizing the host that is benchmarked (We pass the IP address
    of the `frontend-external` service here), and
    - `hamza13/statshandlerhamza13` which is reponsible of periodically uploading the csv
    files generated by Locust into a Google Storage bucket for easy access.
3. `locust_worker.yaml` which runs against the worker hosts and starts on each
one of them a container of this image `hamza13/loadgen2` by passing to it a
Locust command with the flag `--worker` and a host flag containing the private IP
of the master node (which was hardcoded in our case to `10.0.0.10`).


#### Graphs of the Locust results

According to the [Locust documentation](https://docs.locust.io/en/stable/configuration.html)
we can pass the flag `--html` to instruct it to generate an HTML report containing
aggregated statistics about the host we are benchmarking  in the form of graphs.

Working with this functionalityproved to be difficult since it wasn't reliable
at all (restarting the containers, for example, causes the report to not be updated
anymore). We suspect that this is due to [some bugs](https://github.com/locustio/locust/issues/1693) that were reported as issues
on the Locust Github repository and that are still not solved (the linked issue
appears to be closed but that's only because it was marked as stale automatically).

As a workaround, we used a separately maintained Github projet called [Locust reporter](https://github.com/benc-uk/locust-reporter)
that generates graphs and aggregates Locust data using only the csv file generated
by Locust (we had no problem in generating and recovering them).

TODO: insert graphs here

### Canary releases

To impelement the tasks requested for this part, we chose to only use core
Kubernetes components, meaning that we didn't use any service mesh implementation.
This choice was motivated by the fact that we didn't see any real added value
in using a service mesh like Istio in this case. We did, however,
identify some situations where the usage of a service mesh would greatly simply the
canary releases. We will briefly discuss these situations at the end of this section.

#### Creating a new version of a microservice

The microservice we chose to work with is the `productcatalogservice` where we
made a simple change to the `products.json` file (TODO: insert link to old file).
We simply changed the name of the product with ID `OLJCESPC7Z` from `Sunglasses`
to `SunglassesV2`.

This new version was built and pushed to [DockerHub](https://hub.docker.com/repository/docker/hamza13/productcatalogservice/general)
with image name `hamza13/productcatalogservice:v2.1`.

We then changed the Kubernetes manifest to include the following:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: productcatalogservice-v2
  labels:
    app: productcatalogservice
spec:
  selector:
    matchLabels:
      app: productcatalogservice
  template:
    metadata:
      labels:
        app: productcatalogservice
    spec:
      serviceAccountName: default
      terminationGracePeriodSeconds: 5
      securityContext:
        fsGroup: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        runAsUser: 1000
      containers:
      - name: server
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - ALL
          privileged: false
          readOnlyRootFilesystem: true
        image: hamza13/productcatalogservice:v2.1
        imagePullPolicy: Always
        ports:
        - containerPort: 3550
        env:
        - name: PORT
          value: "3550"
        - name: DISABLE_PROFILER
          value: "1"
        readinessProbe:
          grpc:
            port: 3550
        livenessProbe:
          grpc:
            port: 3550
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
```

This represents a new deployment that uses the new version of `productcatalogservice`.
The most important point here is that this deployment should have the same label
that is used as a selector by the kubernetes service `productcatalogservice` which is `app: productcatalogservice`.
This will ensure that pods of both the old and new deployment of this microservice
will be registered as endpoints of the kubernetes service, making it possible to
distribute the traffic between the 2 versions.

As for the requirement concerning the percentage of the traffic hitting each version,
we decided to control by changing the numbers of replicas that each version has.
So to route 25% of the traffic to v2, we had to create 3 replicas of version 1,
and 1 replica of version 2.

In order to check if we're accessing the first or the second version throught the
frontend we need to fetch the HTML of the page `/product/OLJCESPC7Z` and check if the
product's name is `Sunglasses` or `SunglassesV2`.

We wrote the bash script `./canary/canary_test.sh` that does this automatically
and counts the number as well as the percentage of responses it gets from each version.

You can test the script by executing the following command:

```bash
bash ./canary/canary_test.sh http://$FRONTEND_ADDR/product/OLJCESPC7Z 2000
```

This script accepts 2 arguments, the URL it will send requests to, and the number
of requests to send. As expected, when executing this script we got results that were very close to the
25/75 distribution we were aiming for.

In order to fully switch to the new version after validating that it works, we
can use the following command to execute a script that sets the replicas of the
first version to 0, effectively redirecting all the traffic to the new version.
This does not seem to distrupt in-flight requests as we didn't notice any failed
requests when executing the script `./canary/canary_test.sh` and switching in the
same time. This is due to [the fact that](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination)
before pod deletion, a `SIGTERM` signal is sent to the container and a grace
period is allowed for that container to respond to that signal and terminate gracefully.

```bash
bash ./canary/canary_switch.sh
```

##### NB

The results obtained in this part are not reproducible on a GKE created without
the `NetworkPolicy` addon, this is why the command we gave in the [first section](###Deploying-the-original-application-in-GKE)
to create the cluster has the flag `--enable-network-policy`.

When the cluster is created without that flag, the kubernetes service `productcatalogservice`
does not seem to be able to load balance traffic between pods from different
deployments, but only to one deplyment at a time (if you create deployment for
v1 and then for v2, the service will only forward traffic to v1, and only when deployment v1
is deleted does the service start forwarding traffic to deployment v2).

##### When to use a service mesh

As we just described, it is possible to implement canary releases using only
core Kubernetes resources, but this can be limiting because it doesn't permit a
great degree of customization when it comes to the percentage split we want to
achieve. Take for example the case where we want to route only 1% of the traffic
to the new version, then we would have to create 99 pods of version 1, and one
pod of version 2, which can potantially lead to a high resource usage and a relatively
expensive cloud bill. This can be solved efficiently by using a service mesh
like Istio where traffic is controlled by envoy proxies that forward the traffic
according the the rules defined by the user.

Another situation where it can be useful to use a service mesh is if we wanted
to enable autoscaling for the `productcatalogservice` deployments. In this case
it wouldn't be possible to control the traffic percentage split because the
number of pods of each deployment will be constantly changing according to the
metric we use for autoscaling. Istio avoids this problem as it doesn't rely on
the number of pods to enforce its traffic rules.

## Bonus steps

### Performance evaluation bonus

TODO: rerun tests and verify results

We ran the same performance evaluation procedure that we described in the section
[Performance evaluation](###Performance-evaluation) on the same load generation
infrastructure we were working with before, a master and 2 workers of size `f1-micro`
using the following configuration:
- 500 users
- spawn rate of 5 users/second
This produced the following graph where we focus on the average response time of
the application for requests sent to the endpoint `/` with respect to the number of
users:

TODO: add graph here

TODO: add explanation here

We reran the load generation with a bigger number of users:
- 750 users
- spawn rate of 5

This produced the following graph that focuses on the same parameters as the previous
one.

(TODO: add graph here)

This graph shows that the application struggles to keep up with the growing
number of users since the average response time getting slower. This shows us
that the and/or the infrastructure are saturated and may have a bottlneck.

In order to identify this bottlneck we decided to take a look at the dashboard
(TODO: add name of the dashboard) that shows the percentages of utilisation of
the CPU requests and limits of each one of the pods we deployed on GKE. We noticed
that the `currencyservice` uses 95% of its CPU limits, meaning that it consumed
all of its CPU requests and it's bottlnecked by the hard limit of CPU, and that
the `frontend` pod usesaround 98% of its CPU requests, so it can also present an
important bottlneck.

We also noticed, during the execution of the load generation, that the RAM usage
of the pod `currencyservice` gets exceptionally high over time to the point where
it fails with the error `OOMKILLED` which stands for Out Of Memory, suggesting that
it was killed due to the high memory usage we noticed.

### Managing a storage backend for logging orders

In this part, we created a new microservice called `Orderlog`. The code of this
microservice is located at `./orderlog/`. It is implemented using the Go programming
language and grpc with protocol buffers. Its goal is to save received order log messages
into a persistant database.

The database we chose for this is Postgresql deployed on the same GKE cluster as
the rest of the Online Boutique application, using the [Cloudnative-pg operator](https://cloudnative-pg.io/).
This operator greatly simplifies and streamlines the process of deployment of
Postgres while taking into account performance, resiliancy and disaster recovery.

We will begin by deploying Postgresql on GKE as it is the foundation of the `Orderlog`
microservice, and to do that we apply the following steps:
1. Start by creating a new storage class on GKE using the following manifest:
```yaml
allowVolumeExpansion: true
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  annotations:
    components.gke.io/component-name: pdcsi
    components.gke.io/component-version: 0.16.14
    components.gke.io/layer: addon
    storageclass.kubernetes.io/is-default-class: "true"
  labels:
    addonmanager.kubernetes.io/mode: EnsureExists
    k8s-app: gcp-compute-persistent-disk-csi-driver
  name: retain-storage-class
  resourceVersion: "757"
parameters:
  type: pd-balanced
provisioner: pd.csi.storage.gke.io
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```
This manifest is exactly similar to the one used to create the default storage
class in GKE, with the exception of the `reclaimPolicy` which we changed from `Delete`
(which deletes the persistant volume when the corresponding persistant volume claim
is deleted), to `Retain` (which retains the persistant volume unless manually deleted).
This storage class is set as the default in the cluster we are using.

This will help prevent any loss of data by accidentally deleting a persistant
volume claim, and will also make it possible to recover the latest data that was
written into Postgres in case of a major disaster, although than can be more challenging
compared to the strategies of data snapshotting and recovery that we discuss later.

2. We create the Google storage bucket where we will store snapshots of the database.
```bash
export BUCKET_NAME=persistancy
gcloud storage buckets create gs://$BUCKET_NAME
```

3. And we create a service account that has suffisant rights to list, create, modify
and delete objects from that GCS bucket:
```bash
export SERVICE_ACCOUNT=persistancy
export PROJECT_ID=xxxxxxxxxxxxx
gcloud iam service-accounts create $SERVICE_ACCOUNT
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:$SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com \
    --role roles/storage.admin
gcloud iam service-accounts keys create ./$SERVICE_ACCOUNT.json \
    --iam-account $SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com
```
This will save the service accounts key in a JSON file that should **not** be
committed into source control. We will use it to create a Kubernetes secret that
will be used by Cloudnative-pg to store spanshots in GCS:
```bash
kubectl create secret generic backup-creds --from-file=gcsCredentials=./$SERVICE_ACCOUNT.json
```

4. We then deploy `Cloudnative-pg` on the cluster using the `kubectl`:
```bash
kubectl apply -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.21/releases/cnpg-1.21.1.yaml
```

5. We are now ready to create the Postgresql cluster, by applying the
manifest `./pgcluster.yaml`. It describes the secret used to store the username
and password we use to connect to Postgresql (we are aware that this secret is
not encrypted and should not be committed into source control, but we chose to
do it this way for the sake of simplicity) and the Postgresql cluster itself in which
we defined the number of instances of the Postgresql cluster and the backup
strategy we're using (GCE bucket).

6. Finally, we need to configure scheduled automatic backups for this cluster by
applying the manifest `./backup_auto.yaml` that will backup the Postgres data to
the Google storage bucket every day at midnight.

Now that the postgresql cluster is ready to be used, we will implement the Orderlog
microservice.

1. We start by defining the protocol buffers contract in the `./orderlog/log/log.proto` file.
The main element it contains is the declaration of the remote procedure `Log` we are implementing:
```proto
service Logger {
    rpc Log (Entry) returns (Reply) {}
}
```
2. Then, we need to generate the corresponding Go code that defines the structs
we will be using to implement the Orderlog server. This can be done using the `protoc`
CLI tool:
```bash
protoc --go_out=. \
    --go_opt=paths=source_relative  \
    --go-grpc_out=. \
    --go-grpc_opt=paths=source_relative \
    ./log/log.proto
```
This command needs to be executed from the root of the Orderlog microservice code,
`./orderlog/`.

3. The server implementation, written in the file `./orderlog/log_server/main.go`, uses the `database/sql` module to communicate with
the Postgres database we deployed previously. It contains 3 main functions:
    - `func init()` is the first function that is called and its role is to initialize the connection
    and check if the `log` database and the `logs` table exist (and create them if not).
    - `func (s *server) Log(ctx context.Context, in *pb.Entry) (*pb.Reply, error)` represents
    the implementation of the `Log` remote procedure we declared in `./orderlog/log/log.proto`.
    It writes the entry that was passed to it as a parameter in the `logs` table.
    - `func main()` is the main function of this microservice. It initializes the grpc
    server and binds it to the port 50051.

4. A Dockerfile inspired by the Dockerfiles of the Go microservices of the Online Boutique
repository is also used to create a container image that's [pushed to Dockerhub](https://hub.docker.com/repository/docker/hamza13/orderlog/general)
under the name `hamza13/orderlog`

5. The Kubernetes manifest used to deploy this microservice is added to the file
`./minimal-manifest.yaml`. We used a Kubernetes deployment and a service to expose
it to the rest of the microservices.

6. The code of the `checkoutservice` was adapted to call the `Log` procedure of
the `Orderlog` microservice over grpc and its docker image was rebuilt and [pushed
to Dockerhub](https://hub.docker.com/repository/docker/hamza13/checkoutservice/general)
under the name `hamza13/checkoutservice`. This new implementation is included in this
repository under the folder `./checkoutservice/`. The main changes we made were:
    - Adding the `log.proto` file and generating corresponding Go code using it (just like
    we did for the `Orderlog` implementation in step 2)
    - Calling the `Log` procedure in the end of the `PlaceOrder` function.

TODO: copy checkoutservice folder to this repo

After deploying the new `Orderlog` and `Checkoutservice` implementation and passing
some orders on the frontend, we can log into the database and look at the records by
following these steps:
1. Start a terminal session inside one of the pods of the Postgresql cluster:
```bash
kubectl exec -it cluster-example-2-1 -- /bin/sh
```

2. Connect to the Potgres database
```bash
psql
```

3. Use the `Log` database
```bash
\c log
```

4. Select all entries from the `logs` table
```sql
SELECT * FROM logs;
```

In case of a major disaster impacting the GKE cluster we deployed the Postgresql
database on, we can recreate a new GKE cluster and a new Postgresql cluster on it
by using the manifest `./pgclusterrestored.yaml` which uses the backups we configured
to run periodically on Google Cloud Storage buckets. However, we will not be able
to recover data that was written into the old database after the last backup was made.
This problem can be remediated by scheduling backups on a more frequent schedule
(twice a day, or every hour) according to our use case and the tolerations we have
regarding performance and data integrity.


### Deploying your own Kubernetes infrastructure


