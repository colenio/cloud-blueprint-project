# Sealed Secrets

## Overview

For secret management in Kubernetes, we evaluated two primary approaches: **Sealed Secrets** and **External Secrets Operator (ESO)**.
This document outlines our decision-making process and recommendations.

## Solution Comparison

### Sealed Secrets

**What it is:** A Kubernetes controller that allows you to encrypt secrets using asymmetric cryptography, making them safe to store in Git repositories.

**How it works:**

1. Install sealed-secrets controller in cluster
2. Use `kubeseal` CLI to encrypt secrets locally
3. Commit encrypted SealedSecret manifests to Git
4. Controller automatically decrypts to regular Secrets in cluster

### External Secrets Operator (ESO)

**What it is:** A Kubernetes operator that integrates with external secret management systems (AWS Secrets Manager, Azure Key Vault, HashiCorp Vault, etc.)

**How it works:**

1. Install ESO controller in cluster
2. Configure SecretStore pointing to external system
3. Create ExternalSecret manifests referencing external secrets
4. Controller syncs secrets from external systems to cluster

## Pros and Cons Analysis

### Sealed Secrets

#### ✅ Pros

- **Simple setup**: Single controller, no external dependencies
- **Git-friendly**: Encrypted secrets can be safely committed to version control
- **No external services**: Self-contained within the cluster
- **Cost-effective**: No additional infrastructure or licensing costs
- **Quick implementation**: Perfect for PoC and rapid prototyping
- **Deterministic**: Same input always produces same encrypted output
- **Offline capable**: Works without internet connectivity during deployment

#### ❌ Cons

- **Key management burden**: Cluster-specific encryption keys
- **Re-sealing required**: Must re-encrypt all secrets when:
  - Reinstalling the controller
  - Moving to new cluster
  - Rotating encryption keys
- **Limited secret sources**: Only supports manual secret creation
- **No automatic rotation**: Secrets don't update automatically
- **Backup complexity**: Must backup both secrets and encryption keys
- **Single point of failure**: If controller key is lost, all secrets become unrecoverable

### External Secrets Operator (ESO)

#### ✅ Pros

- **Centralized secret management**: Single source of truth for all environments
- **Automatic rotation**: Secrets can be updated centrally and synced automatically
- **Multiple backends**: Supports AWS, Azure, GCP, Vault, and many others
- **Enterprise-grade**: Built for large-scale, multi-cluster deployments
- **Audit trails**: External systems provide comprehensive logging
- **Team collaboration**: Multiple teams can manage secrets independently
- **Disaster recovery**: Secrets survive cluster recreation

#### ❌ Cons

- **Complex setup**: Requires external secret management system
- **Additional costs**: External services (AWS Secrets Manager, etc.) have pricing
- **Network dependencies**: Requires connectivity to external services
- **Learning curve**: More complex configuration and troubleshooting
- **Vendor lock-in**: Tied to specific cloud provider secret services
- **Overkill for small projects**: High complexity-to-value ratio for simple use cases

## Scaling Considerations

### Starting Small (PoC Phase)

**Recommendation: Sealed Secrets**

For proof-of-concept and small projects:

- Minimal setup overhead
- Self-contained solution
- Easy to understand and debug
- No external service dependencies
- Cost-effective for small teams

### Scaling Up (Production/Enterprise)

**Consider Migration to ESO when:**

- **Multi-cluster deployments**: Managing secrets across multiple clusters
- **Team growth**: Multiple teams need independent secret management
- **Compliance requirements**: Need audit trails and centralized governance
- **Automatic rotation**: Secrets need regular rotation without manual intervention
- **Integration needs**: Already using cloud-native secret management services

## Migration Path

### Phase 1: Start with Sealed Secrets

```yaml
# Simple sealed secret for PoC
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-config
  namespace: security
spec:
  encryptedData:
    API_KEY: AgAR8t7/k2l3...
```

### Phase 2: Migrate to ESO (When Scaling)

```yaml
# External secret referencing Azure Key Vault
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-config
  namespace: security
spec:
  secretStoreRef:
    name: azure-keyvault
    kind: SecretStore
  target:
    name: my-config
  data:
    - secretKey: API_KEY
      remoteRef:
        key: my-api-key
```

## Key Management and Re-sealing

### Sealed Secrets Key Management

**Critical Considerations:**

- **Backup the master key**: Essential for disaster recovery
- **Key rotation strategy**: Plan for periodic key updates
- **Re-sealing process**: When controller is reinstalled:

```bash
# Backup existing key
kubectl get secret sealed-secrets-key -n kube-system -o yaml > sealed-secrets-key-backup.yaml

# After controller reinstall, restore key
kubectl apply -f sealed-secrets-key-backup.yaml

# Or re-seal all secrets with new key
kubeseal --controller-namespace=kube-system --controller-name=sealed-secrets < secret.yaml > sealed-secret.yaml
```

**Re-sealing Scenarios:**

1. **Controller reinstallation**: Must restore original key or re-seal all secrets
2. **Cluster migration**: Need to either migrate keys or re-seal for new cluster
3. **Key rotation**: Security best practice requires periodic re-sealing
4. **Key compromise**: Emergency re-sealing of all secrets required

## Advanced: Terraform-Managed Master Key

### Problem Solved

When using Infrastructure as Code (IaC) to manage AKS clusters, the sealed-secrets master key gets lost during cluster recreation, requiring re-sealing of all secrets.

### Solution: Terraform Key Management

By generating and storing the sealed-secrets master key in Terraform state, we can persist it across cluster lifecycle operations.

#### Terraform Configuration

```hcl
# Generate a consistent master key for sealed-secrets
resource "tls_private_key" "sealed_secrets_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create the master key secret that sealed-secrets controller expects
resource "kubernetes_secret" "sealed_secrets_key" {
  metadata {
    name      = "sealed-secrets-key${var.key_suffix}"
    namespace = "kube-system"
    labels = {
      "sealedsecrets.bitnami.com/sealed-secrets-key" = "active"
    }
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_private_key.sealed_secrets_key.public_key_pem
    "tls.key" = tls_private_key.sealed_secrets_key.private_key_pem
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Output the public key for sealing secrets
output "sealed_secrets_public_key" {
  description = "Public key for sealing secrets"
  value       = tls_private_key.sealed_secrets_key.public_key_pem
  sensitive   = false
}

# Store private key in Terraform state (encrypted at rest)
output "sealed_secrets_private_key" {
  description = "Private key for sealed-secrets controller"
  value       = tls_private_key.sealed_secrets_key.private_key_pem
  sensitive   = true
}
```

#### Key Suffix Strategy

```hcl
variable "key_suffix" {
  description = "Suffix for sealed-secrets key to allow rotation"
  type        = string
  default     = ""
}

# For key rotation, change the suffix
# terraform apply -var="key_suffix=-v2"
```

#### Install Sealed-Secrets Controller

```hcl
resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = "2.17.3"
  namespace  = "kube-system"  # Default namespace for sealed-secrets

  # Ensure our key is created before the controller starts
  depends_on = [kubernetes_secret.sealed_secrets_key]

  values = [
    yamlencode({
      # Prevent controller from generating its own key
      secretName = "sealed-secrets-key${var.key_suffix}"

      # Optional: Configure controller settings
      controller = {
        create = true
      }

      # Alternative: Install in different namespace
      # namespace = "sealed-secrets"  # Uncomment to use custom namespace
    })
  ]
}

# Alternative configuration for custom namespace
# resource "kubernetes_namespace" "sealed_secrets" {
#   metadata {
#     name = "sealed-secrets"
#   }
# }
#
# resource "helm_release" "sealed_secrets_custom_ns" {
#   name       = "sealed-secrets"
#   repository = "https://bitnami-labs.github.io/sealed-secrets"
#   chart      = "sealed-secrets"
#   version    = "2.17.3"
#   namespace  = kubernetes_namespace.sealed_secrets.metadata[0].name
#
#   depends_on = [kubernetes_secret.sealed_secrets_key_custom]
#
#   values = [
#     yamlencode({
#       secretName = "sealed-secrets-key${var.key_suffix}"
#       namespace = kubernetes_namespace.sealed_secrets.metadata[0].name
#     })
#   ]
# }
```

### Namespace Considerations

**Default Behavior:**

- Sealed-secrets controller installs in `kube-system` namespace by default
- Master key secret is expected in the same namespace as the controller
- Controller watches for SealedSecret resources cluster-wide

**Custom Namespace Option:**

```hcl
# If using custom namespace, both key and controller must be in same namespace
resource "kubernetes_secret" "sealed_secrets_key_custom" {
  metadata {
    name      = "sealed-secrets-key${var.key_suffix}"
    namespace = "sealed-secrets"  # Custom namespace
    labels = {
      "sealedsecrets.bitnami.com/sealed-secrets-key" = "active"
    }
  }
  # ... rest of configuration
}
```

**Security Implications:**

- `kube-system` namespace has elevated privileges
- Custom namespace provides better isolation
- Consider your cluster's security policies when choosing

### Usage Workflow

#### 1. Initial Setup

```bash
# Deploy cluster with sealed-secrets
terraform apply

# Extract public key for sealing
terraform output -raw sealed_secrets_public_key > public.pem

# Seal secrets using the Terraform-managed key
kubectl create secret generic my-config \
  --from-literal=API_KEY="secret-value" \
  --dry-run=client -o yaml | \
  kubeseal --cert=public.pem -o yaml > secret-sealed.yaml
```

#### 2. Cluster Recreation

```bash
# Destroy cluster
terraform destroy

# Recreate cluster - same key will be restored
terraform apply

# Existing sealed secrets still work!
kubectl apply -f secret-sealed.yaml
```

#### 3. Key Rotation

```bash
# Rotate to new key
terraform apply -var="key_suffix=-v2"

# Re-seal secrets with new key
kubeseal --cert=<(terraform output -raw sealed_secrets_public_key) \
  < original-secret.yaml > new-sealed-secret.yaml
```

### Benefits of This Approach

✅ **Persistent across cluster recreation**: Key survives infrastructure changes  
✅ **Version controlled**: Key generation is reproducible  
✅ **Automated**: No manual key management required  
✅ **Rotation support**: Can rotate keys systematically  
✅ **Terraform state encryption**: Private key protected at rest  
✅ **Team coordination**: Same key available to all team members

### Security Considerations

⚠️ **Terraform State Security**:

- Use remote state with encryption (Azure Storage, S3, etc.)
- Limit access to Terraform state
- Consider using Terraform Cloud/Enterprise for enhanced security

⚠️ **Key Access**:

- Public key can be shared safely
- Private key is sensitive - only in Terraform outputs
- Use `terraform output` with proper access controls

### Migration from Existing Sealed Secrets

```bash
# 1. Backup existing key from running cluster
kubectl get secret sealed-secrets-key -n kube-system -o yaml > backup-key.yaml

# 2. Extract the key material
PRIVATE_KEY=$(kubectl get secret sealed-secrets-key -n kube-system -o jsonpath='{.data.tls\.key}' | base64 -d)
PUBLIC_KEY=$(kubectl get secret sealed-secrets-key -n kube-system -o jsonpath='{.data.tls\.crt}' | base64 -d)

# 3. Import into Terraform (advanced - requires terraform import)
# Or re-seal all secrets with Terraform-generated key
```

This approach transforms sealed-secrets from a cluster-specific solution into an infrastructure-as-code managed component, solving the key persistence problem while maintaining the simplicity benefits over ESO.

## Recommendations

### For PoC Projects (Current State)

**Use Sealed Secrets because:**

- Minimal complexity for getting started
- No external service dependencies
- Cost-effective for small scope
- Easy to implement and maintain
- Perfect for demonstrating concepts

### For Production Scale-Up

**Migrate to ESO when you have:**

- Multiple environments/clusters
- Team size > 5 developers
- Compliance/audit requirements
- Need for automatic secret rotation
- Existing cloud secret management services

### Implementation Strategy

1. **Start**: Implement Sealed Secrets for immediate needs
2. **Monitor**: Track complexity and operational overhead
3. **Evaluate**: Assess when ESO benefits outweigh complexity
4. **Migrate**: Plan gradual migration when scaling requirements emerge

## Conclusion

For our current PoC project, **Sealed Secrets is the optimal choice** due to its simplicity and self-contained nature. However, we should plan for eventual migration to ESO as the project scales and operational requirements grow.

The key is to start simple and evolve the secret management strategy as the project matures, rather than over-engineering from the beginning.

### Installation Strategy: Terraform vs ArgoCD

**Key Decision:** Should sealed-secrets be installed by Terraform or managed by ArgoCD?

#### Option 1: Terraform Installation (Bootstrap Approach)

**When to use:**

- Sealed-secrets is **foundational infrastructure**
- Need secrets **before ArgoCD** is fully operational
- Want **tight coupling** with cluster lifecycle

```hcl
# Terraform manages sealed-secrets as part of cluster bootstrap
resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = "2.17.3"
  namespace  = "kube-system"

  depends_on = [kubernetes_secret.sealed_secrets_key]

  values = [yamlencode({
    secretName = "sealed-secrets-key${var.key_suffix}"
  })]
}
```

**Pros:**

- ✅ **Available immediately** after cluster creation
- ✅ **Bootstrap secrets** for ArgoCD itself
- ✅ **Atomic deployment** with cluster infrastructure
- ✅ **Terraform manages** key lifecycle completely

**Cons:**

- ❌ **Outside GitOps** workflow
- ❌ **Manual updates** required
- ❌ **Mixed management** (some by Terraform, apps by ArgoCD)

#### Option 2: ArgoCD Installation (GitOps Approach)

**When to use:**

- **Pure GitOps** approach preferred
- ArgoCD is **already bootstrapped** with other means
- Want **consistent management** of all applications

```yaml
# ArgoCD Application for sealed-secrets
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sealed-secrets
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1" # Early in bootstrap
spec:
  project: default
  source:
    chart: sealed-secrets
    repoURL: https://bitnami-labs.github.io/sealed-secrets
    targetRevision: 2.17.3
    helm:
      values: |
        secretName: sealed-secrets-key
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Pros:**

- ✅ **Pure GitOps** - everything in Git
- ✅ **Automatic updates** via ArgoCD
- ✅ **Consistent management** model
- ✅ **Declarative configuration**

**Cons:**

- ❌ **Chicken-and-egg** problem for ArgoCD secrets
- ❌ **Manual key management** still required
- ❌ **Complex bootstrap** sequence

#### Hybrid Approach (Recommended)

**Best of both worlds:**

1. **Terraform**: Creates the master key and basic cluster
2. **ArgoCD**: Manages sealed-secrets controller installation

```hcl
# Terraform: Create key but NOT the controller
resource "kubernetes_secret" "sealed_secrets_key" {
  metadata {
    name      = "sealed-secrets-key"
    namespace = "kube-system"
    labels = {
      "sealedsecrets.bitnami.com/sealed-secrets-key" = "active"
    }
  }
  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = tls_private_key.sealed_secrets_key.public_key_pem
    "tls.key" = tls_private_key.sealed_secrets_key.private_key_pem
  }
}

# Output for ArgoCD to reference
output "sealed_secrets_public_key" {
  value = tls_private_key.sealed_secrets_key.public_key_pem
}
```

```yaml
# ArgoCD: Install controller that uses Terraform-created key
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sealed-secrets
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  # ... ArgoCD manages the controller installation
  source:
    helm:
      values: |
        secretName: sealed-secrets-key  # Uses Terraform-created key
```

#### Recommendation for Your PoC

**Use Option 1 (Terraform)** because:

- **Simplicity**: Single tool manages everything
- **Bootstrap**: No ArgoCD dependency issues
- **Key persistence**: Terraform already manages the key
- **PoC appropriate**: Less complexity for demonstration

**Migration path**: When scaling to production, consider moving to the hybrid approach where Terraform creates keys and ArgoCD manages the controller.

### Automated Secret Re-sealing Strategies

**Security Best Practice:** Periodic re-sealing of all secrets helps maintain security hygiene and prepares for key rotation scenarios.

However, the community has learned that **complex automation often breaks more than it helps**. Here are practical approaches:

#### 1. Simple Manual Re-sealing (Recommended for Most Teams)

**When:** Annually or before major deployments

```bash
#!/bin/bash
# scripts/reseal-secrets.sh - Simple and reliable

echo "🔐 Re-sealing all secrets..."

# Get current public key
kubeseal --fetch-cert > /tmp/public.pem

# List of secrets to re-seal (maintain this list manually)
SECRETS=(
  "manifests/my-config-sealed.yaml:security"
  # Add more as needed
)

for entry in "${SECRETS[@]}"; do
  file="${entry%:*}"
  namespace="${entry#*:}"

  if [ -f "$file" ]; then
    echo "Re-sealing: $file"
    # Extract existing secret from cluster and re-seal
    secret_name=$(yq eval '.metadata.name' "$file")
    kubectl get secret "$secret_name" -n "$namespace" -o yaml | \
      yq eval 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.managedFields)' | \
      kubeseal --cert=/tmp/public.pem -o yaml > "$file"
  fi
done

echo "✅ Done! Review changes with: git diff"
```

**Pros:**

- ✅ **Simple and reliable**
- ✅ **Easy to debug**
- ✅ **No complex dependencies**
- ✅ **Team can understand and modify**

#### 2. Community Best Practice: "Don't Re-seal"

**Most experienced teams follow this approach:**

1. **Use Terraform-managed keys** (as shown above) - eliminates re-sealing need
2. **Rotate only when necessary:**
   - Security incidents
   - Key compromise
   - Annual compliance requirements
3. **Focus on key backup/restore** rather than automated re-sealing

**Rationale:**

- Re-sealing introduces more risk than benefit in most cases
- Well-managed keys rarely need rotation
- Manual process ensures human oversight

#### 3. GitOps-Native Approach

Use ArgoCD's built-in capabilities:

```yaml
# argocd-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: secrets-refresh
  annotations:
    # Manual sync only - no automation
    argocd.argoproj.io/sync-options: Manual
spec:
  source:
    path: scripts/
    repoURL: https://github.com/your-org/your-repo
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: default
```

**When needed:**

1. Run the simple script locally
2. Commit changes
3. Manually sync the ArgoCD app

#### 4. Minimal Automation (If You Must)

For teams that really want some automation:

```yaml
# .github/workflows/reseal-reminder.yml
name: Secret Re-sealing Reminder

on:
  schedule:
    - cron: "0 9 1 */6 *" # Every 6 months

jobs:
  remind:
    runs-on: ubuntu-latest
    steps:
      - name: Create Issue
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: '🔐 Scheduled Secret Re-sealing Reminder',
              body: `
                ## Time for Secret Maintenance!
                
                It's been 6 months since our last secret re-sealing.
                
                ### Tasks:
                - [ ] Run \`scripts/reseal-secrets.sh\`
                - [ ] Test applications after re-sealing
                - [ ] Close this issue when complete
                
                ### Commands:
                \`\`\`bash
                ./scripts/reseal-secrets.sh
                git add -A
                git commit -m "chore: re-seal secrets"
                git push
                \`\`\`
              `,
              labels: ['maintenance', 'security']
            });
```

**This approach:**

- ✅ **Creates awareness** without automation complexity
- ✅ **Human oversight** built-in
- ✅ **Simple to understand**
- ✅ **Easy to modify schedule**

#### Real-World Recommendation

**For your PoC and most production systems:**

1. **Use Terraform-managed keys** to eliminate the re-sealing problem entirely
2. **Keep a simple manual script** for the rare cases when you need to re-seal
3. **Focus on backup/restore procedures** rather than complex automation
4. **Set calendar reminders** for annual reviews instead of automated workflows

**Community consensus:**

- Complex re-sealing automation breaks more often than it helps
- Manual processes with good documentation are more reliable
- The Terraform key management approach solves 90% of re-sealing needs
- Most teams re-seal less than once per year in practice

**Quote from sealed-secrets maintainer:**

> "The best re-sealing strategy is not needing to re-seal. Use persistent keys and only rotate when there's a real security need."
