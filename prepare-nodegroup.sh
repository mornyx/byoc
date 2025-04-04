#!/usr/bin/env bash

set -euo pipefail

while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --nodegroup-name)
            NODEGROUP_NAME="$2"
            shift 2
            ;;
        --subnets)
            SUBNETS="$2"
            shift 2
            ;;
        --node-role)
            NODE_ROLE="$2"
            shift 2
            ;;
        --launch-template)
            LAUNCH_TEMPLATE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "${CLUSTER_NAME:-}" || -z "${NODEGROUP_NAME:-}" || -z "${SUBNETS:-}" || -z "${NODE_ROLE:-}" || -z "${LAUNCH_TEMPLATE:-}" ]]; then
    echo "Error: Missing required parameters."
    echo "Usage: $0 --cluster-name <cluster-name> --nodegroup-name <nodegroup-name> --subnets <subnets> --node-role <node-role> --launch-template <launch-template>"
    exit 1
fi

aws eks create-nodegroup \
    --cluster-name ${CLUSTER_NAME} \
    --nodegroup-name ${NODEGROUP_NAME} \
    --subnets ${SUBNETS} \
    --node-role ${NODE_ROLE} \
    --launch-template ${LAUNCH_TEMPLATE} \
    --scaling-config minSize=2,maxSize=3,desiredSize=2 \
    --labels dedicated=o11y,use-for=byoc-m1 \
    --taints key=dedicated,value=o11y,effect=NO_SCHEDULE key=use-for,value=byoc-m1,effect=NO_SCHEDULE

echo "Waiting for the nodegroup to become active..."
while true; do
    STATUS=$(aws eks describe-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name ${NODEGROUP_NAME} --query 'nodegroup.status' --output text)
    if [[ "$STATUS" == "ACTIVE" ]]; then
        echo "Nodegroup is now active."
        break
    fi
    echo "Current status: $STATUS. Waiting..."
    sleep 10
done
