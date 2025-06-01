function(values)
  assert std.objectHas(values, 'project') : "Missing required 'project' key in values";
  assert std.objectHas(values, 'baseDomain') : "Missing required 'baseDomain' key in values";
  {
    apiVersion: 'argoproj.io/v1alpha1',
    kind: 'Application',
    metadata: {
      name: 'podinfo',
      namespace: 'argocd',
    },
    spec: {
      project: 'default',
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true,
        },
        syncOptions: [
          'CreateNamespace=true',
          'PruneLast=true',
        ],
      },
      source: {
        chart: 'podinfo',
        repoURL: 'https://stefanprodan.github.io/podinfo',
        targetRevision: '6.9.0',
        helm: {
          releaseName: 'podinfo',
          valuesObject: {
            ingress: {
              enabled: true,
              className: 'nginx',
              hosts: [
                {
                  host: 'podinfo.' + values.project + '.' + values.baseDomain,
                  paths: [
                    {
                      path: '/',
                      pathType: 'ImplementationSpecific',
                    },
                  ],
                },
              ],
            },
          },
        },
      },
      destination: {
        server: 'https://kubernetes.default.svc',
        namespace: 'podinfo',
      },
    },
  }
