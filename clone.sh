#!/usr/bin/env bash

#
# A script to fetch the latest versions of Bitnami charts,
# package them, and push them to a personal GitHub Helm repository.
#
# VERSION 2: This version uses `helm search` directly to find charts,
# making it more robust by removing the dependency on the Artifact Hub API.
#

set -e # Exit immediately if a command exits with a non-zero status.

# --- SCRIPT CONFIGURATION ---
#
# !!! IMPORTANT: UPDATE THESE VALUES !!!
#
GITHUB_USER="razvanbalsan-boatyardx"
GITHUB_REPO="bitnami-helm-repo"

# The number of latest versions to fetch for each chart.
NUM_VERSIONS=5
# --- END CONFIGURATION ---

# The final URL of your GitHub Pages site.
REPO_URL="https://${GITHUB_USER}.github.io/${GITHUB_REPO}"

echo "Helm Repo URL will be: ${REPO_URL}"
echo "Running script from: $(pwd)"
echo "---"

echo "Step 1: Updating the Bitnami Helm repository..."
helm repo update bitnami
echo "---"

echo "Step 2: Finding all charts in the 'bitnami' repository..."
# We use `helm search` to get the list of charts, then `awk` and `sed` to clean up the names.
# This avoids the external API call, which is more robust.
chart_names=$(helm search repo bitnami/ --max-col-width 200 | awk 'NR>1 {print $1}' | sed 's|bitnami/||')

if [ -z "$chart_names" ]; then
    echo "Error: Could not find any charts in the Bitnami repository. Please check your Helm setup."
    exit 1
fi
echo "Found charts. Starting to process..."
echo "---"

echo "Step 3: Pulling the latest ${NUM_VERSIONS} versions of each chart..."
for pkg_name in $chart_names; do
  echo "Processing Chart: ${pkg_name}"
  
  # Get the latest versions for this package
  versions_to_pull=$(helm search repo "bitnami/${pkg_name}" -l --max-col-width 200 | awk 'NR>1 {print $2}' | head -n "${NUM_VERSIONS}")

  if [ -z "$versions_to_pull" ]; then
      echo "  - WARNING: Could not find versions for ${pkg_name}. Skipping."
      continue
  fi

  for version in $versions_to_pull; do
    if [ -f "${pkg_name}-${version}.tgz" ]; then
      echo "  - Version ${version} already exists. Skipping download."
    else
      echo "  - Pulling version ${version}..."
      helm pull "bitnami/${pkg_name}" --version "${version}" --destination .
    fi
  done
done
echo "---"

echo "Step 4: Re-indexing the repository..."
helm repo index . --url "${REPO_URL}"

echo "---"
echo "Step 5: Committing and pushing to GitHub..."
git add .
if git diff-index --quiet HEAD; then
    echo "No new chart versions to commit. Repository is up-to-date."
else
    git commit -m "Update Helm charts - $(date)"
    echo "Pushing to GitHub..."
    git push origin main
    echo "Successfully pushed to GitHub. It may take a minute for GitHub Pages to update."
fi
echo "---"
echo "All done!"