# SleepDoctor Flutter App - Project Analysis

## 📋 Project Overview

**SleepDoctor** is a Flutter mobile application that connects to a Bluetooth Low Energy (BLE) sleep monitoring device to sync, store, and visualize sleep data. The app tracks various sleep metrics including sleep phases, body orientation, stimulation states, and device modes.

**Bundle ID**: `de.iptasys.sleepdoctor`  
**Version**: 1.1.0+16  
**Platform**: Android (iOS support in structure but not fully implemented)

---

## 🏗️ Architecture Overview

### High-Level Flow

```
User Interface (Widgets)
    ↓
Repository Layer (Business Logic)
    ↓
Data Connector (BLE Communication)
    ↓
Bluetooth Service (Hardware Abstraction)
    ↓
SleepDoctor BLE Device
```

### Data Flow

1. **Sync Process**:
   - User taps sync button → Permissions check → Battery optimization request
   - Scan for device → Connect → Read time service → Sync time
   - Read sleep data service (recursive until E_ETX signal)
   - Parse binary data → Store in local database
   - Update UI with statistics and history

2. **Data Storage**:
   - Local SQLite database using Floor ORM
   - Stores sleep data records with timestamps
   - Supports querying by date ranges

3. **Data Visualization**:
   - Statistics screen with charts (fl_chart library)
   - History screen with chronological data
   - Pie charts for sleep phase distribution

---

## 📁 Project Structure

### Core Directories

```
lib/
├── main.dart                          # App entry point, theme configuration
├── datastorage/                       # Database layer
│   ├── database/                      # Floor ORM database definitions
│   └── local_data_store.dart          # Data storage abstraction
├── helpers/                           # Data processing utilities
│   ├── bluetooth_data_helper.dart     # Binary data parsing
│   └── sleep_doctor_data_helper.dart  # BLE sync orchestration
├── interfaces/                        # Contracts/Protocols
│   ├── parsable.dart
│   ├── routable.dart
│   └── status_observer.dart           # Observer pattern for status updates
├── models/                            # Data models
│   ├── bluetooth_device_info.dart
│   ├── bluetooth_signals.dart         # BLE protocol signals
│   └── sleepdoctor/                   # Sleep data models
├── repositories/                      # Business logic layer
│   ├── sleep_doctor_repository.dart   # Main repository (singleton)
│   └── sleep_doctor_repository_singleton_global.dart
├── services/                          # External service integrations
│   └── bluetooth_service.dart         # BLE hardware abstraction
├── utils/                             # Utility classes
│   ├── app_config.dart                # App configuration
│   ├── app_lifecycle_manager.dart     # Lifecycle state management
│   ├── app_state_notifier.dart        # State change notifications
│   ├── battery_optimization_handler.dart  # Android battery optimization
│   ├── ble_config.dart                # BLE configuration constants
│   ├── ble_logger.dart                # Structured logging
│   └── layout_util.dart               # UI utilities
└── widgets/                           # UI components
    ├── appBarMenu/                    # Settings and info screens
    ├── base/                          # Base widget classes
    ├── historie/                      # History screen
    ├── startscreen/                   # Main navigation screen
    ├── statistics/                   # Statistics and charts
    └── syncscreen/                    # Sync operation screen
```

---

## 🔧 Key Components

### 1. **Bluetooth Service** (`lib/services/bluetooth_service.dart`)

**Purpose**: Low-level BLE hardware abstraction

**Key Features**:
- Device scanning with retry logic (up to 3 retries)
- Connection management with timeout handling
- Service and characteristic discovery
- Connection state monitoring
- Stream-based state management

**Key Methods**:
- `scanForDevicesWith()` - Scans for devices matching names
- `connectToDevice()` - Connects with retry logic
- `readServiceFromDevice()` - Discovers BLE services
- `readCharacteristicFrom()` - Finds specific characteristics

**Configuration**:
- Scan timeout: 15s
- Overall scan timeout: 30s
- Connection timeout: 10s
- Max retries: 3

---

### 2. **Sleep Doctor Data Connector** (`lib/helpers/sleep_doctor_data_helper.dart`)

**Purpose**: Orchestrates the complete sync process

**Key Features**:
- Coordinates scanning, connection, and data reading
- Time synchronization with device
- Recursive data reading until E_ETX signal
- Connection state monitoring during sync
- Keep-alive timer for long reads (30s intervals)
- Error handling and retry logic

**Sync Process**:
1. Disconnect any existing device
2. Scan for device (with retries)
3. Connect to device
4. Start connection monitoring
5. Read time service → Sync phone time to device
6. Read sleep data service (recursive, up to 120s)
7. Parse binary data
8. Return structured data

**Safety Features**:
- Prevents duplicate syncs
- Monitors connection state throughout
- Stops sync gracefully on disconnection
- Keep-alive pings during long reads

---

### 3. **Repository** (`lib/repositories/sleep_doctor_repository.dart`)

**Purpose**: Business logic layer, coordinates data flow

**Key Features**:
- Singleton pattern for global access
- Coordinates BLE sync and database storage
- Status observer pattern for UI updates
- Database operations (CRUD)

**Key Methods**:
- `fetchDataFromSleepDoctorDevice()` - Main sync method
- `readAllSleepDoctorData()` - Query database
- `clearSleepDoctorDatabase()` - Clear all data

---

### 4. **Database Layer** (`lib/datastorage/database/`)

**Purpose**: Local data persistence

**Technology**: Floor ORM (SQLite wrapper)

**Data Model**: `SleepDoctorData`
- Primary key: `fromTime` (DateTime)
- Fields: `toTime`, `mode`, `stimulation`, `orientation`, `sleepPhase`

**Operations**:
- Insert sleep data records
- Query all data
- Query data since specific date
- Clear database

---

### 5. **UI Components**

#### **Start Screen** (`lib/widgets/startscreen/startscreen_widget.dart`)
- Main navigation hub
- Bottom navigation: Statistics, History, Sync
- App bar menu: Settings, Info

#### **Sync Screen** (`lib/widgets/syncscreen/syncscreen_widget.dart`)
- Sync button and status display
- Bluetooth state indicator
- Permission handling (Android 12+ support)
- Battery optimization request
- Real-time sync status updates

#### **Statistics Screen** (`lib/widgets/statistics/`)
- Visualizes sleep data with charts
- Uses `fl_chart` library
- Displays sleep phases, orientations, etc.

#### **History Screen** (`lib/widgets/historie/`)
- Chronological list of sleep data
- Date-based filtering

---

## 🔐 BLE Protocol

### Device Communication

**Supported Device Names**:
- "SleepDoctor"
- "SD Consumer 1.0"

**BLE Services**:
1. **Current Time Service (CTS)**
   - UUID: `00001805-0000-1000-8000-00805f9b34fb`
   - Characteristic: `00002A2B-0000-1000-8000-00805f9b0131`
   - Purpose: Time synchronization

2. **Sleep Doctor Data Service (SDS)**
   - UUID: `536C6565-0001-1000-8000-00805f9b0131`
   - Characteristic: `536C6565-0001-2000-8000-00805f9b0131`
   - Purpose: Sleep data transmission

### Protocol Signals

- `E_SOH` (0x01): Start of Heading (header data)
- `E_STX` (0x02): Start of Text
- `E_ETX` (0x03): End of Text (sync completion)
- `E_ACK` (0x06): Acknowledge
- `C` (0x43): Clear signal

### Data Format

**Header Packet** (E_SOH):
- Bootloader version
- Firmware version
- Start datetime
- Battery level
- Number of elements

**Data Packets**:
- Binary encoded sleep data
- Each entry: 1 byte with bit flags
  - Bits 7-6: Mode (TIME, SIDLE, APNOE, SNORE)
  - Bits 5-4: Sleep phase (DEEP, LIGHT, REM, AWAKE)
  - Bits 3-1: Orientation (STOMACH, BACK, LEFT, RIGHT, SITTING, WALK, HEADSTAND)
  - Bit 0: Stimulation (ON/OFF)

**Time Encoding**:
- When mode = TIME: Lower 6 bits = repeat count (×10 seconds)

---

## 🛡️ Stability & Reliability Features

### Recent Improvements (2025-01-06)

The app underwent significant stability improvements:

1. **App Lifecycle Management**
   - `AppLifecycleManager` tracks app state
   - Prevents sync interruption awareness
   - Logs state transitions

2. **Battery Optimization Handling**
   - Requests exemption on Android
   - Prevents system from killing BLE operations
   - Platform-specific handling

3. **Connection Monitoring**
   - Real-time connection state tracking
   - Automatic sync stop on disconnection
   - Prevents silent failures

4. **Retry Logic**
   - Scan retries: 3 attempts
   - Connection retries: 3 attempts with delays
   - Graceful failure handling

5. **Keep-Alive Mechanism**
   - Timer-based pings every 30s during long reads
   - Prevents connection timeout (120s reads)
   - Connection state verification

6. **Structured Logging**
   - `BLELogger` with log levels (INFO, WARNING, ERROR, DEBUG)
   - Context tags for each component
   - Replaces all `print()` statements

7. **Async/Await Refactoring**
   - Removed nested `.then()` chains
   - Proper error propagation
   - Better error handling

8. **Permission Handling**
   - Re-checks permissions before every sync
   - Android 12+ specific permissions (bluetooth, bluetoothConnect, bluetoothScan)
   - User-friendly error messages

---

## 📊 Data Models

### SleepDoctorData

```dart
@Entity(tableName: 'sleep_data')
class SleepDoctorData {
  @PrimaryKey()
  DateTime fromTime;
  
  DateTime toTime;
  int mode;              // Device mode
  bool stimulation;       // Stimulation on/off
  int orientation;        // Body position
  int sleepPhase;         // Sleep phase (DEEP, LIGHT, REM, AWAKE)
}
```

### Sleep Data Types

- **MODE**: Device operating mode (TIME, SIDLE, APNOE, SNORE)
- **ORIENTATION**: Body position (7 positions)
- **STIMULATION**: Stimulation state (ON/OFF)
- **SLEEP_PHASE**: Sleep stage (DEEP, LIGHT, REM, AWAKE)

---

## 🌐 Localization

**Supported Languages**:
- English (en) - Default
- German (de)
- French (fr)

**Technology**: `easy_localization` package

**Translation Files**: `assets/translations/`

---

## 🔌 Dependencies

### Core Dependencies

- **flutter_blue_plus** (^1.31.0): BLE communication
- **floor** (^1.5.0): SQLite ORM
- **fl_chart** (^0.66.0): Chart visualization
- **easy_localization** (^3.0.3): Internationalization
- **permission_handler** (^11.0.0): Android permissions
- **device_info_plus** (^9.1.0): Device information
- **shared_preferences** (^2.2.0): Key-value storage

### Development Dependencies

- **floor_generator**: Database code generation
- **build_runner**: Code generation runner

---

## ⚙️ Configuration

### BLE Configuration (`lib/utils/ble_config.dart`)

All BLE-related constants centralized:

```dart
- Scan timeout: 15s
- Scan overall timeout: 30s
- Max scan retries: 3
- Connection timeout: 10s
- Max connection retries: 3
- Read timeout: 120s
- Keep-alive interval: 30s
- Supported device names: ["SleepDoctor", "SD Consumer 1.0"]
```

### App Configuration (`lib/utils/app_config.dart`)

- App title: "SleepDoctor"
- Primary color: RGB(41, 98, 255)
- Secondary color: RGB(255, 198, 41)
- Font: Roboto (all weights)

---

## 🚀 Build & Deployment

### Android Build

1. Add `android/key.properties` (not in git)
2. Update version in `pubspec.yaml`
3. Build APK: `flutter build apk --release`
4. Output: `build/app/outputs/apk/release/`

### Release Bundle

- AAB file: `android/app/release/app-release.aab`

---

## 🐛 Known Limitations

1. **Foreground Service**: Not implemented (documented but not coded)
   - Impact: Android may kill sync if backgrounded for extended periods
   - Mitigation: Battery optimization exemption + lifecycle handling

2. **iOS Background**: Limited BLE operations when backgrounded
   - iOS has stricter background limits than Android

3. **Dead Code**: Some unused code remains (e.g., `LocalDataStore`)

---

## 📝 Key Design Patterns

1. **Singleton Pattern**: Repository, AppLifecycleManager
2. **Observer Pattern**: StatusObserver, BluetoothServiceStatesObserver
3. **Repository Pattern**: Data access abstraction
4. **Service Layer**: Hardware abstraction
5. **Factory Pattern**: Model creation

---

## 🔍 Code Quality

### Strengths

✅ Clean separation of concerns  
✅ Comprehensive error handling  
✅ Structured logging  
✅ Retry logic for reliability  
✅ Connection state monitoring  
✅ Lifecycle awareness  
✅ Battery optimization handling  
✅ Async/await throughout  
✅ Centralized configuration  

### Areas for Improvement

⚠️ Foreground service not implemented  
⚠️ Some dead code remains  
⚠️ Limited iOS testing  
⚠️ No unit tests visible  

---

## 📚 Documentation Files

- `BLE_ARCHITECTURE_AUDIT.md`: Initial architecture audit
- `BLE_STABILITY_FIXES_SUMMARY.md`: Stability improvements summary
- `FOREGROUND_SERVICE_REQUIREMENT.md`: Foreground service guide
- `COMPLETE_FIXES_SUMMARY.md`: Complete fixes documentation
- `CRITICAL_BUG_FIX.md`: Critical bug fixes
- `FUNCTIONAL_FIXES_SUMMARY.md`: Functional improvements

---

## 🎯 Main Use Cases

1. **Sync Sleep Data**
   - User opens app → Navigates to Sync screen
   - Taps sync button → App scans for device
   - Connects → Syncs time → Reads sleep data
   - Stores in database → Updates UI

2. **View Statistics**
   - User navigates to Statistics screen
   - App queries database
   - Displays charts and visualizations

3. **View History**
   - User navigates to History screen
   - App displays chronological sleep data
   - Filterable by date

4. **Clear Data**
   - User accesses Settings
   - Clears database
   - UI updates accordingly

---

## 🔄 Data Synchronization Flow

```
1. User initiates sync
   ↓
2. Check permissions (re-check every time)
   ↓
3. Request battery optimization exemption (Android)
   ↓
4. Disconnect any existing device
   ↓
5. Scan for device (with retries)
   ↓
6. Connect to device (with retries)
   ↓
7. Start connection state monitoring
   ↓
8. Read time service → Get device time
   ↓
9. Write phone time to device (sync)
   ↓
10. Read sleep data service
    - Start keep-alive timer
    - Recursive read until E_ETX signal
    - Monitor connection state
    ↓
11. Parse binary data
    - Extract header (E_SOH)
    - Parse data packets
    - Calculate timestamps
    ↓
12. Store in database
    ↓
13. Update UI
    ↓
14. Clear device data (optional)
```

---

## 🎨 UI/UX

### Theme

- **Primary Color**: Blue (RGB: 41, 98, 255)
- **Secondary Color**: Yellow (RGB: 255, 198, 41)
- **Font**: Roboto (Regular, Bold, Italic)
- **Design**: Material Design

### Navigation

- Bottom navigation: Statistics, History, Sync
- App bar menu: Settings, Info
- Single-screen navigation (no deep routing)

### User Feedback

- Toast messages for errors
- Status indicators (working, success, failure)
- Bluetooth state icon
- Progress indicators during sync

---

## 🔐 Security & Privacy

- Local data storage only (no cloud sync)
- Secure storage for sensitive data (`flutter_secure_storage`)
- No network communication
- All data stored on device

---

## 📱 Platform Support

### Android

✅ Fully supported  
✅ Battery optimization handling  
✅ Permission handling (including Android 12+)  
✅ Foreground service capability (not implemented)  

### iOS

⚠️ Structure exists but limited testing  
⚠️ Background BLE limitations  
⚠️ Different permission model  

---

## 🧪 Testing Considerations

### Test Scenarios

1. **Basic Functionality**
   - Device scan and connection
   - Time synchronization
   - Data reading and parsing
   - Database storage

2. **Reliability**
   - Sync with screen off
   - Sync when app backgrounded
   - Temporary Bluetooth disconnection
   - Retry logic verification
   - Permission revocation handling

3. **Edge Cases**
   - Multiple rapid sync attempts
   - Poor Bluetooth signal
   - Low battery device
   - Battery optimization enabled/disabled

---

## 📈 Performance Characteristics

- **Scan Timeout**: 15s per attempt, 30s overall
- **Connection Timeout**: 10s
- **Read Timeout**: 120s (for large datasets)
- **Keep-Alive Interval**: 30s
- **Max Retries**: 3 attempts for scan/connection

---

## 🎓 Learning Points

1. **BLE Communication**: Complex state management required
2. **Android Background**: Requires special handling (foreground service, battery optimization)
3. **Error Handling**: Critical for reliability (retries, monitoring)
4. **Lifecycle Management**: Essential for background operations
5. **Binary Protocol**: Custom parsing required for device communication

---

## 🔮 Future Enhancements (Potential)

1. Implement foreground service for Android
2. Add unit and integration tests
3. Improve iOS support
4. Add data export functionality
5. Cloud sync capability
6. Enhanced analytics and insights
7. Device firmware update capability
8. Multi-device support

---

**Last Updated**: 2025-01-11  
**Analysis Version**: 1.0
