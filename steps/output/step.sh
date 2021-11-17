#!/bin/bash
set -euo pipefail

#
# Commands
#

JQ="${JQ:-jq}"
NI="${NI:-ni}"

#
#
#

# Common

declare -a PACKAGES="( $( $NI get | $JQ -r 'try .os.packages // empty | @sh' ) )"
[[ ${#PACKAGES[@]} -gt 0 ]] && ( set -x ; apk --no-cache add "${PACKAGES[@]}" )

declare -a COMMANDS="( $( $NI get | $JQ -r 'try .os.commands // empty | @sh' ) )"
for COMMAND in ${COMMANDS[@]+"${COMMANDS[@]}"}; do
  ( set -x ; bash -c "${COMMAND}" )
done

WORKSPACE=$(ni get -p {.workspace})
[ -z "${WORKSPACE}" ] && WORKSPACE=default

CREDENTIALS=$(ni get -p {.credentials})
if [ -n "${CREDENTIALS}" ]; then
  ni credentials config
  export GOOGLE_APPLICATION_CREDENTIALS=/workspace/credentials.json
fi

GOOGLE=$(ni get -p {.google})
if [ -n "${GOOGLE}" ]; then
  ni gcp config -d "/workspace/.gcp"
  export GOOGLE_APPLICATION_CREDENTIALS=/workspace/.gcp/credentials.json
fi

AWS=$(ni get -p {.aws})
if [ -n "${AWS}" ]; then
  ni aws config
  export AWS_SHARED_CREDENTIALS_FILE=/workspace/.aws/credentials
fi

AZURE=$(ni get -p {.azure})
if [ -n "${AZURE}" ]; then
  eval "$( ni azure arm env )"
fi

DIRECTORY=$(ni get -p {.directory})

GIT=$(ni get -p {.git})
if [ -n "${GIT}" ]; then
  ni git clone
  NAME=$(ni get -p {.git.name})
  DIRECTORY="/workspace/${NAME}/${DIRECTORY}"
fi

declare -a TERRAFORM_INIT_ARGS="( $( $NI get | $JQ -r 'try .backendConfig | to_entries[] | "-backend-config=\( .key )=\( .value )" | @sh' ) )"

cd "${DIRECTORY}"

export TF_IN_AUTOMATION=true

terraform init "${TERRAFORM_INIT_ARGS[@]}"
terraform workspace select ${WORKSPACE}

# Provider initialization may be workspace-dependent. See
# https://discuss.hashicorp.com/t/terraform-v0-13-failed-to-instantiate-provider-for-every-project/16522
# for more information.
terraform init -reconfigure "${TERRAFORM_INIT_ARGS[@]}"

WORKSPACE_OUTPUTS=/workspace/outputs.json

terraform output
terraform output -json > ${WORKSPACE_OUTPUTS}

declare -a NI_OUTPUT_SET_ARGS

declare -a OUTPUT_KEYS="( $( ${JQ} -r 'keys | .[]' ${WORKSPACE_OUTPUTS} ) )"

for KEY in "${OUTPUT_KEYS[@]}"; do
  NI_OUTPUT_SET_ARGS=( --json )

  SENSITIVE="$( ${JQ} --arg key "${KEY}" '.[$key].sensitive' ${WORKSPACE_OUTPUTS} )"
  if [ "${SENSITIVE}" = "true" ]; then
      NI_OUTPUT_SET_ARGS+=( --sensitive )
  fi

  VALUE="$( ${JQ} --arg key "${KEY}" '.[$key].value' ${WORKSPACE_OUTPUTS} )"

  ${NI} output set "${NI_OUTPUT_SET_ARGS[@]}" \
    --key "${KEY}" --value "${VALUE}"
done
