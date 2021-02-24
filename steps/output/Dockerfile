FROM hashicorp/terraform:light
RUN set -eux ; \
    mkdir -p /tmp/ni && \
    cd /tmp/ni && \
    wget https://packages.nebula.puppet.net/sdk/ni/v1/ni-v1-linux-amd64.tar.xz && \
    wget https://packages.nebula.puppet.net/sdk/ni/v1/ni-v1-linux-amd64.tar.xz.sha256 && \
    echo "$( cat ni-v1-linux-amd64.tar.xz.sha256 )  ni-v1-linux-amd64.tar.xz" | sha256sum -c - && \
    tar -xvJf ni-v1-linux-amd64.tar.xz && \
    mv ni-v1*-linux-amd64 /usr/local/bin/ni && \
    cd - && \
    rm -fr /tmp/ni
RUN apk --no-cache add bash ca-certificates curl git jq openssh && update-ca-certificates
COPY "./step.sh" "/nebula/step-terraform-step-output.sh"
ENTRYPOINT []
CMD ["/bin/bash", "/nebula/step-terraform-step-output.sh"]

LABEL "org.opencontainers.image.title"="List Terraform outputs"
LABEL "org.opencontainers.image.description"="This step will list the outputs of the given Terraform module. The outputs of this step are the same as the Terraform outputs."
LABEL "com.puppet.nebula.sdk.version"="v1"
