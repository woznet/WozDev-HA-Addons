# Dockerfile reference: https://github.com/PowerShell/PowerShell-Docker/blob/master/release/7-4/alpine317/docker/Dockerfile
ARG BUILD_FROM
FROM $BUILD_FROM AS installer-env

# PowerShell (pwsh)
ARG PS_VERSION=7.5.4
ARG PS_PACKAGE=powershell-${PS_VERSION}-linux-musl-x64.tar.gz
ARG PS_PACKAGE_URL=https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/${PS_PACKAGE}
ARG PS_INSTALL_VERSION=7
ENV PS_INSTALL_FOLDER=/opt/microsoft/powershell/$PS_INSTALL_VERSION

# 1Password CLI (op)
ARG OP_CLI_VERSION=2.32.1
ARG OP_CLI_PACKAGE=op_linux_amd64_v${OP_CLI_VERSION}.zip
ARG OP_CLI_URL=https://cache.agilebits.com/dist/1P/op2/pkg/v${OP_CLI_VERSION}/${OP_CLI_PACKAGE}
ENV OP_CLI_INSTALL_FOLDER=/opt/1password-cli

# Tools needed only for installer stage
RUN apk add --no-cache curl unzip

# 1Password CLI - Download and install
RUN mkdir -p ${OP_CLI_INSTALL_FOLDER} \
  && curl -fsSL ${OP_CLI_URL} -o /tmp/op.zip \
  && unzip -q /tmp/op.zip -d ${OP_CLI_INSTALL_FOLDER} \
  && chmod 0755 ${OP_CLI_INSTALL_FOLDER}/op \
  && rm -f /tmp/op.zip

# PowerShell - Download and install
RUN mkdir -p ${PS_INSTALL_FOLDER} \
  && curl -fSL ${PS_PACKAGE_URL} -o /tmp/linux.tar.gz \
  && tar zxf /tmp/linux.tar.gz -C ${PS_INSTALL_FOLDER} -v \
  && rm -f /tmp/linux.tar.gz

# Start a new stage so we lose all the tar.gz layers from the final image
FROM $BUILD_FROM

COPY --from=installer-env ["/opt/microsoft/powershell", "/opt/microsoft/powershell"]
COPY --from=installer-env ["/opt/1password-cli", "/opt/1password-cli"]

# Define Args and Env needed to create links
ARG PS_INSTALL_VERSION=7
ENV PS_INSTALL_FOLDER=/opt/microsoft/powershell/$PS_INSTALL_VERSION \
  OP_CLI_INSTALL_FOLDER=/opt/1password-cli \
  \
  # Define ENVs for Localization/Globalization
  DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false \
  LC_ALL=en_US.UTF-8 \
  LANG=en_US.UTF-8 \
  # set a fixed location for the Module analysis cache
  PSModuleAnalysisCachePath=/var/cache/microsoft/powershell/PSModuleAnalysisCache/ModuleAnalysisCache \
  POWERSHELL_DISTRIBUTION_CHANNEL=PSDocker-Alpine-3.20

# Install dotnet dependencies and ca-certificates
RUN apk add --no-cache \
  ca-certificates \
  less \
  \
  # PSReadline/console dependencies
  ncurses-terminfo-base \
  \
  # .NET Core dependencies
  krb5-libs \
  libgcc \
  libintl \
  libssl3 \
  libstdc++ \
  tzdata \
  userspace-rcu \
  zlib \
  icu-libs \
  && apk -X https://dl-cdn.alpinelinux.org/alpine/edge/main add --no-cache \
  lttng-ust \
  \
  # PowerShell remoting over SSH dependencies
  openssh-client \
  \
  && apk update \
  && apk upgrade \
  \
  # Create the op symbolic link that points to the 1password cli
  && ln -s ${OP_CLI_INSTALL_FOLDER}/op /usr/bin/op \
  && chmod a+x,o-w ${OP_CLI_INSTALL_FOLDER}/op \
  \
  # Create the pwsh symbolic link that points to powershell
  && ln -s ${PS_INSTALL_FOLDER}/pwsh /usr/bin/pwsh \
  && chmod a+x,o-w ${PS_INSTALL_FOLDER}/pwsh \
  \
  # initialize powershell module cache and disable telemetry
  && export POWERSHELL_TELEMETRY_OPTOUT=1 \
  && pwsh \
  -NoLogo \
  -NoProfile \
  -Command " \
  \$ErrorActionPreference = 'Stop' ; \
  \$ProgressPreference = 'SilentlyContinue' ; \
  while(!(Test-Path -Path \$env:PSModuleAnalysisCachePath)) { \
  Write-Host "Waiting for \$PSModuleAnalysisCachePath" ; \
  Start-Sleep -Seconds 6 ; \
  }"

COPY Run-ScriptsAsThreads.ps1 /app/
COPY Read-HassIoStdIn.ps1 /app/

ENTRYPOINT ["pwsh","-NoProfile", "-NoLogo", "-NonInteractive","-File","/app/Run-ScriptsAsThreads.ps1"]
