#!/bin/bash
# Refresh Hatch egress CA in Temurin keystore before Gradle builds.
# The CA rotates frequently; stale CA causes "PKIX path validation failed".
set -e
JAVA_HOME=~/jdk-temurin
CA_FILE=/usr/local/share/ca-certificates/hatch-egress-ca.crt
KEYSTORE=$JAVA_HOME/lib/security/cacerts

# Get current fingerprints
SRC_FP=$(openssl x509 -in $CA_FILE -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
DST_FP=$($JAVA_HOME/bin/keytool -list -keystore $KEYSTORE -storepass changeit -alias hatch-egress-ca 2>/dev/null | grep "SHA-256" | cut -d: -f2- | tr -d ' :' || echo "missing")

# Normalize (remove colons, uppercase)
SRC_NORM=$(echo $SRC_FP | tr -d ':' | tr 'a-z' 'A-Z')
DST_NORM=$(echo $DST_FP | tr -d ':' | tr 'a-z' 'A-Z')

if [ "$SRC_NORM" != "$DST_NORM" ]; then
    echo "CA rotated, updating keystore..."
    $JAVA_HOME/bin/keytool -delete -alias hatch-egress-ca -keystore $KEYSTORE -storepass changeit 2>/dev/null || true
    $JAVA_HOME/bin/keytool -import -trustcacerts -alias hatch-egress-ca -file $CA_FILE -keystore $KEYSTORE -storepass changeit -noprompt 2>&1 | head -1
    # Kill daemons so they pick up the new CA
    for pid in $(ps -eo pid,args | grep "[G]radleDaemon" | awk '{print $1}'); do
        kill -9 $pid 2>/dev/null || true
    done
    echo "CA updated and daemons cleared"
else
    echo "CA is current"
fi
