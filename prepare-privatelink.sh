#!/usr/bin/env bash

set -euo pipefail

while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --endpoint-name)
            ENDPOINT_NAME="$2"
            shift 2
            ;;
        --subnet-ids)
            SUBNET_IDS="$2"
            shift 2
            ;;
        --security-group-ids)
            SECURITY_GROUP_IDS="$2"
            shift 2
            ;;
        --service-name)
            SERVICE_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "${CLUSTER_NAME:-}" || -z "${ENDPOINT_NAME:-}" || -z "${SUBNET_IDS:-}" || -z "${SECURITY_GROUP_IDS:-}" || -z "${SERVICE_NAME:-}" ]]; then
    echo "Error: Missing required parameters."
    echo "Usage: $0 --cluster-name <cluster-name> --endpoint-name <endpoint-name> --subnet-ids <subnet-ids> --security-group-ids <security-group-ids> --service-name <service-name>"
    exit 1
fi

VPC_ID=$(aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

set +e
aws ec2 create-vpc-endpoint \
    --vpc-id "${VPC_ID}" \
    --vpc-endpoint-type Interface \
    --service-name "${SERVICE_NAME}" \
    --subnet-ids "${SUBNET_IDS}" \
    --security-group-ids "${SECURITY_GROUP_IDS}" \
    --private-dns-enabled \
    --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${ENDPOINT_NAME}}]"
set -e

echo "Waiting for the VPC endpoint to become available..."
while true; do
    STATUS=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=service-name,Values=${SERVICE_NAME}" \
        --query "VpcEndpoints[0].State" \
        --output text)
    if [[ "${STATUS}" == "available" ]]; then
        echo "The VPC endpoint is now available."
        break
    elif [[ "${STATUS}" == "pending" ]]; then
        echo "The VPC endpoint is still pending. Waiting..."
        sleep 10
    else
        echo "The VPC endpoint is in an unexpected state: ${STATUS}"
        exit 1
    fi
done
