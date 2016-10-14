#!/usr/bin/env bash
##
## How to use:
## From the repo root directory (croot):
##   $ ./docs/source.android.com/scripts/build2stage.sh [options] server-number
##
## To build/stage from anywhere, add an alias or scripts/ to PATH.
##
## Examples:
## Build and stage on staging instance 13:
##   $ build2stage.sh 13
## Build only (outputs to out/target/common/docs/online-sac):
##   $ build2stage.sh -b
## Stage only (using existing build):
##   $ build2stage.sh -s 13

usage() {
  echo "Usage: $(basename $0) [options] server-number"
  echo "Options:"
  echo " -b    Build docs without staging"
  echo " -s    Stage only using an existing build"
  echo " -h    Print this help and exit"
}

# Arguments required
if [ $# -eq 0 ]; then
  usage
  exit 1
fi

## VARS

# Determine repo root relative to the location of this script
REPO_ROOT="$(cd $(dirname $0)/../../..; pwd -P)"
DOCS_OUT_ROOT="$REPO_ROOT/out/target/common/docs"
SAC_OUT_ROOT="$DOCS_OUT_ROOT/online-sac"
AE_STAGING_CONF="/etc/profile.d/build2stage-conf.sh"
LOG_NAME="[$(basename $0)]"

# Parse options
while getopts "bsh" opt; do
  case $opt in
    b) BUILD_ONLY_FLAG=1;;
    s) STAGE_ONLY_FLAG=1;;
    h | *)
      usage
      exit 0
      ;;
  esac
done

##
## Check args
##

# Get final command-line arg
for last; do true; done
STAGING_NUM="$last"

if [ -z "$BUILD_ONLY_FLAG" ]; then
  # Must be a number
  if ! [[ "$STAGING_NUM" =~ ^[0-9]+$ ]] ; then
    echo "${LOG_NAME} Error: Argument for server instance must be a number" 1>&2
    usage
    exit 1
  fi
fi

if [ -n "$STAGE_ONLY_FLAG" ] && [ ! -d "$SAC_OUT_ROOT" ]; then
  echo "${LOG_NAME} Error: Unable to stage without a build" 1>&2
  exit 1
fi

# Retrieve App Engine staging config 'AE_STAGING' if it doesn't already exist
if [ -z "$AE_STAGING" ] && [ -e "$AE_STAGING_CONF" ]; then
  source "$AE_STAGING_CONF"
fi

# If staging, require staging config
if [ -z "$BUILD_ONLY_FLAG" ] && [ -z "$AE_STAGING" ]; then
  echo "${LOG_NAME} Error: No value for AE_STAGING" 1>&2
  echo "Set in local environment or ${AE_STAGING_CONF}" 1>&2
  exit 1
fi

# Default lunch build config
: ${BUILD_TARGET:="aosp_arm-eng"}

##
## BUILD DOCS
##
if [ -n "$STAGE_ONLY_FLAG" ]; then
  echo "${LOG_NAME} Not building"

else
  cd "$REPO_ROOT"

  # Delete old output
  if [ -d "$SAC_OUT_ROOT" ]; then
    echo "${LOG_NAME} Removing old build: ${SAC_OUT_ROOT}"
    rm -rf "$SAC_OUT_ROOT"*
  fi

  # Initialize the build environment
  source build/make/envsetup.sh

  # Select a target and finish setting up the environment
  lunch "$BUILD_TARGET"

  # Build the docs and output to: out/target/common/docs/online-sac
  make online-sac-docs
fi

##
## STAGE DOCS
##
if [ -n "$BUILD_ONLY_FLAG" ]; then
  echo "${LOG_NAME} Not staging"

else
  # Make sure there's something to stage
  if [ ! -d "$SAC_OUT_ROOT" ]; then
    echo "${LOG_NAME} Error: Unable to stage without a build" 1>&2
    exit 1
  fi

  ## Set staging server

  # Parse current value for yaml key 'application'
  STAGING_SERVER=$(cat "$SAC_OUT_ROOT/app.yaml" | grep "^application:" | \
                     cut -d ':' -f2- | tr -d ' ')
  # Remove any trailing numbers in case it's already been set
  STAGING_SERVER=$(echo "$STAGING_SERVER" | sed 's/[0-9]\{1,10\}$//')

  # Set new staging server
  STAGING_SERVER="${STAGING_SERVER}${STAGING_NUM}"

  tmpfile=$(mktemp /tmp/app.yaml.XXXX)

  # Replace application key in tmp app.yaml with specified staging server
  sed "s/^application:.*/application: ${STAGING_SERVER}/" \
      "$SAC_OUT_ROOT/app.yaml" > "$tmpfile"

  # Copy in new app.yaml content
  cp "$tmpfile" "${SAC_OUT_ROOT}/app.yaml"
  rm "$tmpfile"

  echo "${LOG_NAME} Configured stage for ${STAGING_SERVER}"

  ## Stage
  ##
  echo "${LOG_NAME} Start staging ..."

  # Go to the output directory to stage content
  cd "$DOCS_OUT_ROOT"

  # Stage to specified server
  if $AE_STAGING update online-sac; then
    echo "${LOG_NAME} Content now available at staging instance ${STAGING_NUM}"
  else
    echo "${LOG_NAME} Error: Unable to stage to ${STAGING_SERVER}" 1>&2
    exit 1
  fi
fi
