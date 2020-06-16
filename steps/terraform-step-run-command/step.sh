#!/bin/bash

#
# Commands
#

JQ="${JQ:-jq}"
NI="${NI:-ni}"

#
#
#

declare -a PACKAGES="( $( $NI get | $JQ -r 'try .os.packages // empty | @sh' ) )"
[[ ${#PACKAGES[@]} -gt 0 ]] && ( set -x ; apk --no-cache add "${PACKAGES[@]}" )

declare -a COMMANDS="( $( $NI get | $JQ -r 'try .os.commands // empty | @sh' ) )"
for COMMAND in ${COMMANDS[@]+"${COMMANDS[@]}"}; do
  ( set -x ; bash -c "${COMMAND}" )
done

DIRECTORY=$(ni get -p {.directory})
WORKSPACE=$(ni get -p {.workspace})
COMMAND=$(ni get -p {.command})
[ "$COMMAND" ] || COMMAND="apply"
WORKSPACE_FILE=workspace.${WORKSPACE}.tfvars.json

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

GIT=$(ni get -p {.git})
if [ -n "${GIT}" ]; then
    ni git clone
    NAME=$(ni get -p {.git.name})
    WORKSPACE_PATH=/workspace/${NAME}/${DIRECTORY}
else
    WORKSPACE_PATH=${DIRECTORY}
fi

ni file -p vars -f ${WORKSPACE_PATH}/${WORKSPACE_FILE} -o json

cd ${WORKSPACE_PATH}

export TF_IN_AUTOMATION=true

declare -a BACKEND_CONFIGS="( $( $NI get | $JQ -r 'try .backendConfig | to_entries[] | "-backend-config=\( .key )=\( .value )" | @sh' ) )"

terraform init ${BACKEND_CONFIGS[@]}
terraform workspace new ${WORKSPACE}
terraform workspace select ${WORKSPACE}
terraform ${COMMAND} -auto-approve

keys=$(terraform output -json | jq -r '. | keys | .[]')
for key in ${keys}; do
    value=$(terraform output ${key})
    if [[ "${value}" == *$'\n'* ]]; then
        value=$(echo "${value}" | base64 | tr -d '\n')
    fi
    ni output set --key "${key}" --value "${value}"
done
