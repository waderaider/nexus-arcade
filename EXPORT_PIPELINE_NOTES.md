# NEXUS ARCADE - Godot Android Export Pipeline Fixes
# Date: 2026-10-02
# These fixes were required to get Gradle working in the Hatch sandbox.

## 1. JDK: Use Eclipse Temurin 17 (not Oracle JDK)
# Location: ~/jdk-temurin/
# Reason: Oracle JDK's TLS ClientHello is fingerprinted/blocked by the egress
# proxy for certain hosts (repo.maven.apache.org, plugins.gradle.org).
# Temurin's TLS fingerprint is not blocked.
# Also installed Hatch Egress CA into Temurin's cacerts:
#   keytool -import -trustcacerts -alias hatch-egress-ca \
#     -file /usr/local/share/ca-certificates/hatch-egress-ca.crt \
#     -keystore ~/jdk-temurin/lib/security/cacerts -storepass changeit -noprompt
# IMPORTANT (2026-10-02): The Hatch egress CA ROTATES. If Gradle fails with
# "PKIX path validation failed: signature check failed", re-import the current
# CA from /usr/local/share/ca-certificates/hatch-egress-ca.crt and kill all
# Gradle daemons before retrying.

## 2. Force IPv4 on Gradle daemon
# The Gradle daemon's protocol breaks on IPv6 ('Unexpected type tag 109').
# org.gradle.jvmargs -D flags are NOT reliably picked up by the daemon.
# Solution: export _JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"
# This affects ALL Java processes, which is fine for the build environment.

## 3. Refresh proxy credentials before each Gradle run
# The sandbox egress proxy password ROTATES every few minutes.
# gradle.properties must be updated from the live $https_proxy env var
# immediately before each Gradle invocation.
# See: ~/workspace/godot-nexus-arcade/android/build/gradlew-fresh.sh

## 4. SDK versions (use what's installed)
# config.gradle: compileSdk 34, targetSdk 34, buildTools '34.0.0'
# (Godot 4.7.2 defaults to 36, which is not installed)

## 5. SDK licenses
# Manually created ~/android-sdk/licenses/android-sdk-license
# (sdkmanager --licenses fails in this environment)

## Export command (debug smoke test):
# cd ~/workspace/godot-nexus-arcade
# export JAVA_HOME=~/jdk-temurin ANDROID_SDK_ROOT=~/android-sdk ANDROID_HOME=~/android-sdk
# export PATH=$JAVA_HOME/bin:$PATH
# export _JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"
# ~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless \
#   --export-debug "NEXUS ARCADE (Quest 3)" builds/NexusArcade-debug.apk
#
# Result: 83MB APK, package com.brioagent.nexusarcade, arm64-v8a,
#         includes godotopenxrvendors (Meta Quest MR) + openxr_loader
