#!/bin/bash
# SHK Planer – Android APK Build
# Einmalig auf dem VPS ausführen: bash /root/shk-planer/build-android.sh
set -e

PLANER_DIR="/root/shk-planer"
ANDROID_HOME="/opt/android-sdk"
JAVA_VERSION="17"

echo "╔══════════════════════════════════════╗"
echo "║  SHK Planer – Android APK Build      ║"
echo "╚══════════════════════════════════════╝"

# ── 1. Java JDK ────────────────────────────────────────────────────────────
echo ""
echo "▶ Java JDK $JAVA_VERSION prüfen…"
if ! java -version 2>&1 | grep -q "17\|21"; then
  echo "  Installiere OpenJDK $JAVA_VERSION…"
  apt-get update -qq
  apt-get install -y openjdk-${JAVA_VERSION}-jdk
fi
java -version 2>&1 | head -1
echo "✓ Java OK."

# ── 2. Android SDK ──────────────────────────────────────────────────────────
echo ""
echo "▶ Android SDK prüfen…"
if [ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]; then
  echo "  Lade Android Command-Line Tools herunter…"
  apt-get install -y unzip wget curl
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  cd /tmp
  # Android cmdline-tools (stable)
  wget -q "https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip" \
    -O android-cmdline-tools.zip
  unzip -q android-cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools"
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm android-cmdline-tools.zip
fi

export ANDROID_HOME="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"

# Licenses + SDK-Pakete
if [ ! -d "$ANDROID_HOME/platforms/android-34" ]; then
  echo "  Installiere Android SDK (Plattform 34, Build-Tools)…"
  yes | sdkmanager --licenses > /dev/null 2>&1 || true
  sdkmanager "platforms;android-34" "build-tools;34.0.0" "platform-tools"
fi
echo "✓ Android SDK OK."

# ── 3. Frontend deps + Capacitor init ──────────────────────────────────────
echo ""
echo "▶ Frontend-Abhängigkeiten installieren…"
cd "$PLANER_DIR/frontend"
npm install

echo ""
echo "▶ Capacitor initialisieren…"
export JAVA_HOME="$(dirname $(dirname $(readlink -f $(which java))))"
npx cap init "SHK Planer" "de.shkplaner.app" --web-dir dist 2>/dev/null || true

# ── 4. Web-Build ────────────────────────────────────────────────────────────
echo ""
echo "▶ Web-App bauen…"
npm run build

# ── 5. Android-Plattform ───────────────────────────────────────────────────
echo ""
echo "▶ Android-Plattform einrichten…"
if [ ! -d "$PLANER_DIR/frontend/android" ]; then
  npx cap add android
else
  echo "  Android-Ordner vorhanden, sync…"
fi
npx cap sync android

# ── 6. APK bauen ───────────────────────────────────────────────────────────
echo ""
echo "▶ APK bauen (Debug)…"
cd "$PLANER_DIR/frontend/android"
chmod +x gradlew
./gradlew assembleDebug --no-daemon -q

APK_SRC="$PLANER_DIR/frontend/android/app/build/outputs/apk/debug/app-debug.apk"
APK_DEST="$PLANER_DIR/frontend/dist/shk-planer.apk"
cp "$APK_SRC" "$APK_DEST"

# APK via Nginx erreichbar machen
echo ""
echo "╔══════════════════════════════════════╗"
echo "║       Android APK fertig!            ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  APK-Größe: $(du -sh "$APK_DEST" | cut -f1)"
echo ""
echo "  Download-Link:"
echo "  http://planer.shk-innovation.de/shk-planer.apk"
echo ""
echo "  Auf Android-Handy:"
echo "  1. Link öffnen"
echo "  2. APK herunterladen"
echo "  3. Tippe auf die Datei → Installieren"
echo "  (Einstellungen → Unbekannte Quellen erlauben)"
echo ""
