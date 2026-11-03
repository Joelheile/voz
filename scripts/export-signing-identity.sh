#!/bin/bash
set -euo pipefail

export LC_ALL=C
TEAM_ID=G2CSKBA739
OUTPUT=${1:-developer-id.p12.b64}

read -r -s -p "Password to protect the export (becomes DEVELOPER_ID_P12_PASSWORD): " PASSWORD
echo
export PASSWORD

WORK=$(mktemp -d)
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

if [[ -z "${ALL_IDENTITIES_P12:-}" ]]; then
    ALL_IDENTITIES_P12=$WORK/all.p12
    security export -k login.keychain-db -t identities -f pkcs12 -P "$PASSWORD" -o "$ALL_IDENTITIES_P12"
fi

/usr/bin/openssl pkcs12 -in "$ALL_IDENTITIES_P12" -passin env:PASSWORD -nodes -out "$WORK/all.pem"
awk -v dir="$WORK" '
    /-----BEGIN CERTIFICATE-----/ { file = sprintf("%s/cert-%d.pem", dir, ++count) }
    /-----BEGIN .*PRIVATE KEY-----/ { file = sprintf("%s/key-%d.pem", dir, ++count) }
    file { print > file }
    /-----END / { file = "" }
' "$WORK/all.pem"

for cert in "$WORK"/cert-*.pem; do
    [[ -e "$cert" ]] || continue
    subject=$(/usr/bin/openssl x509 -noout -subject -in "$cert")
    [[ "$subject" == *"Developer ID Application"* && "$subject" =~ OU\ ?=\ ?$TEAM_ID ]] || continue
    public_key=$(/usr/bin/openssl x509 -pubkey -noout -in "$cert")
    for key in "$WORK"/key-*.pem; do
        [[ -e "$key" ]] || continue
        [[ "$(/usr/bin/openssl pkey -pubout -in "$key")" == "$public_key" ]] || continue
        /usr/bin/openssl pkcs12 -export -inkey "$key" -in "$cert" -name "Developer ID Application ($TEAM_ID)" \
            -passout env:PASSWORD -out "$WORK/developer-id.p12"
        base64 -i "$WORK/developer-id.p12" | tr -d '\n' > "$OUTPUT"
        echo "Wrote $OUTPUT. Paste its contents into the GitHub secret DEVELOPER_ID_P12, then delete the file."
        exit 0
    done
done

echo "No Developer ID Application identity with a private key for team $TEAM_ID." >&2
exit 1
