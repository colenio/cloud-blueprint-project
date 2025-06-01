# cloud-blueprint-project

Template for a project repository for cloud-blueprint

## ArgoCD

Once rolled out to an environment named `<project>`, ArgoCD should be available at
`argocd.<project>.<baseDomain>` and configured for SSO using your github organization and team=`<project>`.

Make sure that you are member of the Team `<project>` and you should be able to login

Using the ArgoCD CLI, this would go like this

```shell
# Login
argocd login argocd.<project>.<baseDomain> --sso --grpc-web
# Alternatively, login using direct k8s access (for that set kubecontext and active namespace=argocd accordingly)
argocd login --core

# Some basic commands: list projects, repos, apps, ...
argocd proj list
argocd repo list
argocd app list

# Diff & Sync, Logs for the example app...
argocd app diff argocd/podinfo
argocd app sync argocd/podinfo
argocd app logs argocd/podinfo
```
