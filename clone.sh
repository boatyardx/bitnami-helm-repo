#!/usr/bin/env bash

#
# A script to fetch Bitnami charts and push them to a personal GitHub Helm repo.
#
# VERSION 3: Added command-line options for flexible operation.
#
# MODES:
#  --all          (Default) Sync latest versions of ALL charts.
#  --latest X     Sync latest versions of the X most recently updated charts.
#  --chart C --version V  Sync a single, specific chart version.
#

set -e # Exit immediately if a command fails.

# --- SCRIPT CONFIGURATION ---
GITHUB_USER="razvanbalsan-boatyardx"
GITHUB_REPO="bitnami-helm-repo"
NUM_VERSIONS=10 # Default number of versions to pull in --all or --latest mode.
# --- END CONFIGURATION ---

# The final URL of your GitHub Pages site.
REPO_URL="https://${GITHUB_USER}.github.io/${GITHUB_REPO}"

# --- Usage Function ---
usage() {
  cat << EOF
A script to sync Bitnami charts to a personal Helm repository.

Usage: $(basename "$0") [options]

Options:
  --all                 Sync the latest ${NUM_VERSIONS} versions of every Bitnami chart. (Default behavior)
  --latest <count>      Sync the latest ${NUM_VERSIONS} versions for the <count> most recently updated charts.
                        Requires 'curl' and 'jq'.
  --chart <name> --version <version>
                        Sync only a specific chart and version.
  -h, --help            Display this help message.

Examples:
  $(basename "$0")
  $(basename "$0") --all
  $(basename "$0") --latest 5
  $(basename "$0") --chart wordpress --version 19.2.2
EOF
}

# --- Argument Parsing ---
MODE="all" # Default mode
LATEST_COUNT=0
CHART_NAME=""
CHART_VERSION=""

if [ $# -eq 0 ]; then
  echo "No options provided. Defaulting to '--all' mode."
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --all)
      MODE="all"
      shift
      ;;
    --latest)
      MODE="latest"
      if [[ ! "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --latest requires a number." >&2; usage; exit 1
      fi
      LATEST_COUNT="$2"
      shift 2
      ;;
    --chart)
      MODE="specific"
      if [ -z "$2" ]; then
        echo "Error: --chart requires a name." >&2; usage; exit 1
      fi
      CHART_NAME="$2"
      shift 2
      ;;
    --version)
      if [ "$MODE" != "specific" ]; then
        echo "Error: --version can only be used with --chart." >&2; usage; exit 1
      fi
      if [ -z "$2" ]; then
        echo "Error: --version requires a version number." >&2; usage; exit 1
      fi
      CHART_VERSION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# Validate that --chart and --version were used together
if [ "$MODE" == "specific" ] && [ -z "$CHART_VERSION" ]; then
    echo "Error: --version is required when using --chart." >&2
    usage
    exit 1
fi

# --- Main Logic ---

echo "Helm Repo URL will be: ${REPO_URL}"
echo "Running script from: $(pwd)"
echo "---"

echo "Step 1: Updating the Bitnami Helm repository..."
helm repo update bitnami
echo "---"

# --- Step 2 & 3: Fetch charts based on selected mode ---

if [ "$MODE" == "specific" ]; then
    echo "Mode: Specific Chart"
    echo "Pulling chart: ${CHART_NAME}, version: ${CHART_VERSION}"
    if [ -f "${CHART_NAME}-${CHART_VERSION}.tgz" ]; then
        echo "  - Chart already exists. Skipping download."
    else
        helm pull "bitnami/${CHART_NAME}" --version "${CHART_VERSION}" --destination .
    fi
else
    # This block handles both 'all' and 'latest' modes
    chart_names=""
    if [ "$MODE" == "all" ]; then
        echo "Mode: Full Sync (--all)"
        echo "Finding all charts in the 'bitnami' repository..."
        chart_names=$(helm search repo bitnami/ --max-col-width 200 | awk 'NR>1 {print $1}' | sed 's|bitnami/||')
    elif [ "$MODE" == "latest" ]; then
        echo "Mode: Latest ${LATEST_COUNT} Charts"
        # Check for dependencies for this mode
        if ! command -v jq &> /dev/null; then
            echo "Error: 'jq' is required for --latest mode but could not be found." >&2
            echo "Please install it (e.g., 'brew install jq') and try again." >&2
            exit 1
        fi
        echo "Finding the ${LATEST_COUNT} most recently updated charts..."
        chart_names=$(curl -s "https://artifacthub.io/api/v1/packages/search?org=bitnami&kind=0&sort=updated&limit=${LATEST_COUNT}" | jq -r '.packages[].name')
    fi

    if [ -z "$chart_names" ]; then
        echo "Error: Could not find any charts to process." >&2
        exit 1
    fi

    echo "Found charts. Pulling the latest ${NUM_VERSIONS} versions of each..."
    echo "---"
    for pkg_name in $chart_names; do
      echo "Processing Chart: ${pkg_name}"
      versions_to_pull=$(helm search repo "bitnami/${pkg_name}" -l --max-col-width 200 | awk 'NR>1 {print $2}' | head -n "${NUM_VERSIONS}")
      if [ -z "$versions_to_pull" ]; then
          echo "  - WARNING: Could not find versions for ${pkg_name}. Skipping."
          continue
      fi
      for version in $versions_to_pull; do
        if [ -f "${pkg_name}-${version}.tgz" ]; then
            echo "  - Version ${version} already exists. Skipping."
        else
            echo "  - Pulling version ${version}..."
            helm pull "bitnami/${pkg_name}" --version "${version}" --destination .
        fi
      done
    done
fi
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
