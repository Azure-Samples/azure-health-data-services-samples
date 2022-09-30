#/bin/bash -e

cd $HOME

# Install dotnet
apk add bash icu-libs krb5-libs libgcc libintl libssl1.1 libstdc++ zlib
apk add libgdiplus --repository https://dl-3.alpinelinux.org/alpine/edge/testing/ --allow-untrusted
wget https://dot.net/v1/dotnet-install.sh
chmod +x dotnet-install.sh
bash dotnet-install.sh

export PATH="$PATH:/root/.dotnet"

#bash dotnet-install.sh --runtime dotnet --version 6.0.4

# Get FHIR Loader CLI
wget https://github.com/microsoft/fhir-loader/releases/download/v1.0.0/FhirLoader.Tool.0.9.0.nupkg

# Unpack FHIR Loader CLI
unzip FhirLoader.Tool.0.9.0.nupkg

# Load Data
dotnet tools/net6.0/any/FhirLoader.Tool.dll --blob "https://ahdssampledata.blob.core.windows.net/fhir/synthea-ndjson-100/" --fhir "$FHIR_URL"