# Azure Container Registry (ACR) Integration

This configuration automatically sets up ACR integration for each project, enabling container image pushing to a shared ACR instance.

## What's Created

For each project, the following resources are created:

### Azure Resources

- **ACR Token**: A project-specific token for authentication
- **ACR Scope Map**: Limits access to repositories with the project prefix (`{project}/*`)
- **ACR Token Password**: Authentication credentials for the token

### GitHub Secrets

The following github variables & secrets are automatically created in the project repository:

- `ACR_REGISTRY_URL`: The ACR login server URL
- `ACR_USERNAME`: The ACR token name
- `ACR_PASSWORD`: The ACR token password (secret)

## Usage in GitHub Actions

You can use these secrets in your GitHub Actions workflows to build and push container images:

```yaml
name: MyApp-Build

on:
  push:
    branches: [main]

jobs:
  build:
    uses: ./.github/workflows/_build.yml
    with:
      component: myapp
      cr: ${{ vars.ACR_REGISTRY_URL }}
      cr_user: ${{ vars.ACR_USERNAME }}
    secrets:
      crToken: ${{ secrets.ACR_PASSWORD }}
```

## Repository Naming Convention

Container images should be pushed to repositories with the project prefix:

- Format: `{acr_login_server}/{project_name}/{image_name}:{tag}`
- Example: `myacr.azurecr.io/myproject/myapp:latest`

## Permissions

The ACR token has the following permissions:

- **Push**: Can push images to `{project}/*` repositories
- **Pull**: Can pull images from `{project}/*` repositories
