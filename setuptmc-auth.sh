#!/bin/sh
CLUSTER_NAME="workload-cluster-aws-1"
KUBECONFIG_FILE="/tmp/${CLUSTER_NAME}.conf"

###################################
# Setup webhook-config server file
####################################
echo "Creating WEBHOOK-CONFIG SERVER FILE"
webhookdetails=`tmc cluster auth serverconfig get ${CLUSTER_NAME} -o json |jq -r '.status.authenticationWebhook'`
SERVER=`echo $webhookdetails|jq -r '.endpoint'`
echo $webhookdetails|jq -r '.certificateAuthorityData' |base64 -d > /tmp/tmc.pem
kubectl --kubeconfig=/tmp/webhook-config.yaml config set-cluster server --server=${SERVER}  --certificate-authority=/tmp/tmc.pem --embed-certs=true
kubectl --kubeconfig=/tmp/webhook-config.yaml config set-credentials apiserver
kubectl --kubeconfig=/tmp/webhook-config.yaml config set-context token-webhook-authentication --user=apiserver --cluster=server
kubectl --kubeconfig=/tmp/webhook-config.yaml config use-context token-webhook-authentication
rm /tmp/tmc.pem

##################################
# Setup the kubeconfig file
#################################
echo "Creating WEBHOOK KUBECONFIG SETTINGS"
userdetails=`tmc cluster auth userconfig get ${CLUSTER_NAME} -o json|jq -r '.status.user.exec'`
apiversion=`echo $userdetails| jq -r '.apiVersion'`
command=`echo $userdetails| jq -r '.command'`
kubectl --kubeconfig=${KUBECONFIG_FILE} config set-credentials tanzu --exec-command=${command} --exec-api-version=${apiversion}
args=`echo $userdetails| jq -r '.args|@csv'| tr -d \"`
kubectlargs=`echo $args | sed 's/,/ --exec-arg=/g' | sed 's/^/ --exec-arg=/g'`
kubectl --kubeconfig=${KUBECONFIG_FILE} config set-credentials tanzu $kubectlargs
for i in `echo $userdetails| jq -r '.env[] | [.name, .value]|@csv'|tr -d \"`
do
        key=`echo $i|cut -d, -f1`
        value=`echo $i|cut -d, -f2`
        kubectl --kubeconfig=${KUBECONFIG_FILE} config set-credentials tanzu --exec-env=${key}=${value}
done
kubectl --kubeconfig=${KUBECONFIG_FILE} config set-context tanzu --user tanzu --cluster=${CLUSTER_NAME}

#################################
# Push the changes to the CTRL PLANE. 
# Methods varies on type of cluster.
# This example assumes that the control
# plane servers are in a pvt network
# and can be connected thru a SSH tunnel 
# using a jump box. The control plane has been 
# bootstrapped using kubeadm
################################
echo "UPADTING CONTROL PLANE "
IFS=
bastion=`kubectl get awscluster/workload-cluster-aws-1 -o json|jq -r '.status.bastion.publicIp'`
controlplanes=`kubectl --kubeconfig=${KUBECONFIG_FILE} get nodes -l node-role.kubernetes.io/master --no-headers|awk '{print $1}'`
#### Check for multi node scenario
for controlplane in ${controlplanes}
do
	while read -r line
	do
		eval echo $line
	done < config > ~/.ssh/config
	echo Updating ${controlplane}
	#################################
	# COpy webhook config file
	#################################
	ssh ubuntu@${controlplane} sudo mkdir -p /etc/kubernetes/token-webhook-authentication
	scp /tmp/webhook-config.yaml ubuntu@${controlplane}:
	ssh ubuntu@${controlplane} sudo chown root:root webhook-config.yaml
	ssh ubuntu@${controlplane} sudo chmod 0600 webhook-config.yaml
	ssh ubuntu@${controlplane} sudo mv webhook-config.yaml /etc/kubernetes/token-webhook-authentication/webhook-config.yaml
	################################
	# Setup kube-apiserver config
	################################
	ssh ubuntu@${controlplane} sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml .
	ssh ubuntu@${controlplane} sudo cp kube-apiserver.yaml kube-apiserver.yaml.backup
	ssh ubuntu@${controlplane} sudo chmod 666 kube-apiserver.yaml
	scp ubuntu@${controlplane}:kube-apiserver.yaml .
	# Do local processing
	sed -i '/^    - --allow-privileged=true/a\    - --authentication-token-webhook-cache-ttl=5m0s\n    - --authentication-token-webhook-config-file=/etc/kubernetes/token-webhook-authentication/webhook-config.yaml' kube-apiserver.yaml
	sed -i '/^  hostNetwork: true/i\    - mountPath: /etc/kubernetes/token-webhook-authentication/\n      name: token-webhook-authentication\n      readOnly: true' kube-apiserver.yaml
	sed -i '/^status: {}/i\  - hostPath:\n      path: /etc/kubernetes/token-webhook-authentication/\n      type: Directory\n    name: token-webhook-authentication' kube-apiserver.yaml
	# Copy modified file back
	scp kube-apiserver.yaml ubuntu@${controlplane}:
	ssh ubuntu@${controlplane} sudo chmod 0600 kube-apiserver.yaml
	ssh ubuntu@${controlplane} sudo chown root:root kube-apiserver.yaml
	ssh ubuntu@${controlplane} sudo mv kube-apiserver.yaml /etc/kubernetes/manifests/
done
rm ~/.ssh/config
rm kube-apiserver.yaml
