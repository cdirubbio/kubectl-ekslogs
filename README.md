# kubectl-ekslogs

A kubectl plugin to collect diagnostic log bundles from Amazon EKS nodes using the [NodeDiagnostic](https://docs.aws.amazon.com/eks/latest/userguide/node-health.html) API.

## Overview

Troubleshooting EKS node issues often requires gathering system logs, kubelet output, and other diagnostic data from the underlying EC2 instance. `kubectl ekslogs` automates this workflow — it creates a `NodeDiagnostic` resource, waits for log collection to complete, and downloads the resulting tarball directly to your local machine. No SSH access or SSM sessions required. This plugin was made possible via a PR I made to the NMA repository (https://github.com/aws/eks-node-monitoring-agent/pull/58) which was released in version `v1.5.3`.

## Prerequisites

- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured with access to an EKS cluster
- The EKS NodeDiagnostic API (`eks.amazonaws.com/v1alpha1`) must be available on your cluster
- Sufficient RBAC permissions to create/delete `NodeDiagnostic` resources and access the node proxy API

## Installation

### Manual

Download the plugin and place it in your `PATH`:

```bash
curl -LO https://raw.githubusercontent.com/cdirubbio/kubectl-ekslogs/refs/heads/main/kubectl-ekslogs
chmod +x kubectl-ekslogs
sudo mv kubectl-ekslogs /usr/local/bin/
```
