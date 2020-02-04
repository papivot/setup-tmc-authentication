# Setting up cluster authentication for attached clusters in TMC

  - [Prequisites](#prequisites)
  - [Stage 1 - Generate the webhook config file.](#stage-1---generate-the-webhook-config-file)
  - [Stage 2 - Create a context in the kubeconfig file.](#stage-2---create-a-context-in-the-kubeconfig-file)
  - [Stage 3 - Update the apiserver configuration.](#stage-3---update-the-apiserver-configuration)

This a three stage process that is described here. While stages 1 and 2 can be automated, the stage 3 is specific to the type of K8s cluster and depends on how you can access the contol plane nodes to modify files. 

The sample provided with this repo works for a cluster that has been deployed using Cluster API in AWS, where the nodes can be acessed using SSH via the bastion host (that gets deployed thru the cluster API). You can modify the config file as per your reqirements. 

## Prequisites 

* A Kubernetes cluster that has been attached to TMC. This is different from a provisioned cluster that was deployed thru TMC. The attached cluster can be a DIY, PKS Ess, PKS Ent (caution) etc, where you have access to the control plane of the cluster. 
  
  Note - you can attach the cluster to TMC using the command similar to this - 
  ```command
  tmc cluster attach -k ${KUBECONFIG_FILE} -n ${CLUSTER_NAME} -g ${TMC_CLUSTER_GROUP}
  ```
* A bastion host - preferably a linux or a MacOS system.
* tmc cli with working access to TMC console. 
* Kubeconfig file to access the above cluster.

## Stage 1 - Generate the webhook config file.

This stage generates the `webhook-config.yaml` file as per the recommendations found [here](https://kubernetes.io/docs/reference/access-authn-authz/webhook/). Since format of the configuration files is similar to the kubeconfig file, we can leverage `kubectl config` commands to generate this file.

## Stage 2 - Create a context in the kubeconfig file.

This step generates the required context in the kubeconfig file to connect to the cluster. 
This uses the `kubectl config set-credentials` option to set the required credentials for the context to use. 

## Stage 3 - Update the apiserver configuration. 

The way to implement this stage will depend on the cluster and the level of access the user has to modify the files and apiserver configurations. 

* The webhook configuration file, generated in stage 1, is copied to the `/etc/kubernetes/token-webhook-authentication` or similar folder (depending on the K8s distribution type)
* The apiserver configuration file is modifed to reference the above file as well as enable webhook authentication. This includes adding the following lines to the apiserver command line options -

```console
    --authentication-token-webhook-cache-ttl=5m0s
    --authentication-token-webhook-config-file=/etc/kubernetes/token-webhook-authentication/webhook-config.yaml'
```
If your apiserver runs as a pod, then the above drectory would have to be references as a volume mount. This could be achived by add the following entries in the appropriate location - 

```yaml
   - mountPath: /etc/kubernetes/token-webhook-authentication/
        name: token-webhook-authentication
        readOnly: true
```

and 

```yaml
  - hostPath:
        path: /etc/kubernetes/token-webhook-authentication/
        type: Directory
            name: token-webhook-authentication
```

Depending on your distribution, you may require a restart of the apiserver. 

Once the apiserver is restarted, you can use the new context, created at stage 2, to connect to the cluster. 

Note: Due to current tmc cli limitations, you my have to use a workstation with browser installed, to access the new cluster. 
