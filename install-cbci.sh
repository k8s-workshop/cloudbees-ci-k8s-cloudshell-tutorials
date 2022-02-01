#!/bin/bash
gcloud config set project "core-workshop"
gcloud container clusters create "degrasse-python" \
    --region "us-east1" \
    --node-locations "us-east1-b","us-east1-c" \
    --num-nodes=1 \
    --cluster-version "1.21.5-gke.1302" --release-channel "regular" \
    --machine-type "n1-standard-4" \
    --disk-type "pd-ssd" --disk-size "50" \
    --service-account "gke-nodes-for-workshop-testing@core-workshop.iam.gserviceaccount.com" \
    --enable-autoscaling --min-nodes "0" --max-nodes "4" \
    --autoscaling-profile optimize-utilization \
    --enable-dataplane-v2 \
    --workload-pool "core-workshop.svc.id.goog"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add cloudbees https://charts.cloudbees.com/public/cloudbees
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts

helm repo update

helm upgrade --install --wait ingress-nginx ingress-nginx/ingress-nginx \
    -n ingress-nginx --create-namespace

helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace \
  --version v1.5.4 \
  --set global.leaderElection.namespace=cert-manager  --set prometheus.enabled=false \
  --set installCRDs=true --wait

helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver --namespace kube-system

git clone https://github.com/GoogleCloudPlatform/secrets-store-csi-driver-provider-gcp.git
kubectl apply -f secrets-store-csi-driver-provider-gcp/deploy/provider-gcp-plugin.yaml

INGRESS_IP=$(kubectl get services -n ingress-nginx | grep LoadBalancer  | awk '{print $4}')
echo $INGRESS_IP

PROJECT_ID=core-workshop
DNS_ZONE=workshop-cb-sa
CBCI_HOSTNAME=degrasse-python.workshop.cb-sa.io

gcloud dns record-sets delete $CBCI_HOSTNAME. --type=A --zone=$DNS_ZONE

gcloud dns --project=$PROJECT_ID record-sets transaction start --zone=$DNS_ZONE
gcloud dns --project=$PROJECT_ID record-sets transaction add $INGRESS_IP --name=$CBCI_HOSTNAME. --ttl=300 --type=A --zone=$DNS_ZONE
gcloud dns --project=$PROJECT_ID record-sets transaction execute --zone=$DNS_ZONE

gcloud iam service-accounts add-iam-policy-binding core-cloud-run@core-workshop.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:core-workshop.svc.id.goog[cbci/cjoc]"

chmod +x kustomize-wrapper.sh

rm -f casc/oc/jenkins.yaml
mv casc/oc/jenkins.yaml.updated casc/oc/jenkins.yaml

CBCI_HOSTNAME=degrasse-python.workshop.cb-sa.io
helm upgrade --install --wait cbci cloudbees/cloudbees-core \
  --set OperationsCenter.HostName=$CBCI_HOSTNAME \
  --namespace='cbci'  --create-namespace \
  --set OperationsCenter.Ingress.tls.Host=$CBCI_HOSTNAME \
  --values ./helm/cbci-values.yml --post-renderer ./kustomize-wrapper.sh

kubectl cp --namespace cbci casc/base cjoc-0:/var/jenkins_home/jcasc-bundles-store/


