declare module 'react-native-config' {
  export interface NativeConfig {
    VWORLD_API_KEY?: string;
    GOOGLE_VPS_API_KEY?: string;
  }

  const Config: NativeConfig;
  export default Config;
}
