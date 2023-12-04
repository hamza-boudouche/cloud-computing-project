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

TODO: change cluster to regional instead of zonal

```bash
# the GCP project ID
export PROJECT_ID=xxxxxxxxxxxxx
# the type of the worker nodes
export M_TYPE=e2-standard-2
# the zone in which to create the cluster
export ZONE=

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
and were left with this YAML manifest. TODO: insert link to the minimal-yaml manifest.
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
we chose to [make some minor changes]() to the Dockerfile that's provided in the
[application repository](https://github.com/GoogleCloudPlatform/microservices-demo).
The main change we made was removing the `ENTRYPOINT` of the docker image,
because we wanted to customize the command that will be passed to the container
upon its creation. TODO: add link to the new dockerfile

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

### Deploying automatically the load generator in Google cloud:

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
