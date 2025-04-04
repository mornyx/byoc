#!/usr/bin/env bash

set -euo pipefail

while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --tidb-name)
            TIDB_NAME="$2"
            shift 2
            ;;
        --o11y-cluster-id)
            O11Y_CLUSTER_ID="$2"
            shift 2
            ;;
        --private-link-dns-name)
            PRIVATE_LINK_DNS_NAME="$2"
            shift 2
            ;;
        --role-arn)
            ROLE_ARN="$2"
            shift 2
            ;;
        --o11y-role-arn)
            O11Y_ROLE_ARN="$2"
            shift 2
            ;;
        --tenant-id)
            TENANT_ID="$2"
            shift 2
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --cluster-id)
            CLUSTER_ID="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "${REGION:-}" || -z "${NAMESPACE:-}" || -z "${TIDB_NAME:-}" || -z "${O11Y_CLUSTER_ID:-}" || -z "${PRIVATE_LINK_DNS_NAME:-}" || -z "${ROLE_ARN:-}" || -z "${O11Y_ROLE_ARN:-}" || -z "${TENANT_ID:-}" || -z "${PROJECT_ID:-}" || -z "${CLUSTER_ID:-}" ]]; then
    echo "Error: All parameters must be specified."
    echo "Usage: $0 --region <value> --namespace <value> --tidb-name <value> --o11y-cluster-id <value> --private-link-dns-name <value> --role-arn <value> --o11y-role-arn <value> --tenant-id <value> --project-id <value> --cluster-id <value>"
    exit 1
fi

echo "Creating namespace if not exists..."
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    kubectl create namespace "${NAMESPACE}"
    echo "Namespace ${NAMESPACE} created."
fi

echo "Adding helm repositories if not exist..."
if ! helm repo list | grep -q 'https://victoriametrics.github.io/helm-charts'; then
    helm repo add vm https://victoriametrics.github.io/helm-charts
fi
if ! helm repo list | grep -q 'https://helm.vector.dev'; then
    helm repo add vector https://helm.vector.dev
fi
helm repo update

echo "Installing or upgrading operator..."
helm show values vm/victoria-metrics-operator > /tmp/vmoperator-values.yaml
helm upgrade --install -n ${NAMESPACE} vmoperator vm/victoria-metrics-operator -f /tmp/vmoperator-values.yaml

echo "Checking operator pods..."
while true; do
    ready_pods=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=victoria-metrics-operator -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep -c true || true)
    total_pods=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=victoria-metrics-operator --no-headers 2>/dev/null | wc -l || true)
    
    if [[ "${ready_pods}" -eq "${total_pods}" && "${total_pods}" -gt 0 ]]; then
        echo "All vmoperator pods are ready."
        break
    else
        echo "Waiting for vmoperator pods to be ready..."
        sleep 5
    fi
done

echo "Installing or upgrading metrics agent..."
curl -o /tmp/vmpodscrape.yaml https://raw.githubusercontent.com/mornyx/byoc/refs/heads/main/vmpodscrape.tmpl.yaml
sed -i '' "s|\${NAMESPACE}|${NAMESPACE}|g" /tmp/vmpodscrape.yaml
sed -i '' "s|\${TIDB_NAME}|${TIDB_NAME}|g" /tmp/vmpodscrape.yaml
curl -o /tmp/vmagent.yaml https://raw.githubusercontent.com/mornyx/byoc/refs/heads/main/vmagent.tmpl.yaml
sed -i '' "s|\${NAMESPACE}|${NAMESPACE}|g" /tmp/vmagent.yaml
sed -i '' "s|\${O11Y_CLUSTER_ID}|${O11Y_CLUSTER_ID}|g" /tmp/vmagent.yaml
sed -i '' "s|\${PRIVATE_LINK_DNS_NAME}|${PRIVATE_LINK_DNS_NAME}|g" /tmp/vmagent.yaml
kubectl -n ${NAMESPACE} apply -f /tmp/vmpodscrape.yaml
kubectl -n ${NAMESPACE} apply -f /tmp/vmagent.yaml

echo "Installing or upgrading logs agent..."
curl -o /tmp/vector-k8s.yaml https://raw.githubusercontent.com/mornyx/byoc/refs/heads/main/vector-k8s.tmpl.yaml
sed -i '' "s|\${REGION}|${REGION}|g" /tmp/vector-k8s.yaml
sed -i '' "s|\${ROLE_ARN}|${ROLE_ARN}|g" /tmp/vector-k8s.yaml
sed -i '' "s|\${O11Y_ROLE_ARN}|${O11Y_ROLE_ARN}|g" /tmp/vector-k8s.yaml
sed -i '' "s|\${TENANT_ID}|${TENANT_ID}|g" /tmp/vector-k8s.yaml
sed -i '' "s|\${PROJECT_ID}|${PROJECT_ID}|g" /tmp/vector-k8s.yaml
sed -i '' "s|\${CLUSTER_ID}|${CLUSTER_ID}|g" /tmp/vector-k8s.yaml
sed -i '' "s|\${PRIVATE_LINK_DNS_NAME}|${PRIVATE_LINK_DNS_NAME}|g" /tmp/vector-k8s.yaml
helm upgrade --install -n ${NAMESPACE} vector-k8s vector/vector -f /tmp/vector-k8s.yaml

echo "Installing or upgrading diagnstic agent..."
curl -o /tmp/vector-tidb.yaml https://raw.githubusercontent.com/mornyx/byoc/refs/heads/main/vector-tidb.tmpl.yaml
sed -i '' "s|\${REGION}|${REGION}|g" /tmp/vector-tidb.yaml
sed -i '' "s|\${TIDB_NAME}|${TIDB_NAME}|g" /tmp/vector-tidb.yaml
sed -i '' "s|\${ROLE_ARN}|${ROLE_ARN}|g" /tmp/vector-tidb.yaml
sed -i '' "s|\${O11Y_ROLE_ARN}|${O11Y_ROLE_ARN}|g" /tmp/vector-tidb.yaml
sed -i '' "s|\${TENANT_ID}|${TENANT_ID}|g" /tmp/vector-tidb.yaml
sed -i '' "s|\${PROJECT_ID}|${PROJECT_ID}|g" /tmp/vector-tidb.yaml
sed -i '' "s|\${CLUSTER_ID}|${CLUSTER_ID}|g" /tmp/vector-tidb.yaml
sed -i '' "s|\${O11Y_CLUSTER_ID}|${O11Y_CLUSTER_ID}|g" /tmp/vector-tidb.yaml
sed -i '' "s|\${PRIVATE_LINK_DNS_NAME}|${PRIVATE_LINK_DNS_NAME}|g" /tmp/vector-tidb.yaml
helm upgrade --install -n ${NAMESPACE} vector-tidb vector/vector -f /tmp/vector-tidb.yaml

echo "Waiting for vmagent deployment pods to be ready..."
while true; do
    ready_pods=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=vmagent -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep -o true | wc -l || true)
    total_pods=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=vmagent --no-headers 2>/dev/null | wc -l || true)
    total_pods=$((total_pods * 2))
    if [[ "${ready_pods}" -eq "${total_pods}" && "${total_pods}" -gt 0 ]]; then
        echo "All vmagent deployment pods are ready."
        break
    else
        echo "Waiting for vmagent deployment pods to be ready... (${ready_pods}/${total_pods})"
        sleep 5
    fi
done

echo "Waiting for vector-k8s daemonset pods to be ready..."
while true; do
    ready_pods=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=vector-k8s -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep -o true | wc -l || true)
    total_pods=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=vector-k8s --no-headers 2>/dev/null | wc -l || true)
    if [[ "${ready_pods}" -eq "${total_pods}" && "${total_pods}" -gt 0 ]]; then
        echo "All vector-k8s daemonset pods are ready."
        break
    else
        echo "Waiting for vector-k8s daemonset pods to be ready... (${ready_pods}/${total_pods})"
        sleep 5
    fi
done

echo "Waiting for vector-tidb deployment pods to be ready..."
while true; do
    ready_pods=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=vector-tidb -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep -o true | wc -l || true)
    total_pods=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/instance=vector-tidb --no-headers 2>/dev/null | wc -l || true)
    if [[ "${ready_pods}" -eq "${total_pods}" && "${total_pods}" -gt 0 ]]; then
        echo "All vector-tidb deployment pods are ready."
        break
    else
        echo "Waiting for vector-tidb deployment pods to be ready... (${ready_pods}/${total_pods})"
        sleep 5
    fi
done

echo "All done."
