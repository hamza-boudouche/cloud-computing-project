#!/bin/bash

kubectl patch deployments.apps/productcatalogservice-v2 -p '{"spec":{"replicas": 4}}'
kubectl patch deployments.apps/productcatalogservice-v1 -p '{"spec":{"replicas": 0}}'
