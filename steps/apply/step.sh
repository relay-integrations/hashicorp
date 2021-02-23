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

DIRECTORY=$(ni get -p {.directory})

GIT=$(ni get -p {.git})
if [ -n "${GIT}" ]; then
  ni git clone
  NAME=$(ni get -p {.git.name})
  DIRECTORY="/workspace/${NAME}/${DIRECTORY}"
fi

declare -a TERRAFORM_ARGS
TERRAFORM_ARGS+=( -input=false -auto-approve )

ni get -p {.plan} >/workspace/step.tfplan
if [[ "$( wc -c </workspace/step.tfplan )" -gt 0 ]]; then
  TERRAFORM_ARGS+=( /workspace/step.tfplan )
else
  declare -a VAR_FILES="( $( ni get | jq -r 'try .varFiles[] | "-var-file=\(.)" | @sh' ) )"
  [[ ${#VAR_FILES[@]} -gt 0 ]] && TERRAFORM_ARGS+=( "${VAR_FILES[@]}" )

  ni get | jq 'try .vars // {}' >/workspace/step.tfvars.json
  TERRAFORM_ARGS+=( -var-file=/workspace/step.tfvars.json )
fi

declare -a TERRAFORM_INIT_ARGS="( $( $NI get | $JQ -r 'try .backendConfig | to_entries[] | "-backend-config=\( .key )=\( .value )" | @sh' ) )"

cd "${DIRECTORY}"

export TF_IN_AUTOMATION=true

terraform init "${TERRAFORM_INIT_ARGS[@]}"
terraform workspace new "${WORKSPACE}" || {
  echo "step: ignoring error creating workspace because it may already exist" >&2
}
terraform workspace select ${WORKSPACE}

# Provider initialization may be workspace-dependent. See
# https://discuss.hashicorp.com/t/terraform-v0-13-failed-to-instantiate-provider-for-every-project/16522
# for more information.
terraform init -reconfigure "${TERRAFORM_INIT_ARGS[@]}"

terraform apply "${TERRAFORM_ARGS[@]}"

terraform output -json >/workspace/outputs.json

declare -a OUTPUT_KEYS="( $( jq -r 'keys | .[]' /workspace/outputs.json ) )"
for KEY in "${OUTPUT_KEYS[@]}"; do
  ni output set --key "${KEY}" --json --value "$( jq --arg key "${KEY}" '.[$key].value' /workspace/outputs.json )"
done
