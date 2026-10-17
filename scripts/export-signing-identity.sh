#!/bin/bash
set -euo pipefail

IDENTITY_NAME="voz Dev"
OUTPUT=${1:-voz-signing.p12.b64}

read -r -s -p "Password to protect the export (becomes VOZ_SIGNING_P12_PASSWORD): " PASSWORD
echo
export PASSWORD

WORK=$(mktemp -d)
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

if [[ -z "${ALL_IDENTITIES_P12:-}" ]]; then
    ALL_IDENTITIES_P12=$WORK/all.p12
    security export -k login.keychain-db -t identities -f pkcs12 -P "$PASSWORD" -o "$ALL_IDENTITIES_P12"
fi

openssl pkcs12 -in "$ALL_IDENTITIES_P12" -passin env:PASSWORD -nodes -out "$WORK/all.pem"
awk -v dir="$WORK" '
    /-----BEGIN CERTIFICATE-----/ { file = sprintf("%s/cert-%d.pem", dir, ++count) }
    /-----BEGIN .*PRIVATE KEY-----/ { file = sprintf("%s/key-%d.pem", dir, ++count) }
    file { print > file }
    /-----END / { file = "" }
' "$WORK/all.pem"

for cert in "$WORK"/cert-*.pem; do
    [[ -e "$cert" ]] || continue
    openssl x509 -noout -subject -in "$cert" | grep -q "CN *= *$IDENTITY_NAME\$" || continue
    public_key=$(openssl x509 -pubkey -noout -in "$cert")
    for key in "$WORK"/key-*.pem; do
        [[ -e "$key" ]] || continue
        [[ "$(openssl pkey -pubout -in "$key")" == "$public_key" ]] || continue
        openssl pkcs12 -export -inkey "$key" -in "$cert" -name "$IDENTITY_NAME" \
            -passout env:PASSWORD -out "$WORK/voz.p12"
        base64 -i "$WORK/voz.p12" | tr -d '\n' > "$OUTPUT"
        echo "Wrote $OUTPUT. Paste its contents into the GitHub secret VOZ_SIGNING_P12, then delete the file."
        exit 0
    done
done

echo "Identity '$IDENTITY_NAME' with a private key was not found." >&2
exit 1
