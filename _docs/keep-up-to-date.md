# Keeping Your Repository Up-to-Date

When you create a repository from a template on GitHub, it is a snapshot of the template at that moment. Over time, the template may receive updates, and you might want to incorporate those changes into your own repository.

Here are the common approaches to handle this:

1. **Manual Approach (Most Common)**

   - Manually cherry-pick or copy changes from the template repository
   - Compare files between your repo and the template using GitHub's compare view
   - Apply changes selectively based on what's relevant to your project

2. **Add Template as Remote (Recommended)**

   You can manually set up a relationship to pull updates:

   ```shell
   # Add the template repo as a remote
   git remote add template https://github.com/original-owner/template-repo.git

   # Fetch the latest changes
   git fetch template

   # Create a new branch to merge template changes
   git checkout -b update-from-template

   # Merge or cherry-pick specific commits
   git merge template/main
   # OR cherry-pick specific commits
   git cherry-pick <commit-hash>

   # Resolve conflicts and create PR
   ```

3. **GitHub Actions Automation**

   Create a workflow to periodically check for template updates:

   ```yaml
   # .github/workflows/check-template-updates.yml
   name: Check Template Updates
   on:
   schedule:
       - cron: '0 0 * * 1' # Weekly on Monday
   workflow_dispatch: # Manual trigger

   jobs:
   check-template:
       runs-on: ubuntu-latest
       steps:
       - uses: actions/checkout@v4
       - name: Add template remote
           run: |
           git remote add template https://github.com/original-owner/template-repo.git
           git fetch template
       - name: Check for updates
           run: |
           # Compare and create issue or PR if changes detected
           git log HEAD..template/main --oneline
   ```

4. **Third-Party Tools**

- **Renovate** or **Dependabot** can be configured to monitor template repositories
- **GitHub App solutions** like "Template Sync" (community-built)

## Best Practices

1. **Document your customizations** - Keep track of what you've changed from the template
2. **Use feature branches** - Always merge template updates in a separate branch first
3. **Selective merging** - Don't blindly merge everything; review what's applicable
4. **Template versioning** - If you maintain the template, use tags/releases for stable versions

The template relationship is intentionally "fire and forget" because templates are meant to be starting points that diverge significantly from the original. If you need ongoing synchronization, consider using repository forks instead of templates.
