/// Centralized BLE configuration constants
/// Replaces hardcoded magic values throughout the codebase
class BLEConfig {
  // Scan configuration
  static const Duration scanTimeout = Duration(seconds: 15);
  static const Duration scanOverallTimeout = Duration(seconds: 30); // Increased from 20s
  static const int maxScanRetries = 3;
  
  // Connection configuration
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const int maxConnectionRetries = 3;
  static const Duration connectionRetryDelay = Duration(seconds: 2);
  
  // Read configuration
  static const Duration readTimeout = Duration(seconds: 120);
  static const Duration keepAliveInterval = Duration(seconds: 30); // Ping every 30s during long reads
  static const int maxReadRetries = 2;
  
  // Button press wait configuration
  static const Duration buttonPressWaitTimeout = Duration(seconds: 120); // Max wait time for button press
  
  // Device names
  static const List<String> supportedDeviceNames = [
    "SleepDoctor",
    "SD Consumer 1.0"
  ];
  
  // Service UUIDs
  static const String ctsServiceUUID = "00001805-0000-1000-8000-00805f9b34fb";
  static const String currentTimeCharacteristicUUID = "00002A2B-0000-1000-8000-00805f9b34fb";
  static const String sdsServiceUUID = "536C6565-0001-1000-8000-00805f9b0131";
  static const String sleepDoctorCharacteristicUUID = "536C6565-0001-2000-8000-00805f9b0131";
  
  // Android-specific
  static const int androidMinSdkForNewPermissions = 31; // Android 12
}
