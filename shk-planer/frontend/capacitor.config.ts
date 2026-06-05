import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'de.shkplaner.app',
  appName: 'SHK Planer',
  webDir: 'dist',
  // Live-Server-Modus: App lädt immer aktuelle Version von der Domain
  server: {
    url: 'https://planer.shk-innovation.de',
    cleartext: true,
    androidScheme: 'https',
  },
  android: {
    allowMixedContent: true,
    backgroundColor: '#0F1117',
  },
};

export default config;
