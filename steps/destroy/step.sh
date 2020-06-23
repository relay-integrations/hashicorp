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

AWS=$(ni get -p {.aws})
if [ -n "${AWS}" ]; then
  ni aws config
  export AWS_SHARED_CREDENTIALS_FILE=/workspace/.aws/credentials
fi

DIRECTORY=$(ni get -p {.directory})

GIT=$(ni get -p {.git})
if [ -n "${GIT}" ]; then
  ni git clone
  NAME=$(ni get -p {.git.name})
  DIRECTORY="/workspace/${NAME}/${DIRECTORY}"
fi

ni get | jq 'try .vars // {}' >/workspace/step.tfvars.json

declare -a TERRAFORM_INIT_ARGS="( $( $NI get | $JQ -r 'try .backendConfig | to_entries[] | "-backend-config=\( .key )=\( .value )" | @sh' ) )"

(
  cd "${DIRECTORY}"

  export TF_IN_AUTOMATION=true

  terraform init "${TERRAFORM_INIT_ARGS[@]}"
  terraform workspace new "${WORKSPACE}" || {
    echo "step: ignoring error creating workspace because it may already exist" >&2
  }
  terraform workspace select ${WORKSPACE}
  terraform destroy -var-file=/workspace/step.tfvars.json -auto-approve
)
