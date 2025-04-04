#!/usr/bin/env bash

set -euo pipefail

while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --account-id)
            ACCOUNT_ID="$2"
            shift 2
            ;;
        --oidc-provider-id)
            OIDC_PROVIDER_ID="$2"
            shift 2
            ;;
        --role-name)
            ROLE_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "${REGION:-}" || -z "${ACCOUNT_ID:-}" || -z "${OIDC_PROVIDER_ID:-}" || -z "${ROLE_NAME:-}" || -z "${NAMESPACE:-}" ]]; then
    echo "Error: Missing required parameters."
    echo "Usage: $0 --region <region> --account-id <account-id> --oidc-provider-id <oidc-provider-id> --role-name <role-name> --namespace <namespace>"
    exit 1
fi

POLICY_DOCUMENT=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        },
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_PROVIDER_ID}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringLike": {
                    "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_PROVIDER_ID}:sub": "system:serviceaccount:${NAMESPACE}:*"
                }
            }
        }
    ]
}
EOF
)

aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$POLICY_DOCUMENT"
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"

echo "IAM Role 'arn:aws:iam::${ACCOUNT_ID}:${ROLE_NAME}' created successfully."
