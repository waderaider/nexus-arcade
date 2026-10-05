#!/bin/bash
# Godot Android export wrapper: refreshes CA cert and proxy credentials before building.
# The Hatch sandbox rotates both frequently; stale values cause TLS/proxy failures.
set -e
cd ~/workspace/godot-nexus-arcade

# 1. Refresh CA in Temurin keystore
~/workspace/godot-nexus-arcade/refresh-ca.sh > /dev/null 2>&1 || true

# 2. Refresh proxy credentials in gradle.properties
export JAVA_HOME=~/jdk-temurin
export PATH=$JAVA_HOME/bin:$PATH
python3 -c "
import os, urllib.parse
p = os.environ.get('https_proxy', '')
u = urllib.parse.urlparse(p)
user = urllib.parse.unquote(u.username or '')
pw = urllib.parse.unquote(u.password or '')
host = u.hostname or 'hatch-egress-proxy'
port = str(u.port or 3128)
lines = [f'systemProp.http.proxyHost={host}', f'systemProp.http.proxyPort={port}', f'systemProp.http.proxyUser={user}', f'systemProp.http.proxyPassword={pw}', f'systemProp.https.proxyHost={host}', f'systemProp.https.proxyPort={port}', f'systemProp.https.proxyUser={user}', f'systemProp.https.proxyPassword={pw}', 'systemProp.http.nonProxyHosts=localhost|127.0.0.1', 'systemProp.https.nonProxyHosts=localhost|127.0.0.1', 'org.gradle.internal.http.socketTimeout=120000', 'org.gradle.internal.http.connectionTimeout=120000', 'org.gradle.jvmargs=-Djava.net.preferIPv4Stack=true -Xmx2g']
for f in ['/root/.gradle/gradle.properties', '/home/hatch/.gradle/gradle.properties']:
    # preserve non-proxy lines
    keep = []
    try:
        for line in open(f).read().split('\n'):
            if line and not line.startswith('systemProp.') and not line.startswith('org.gradle.'):
                keep.append(line)
    except FileNotFoundError:
        pass
    os.makedirs(os.path.dirname(f), exist_ok=True)
    open(f, 'w').write('\n'.join(lines + keep) + '\n')
    os.chmod(f, 0o600)
"

# 3. Kill stale daemons (they cache old credentials/CA)
for pid in $(ps -eo pid,args 2>/dev/null | grep "[G]radleDaemon" | awk '{print $1}'); do
    kill -9 $pid 2>/dev/null || true
done
sleep 1

# 4. Run the export
export ANDROID_SDK_ROOT=~/android-sdk
export ANDROID_HOME=~/android-sdk
export GRADLE_USER_HOME=/home/hatch/.gradle
export _JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"
# Release signing via env vars (Godot headless reads these); password lives in
# keystore/.release-password (chmod 600), never in this script or the preset.
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PWD/keystore/nexusarcade-release.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="nexusarcade"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(cat "$PWD/keystore/.release-password")"
exec ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless "$@"
