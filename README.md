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

## Usage
kubectl ekslogs [FLAGS] <node> [node...]

### Flags

| Flag | Description | Default |
|------|-------------|---------|
| `-t`, `--timeout <duration>` | Timeout for log collection | `300s` |
| `-o`, `--output-dir <path>` | Directory to save log bundles | `.` (current directory) |
| `-h`, `--help` | Show help message | — |
| `-v`, `--version` | Show version information | — |

### Examples

**Collect logs from a single node:**
```bash
kubectl ekslogs ip-10-0-1-42.ec2.internal
```
**Collect logs from multiple nodes:**
```bash
kubectl ekslogs ip-10-0-1-42.ec2.internal ip-10-0-1-43.ec2.internal
```
**Collect logs with a custom timeout and output directory:**
```bash
kubectl ekslogs --timeout 600s --output-dir /tmp/logs ip-10-0-1-42.ec2.internal
```

**Collect logs from all nodes in a specific node group:**
```
kubectl ekslogs $(kubectl get nodes -l eks.amazonaws.com/nodegroup=my-node-group -o jsonpath='{.items[*].metadata.name}')
```
### Sample Output
```
⟳ Validating node(s)...
✔ All 2 node(s) found
⟳ Creating NodeDiagnostic resources...
⟳ Waiting for log collection to complete (timeout: 300s)...
✔ Log collection completed on all nodes
⟳ Downloading log bundles...
✔ Saved: ./ip-10-0-1-42.ec2.internal-logs.tar.gz (14M)
✔ Saved: ./ip-10-0-1-43.ec2.internal-logs.tar.gz (12M)

✔ Done — 2 log bundle(s) downloaded to ./
```
