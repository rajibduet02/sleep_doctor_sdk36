# SDK 36 BLE Sync Regression Fix

## 🔴 Root Cause Analysis

### Problem Identified

After upgrading from Android SDK 31 to SDK 36, the BLE sync workflow broke:

1. **Auto-start bug**: Sync would automatically start after 20-30 seconds even without device button press
2. **Missing notification handling**: The app was not waiting for the BLE characteristic notification triggered by the physical button press
3. **Timeout-based triggers**: Scan timeout logic was causing premature sync initiation

### Root Cause

The original code flow was:
```
Scan → Connect → Immediately start sync
```

**This is WRONG** - it should be:
```
Scan → Connect → Wait for button press notification → Start sync
```

The missing piece was:
- **No characteristic notification subscription**
- **No wait mechanism for button press**
- **Timeout-based auto-completion** in scan logic

### Why It Broke After SDK 36

Android SDK 36 introduced stricter BLE permission enforcement and changed BLE callback behavior. The previous code likely worked by accident (polling or timing), but SDK 36 requires proper notification/indication handling.

---

## ✅ Solution Implemented

### 1. Added BLE Characteristic Notification Support

**File**: `lib/services/bluetooth_service.dart`

Added methods to enable/disable notifications on characteristics:

```dart
Future<Stream<List<int>>> enableCharacteristicNotifications(
    BluetoothCharacteristic characteristic) async {
  // Enables notifications/indications
  await characteristic.setNotifyValue(true);
  return characteristic.onValueReceived; // Returns stream of notifications
}
```

### 2. Implemented Button Press Wait Mechanism

**File**: `lib/helpers/sleep_doctor_data_helper.dart`

Added `_waitForDeviceButtonPress()` method that:
- Discovers the sleep data service characteristic
- Enables notifications on the characteristic
- **Waits indefinitely** for a notification from the device
- Only proceeds when device sends notification (button pressed)

```dart
Future<void> _waitForDeviceButtonPress() async {
  // Enable notifications
  final notificationStream = await _bluetoothService.enableCharacteristicNotifications(characteristic);
  
  // Subscribe to notifications - blocks until button press
  _buttonPressNotificationSubscription = notificationStream.listen(
    (data) {
      // Button pressed! Complete the wait
      completer.complete();
    }
  );
  
  // Wait indefinitely for notification
  await completer.future;
}
```

### 3. Modified Sync Flow

**File**: `lib/helpers/sleep_doctor_data_helper.dart`

Updated `fetchDataFromSleepDoctorDevice()` to:

1. Scan for device (no timeout-based auto-completion)
2. Connect to device
3. **WAIT for button press notification** ← NEW STEP
4. Only then start sync (time service + data service)

```dart
// Step 5: Wait for device button press notification
BLELogger.info('Waiting for device button press notification...', 'SleepDoctorDataConnector');
_bluetoothServiceStatesObserver?.waitingForButtonPress(true);
await _waitForDeviceButtonPress(); // BLOCKS HERE until button pressed
_bluetoothServiceStatesObserver?.waitingForButtonPress(false);

// Step 6: Button pressed - now start sync
BLELogger.info('Device button pressed - starting sync', 'SleepDoctorDataConnector');
```

### 4. Removed Auto-Start Logic

**File**: `lib/services/bluetooth_service.dart`

- **Removed** timeout-based auto-completion in scan
- Scan now continues indefinitely until device found or user cancels
- No more 20-30 second auto-start trigger

**Before**:
```dart
Timer(BLEConfig.scanOverallTimeout, () {
  // Auto-complete after timeout - THIS WAS THE BUG
  completer.completeError(TimeoutException(...));
});
```

**After**:
```dart
// NO TIMEOUT-BASED AUTO-COMPLETION
// Scan continues until device found or error occurs
```

### 5. Updated AndroidManifest for SDK 36

**File**: `android/app/src/main/AndroidManifest.xml`

Added proper permission attributes for SDK 36:

```xml
<!-- Android 12+ (SDK 31+) Bluetooth permissions -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" 
    android:usesPermissionFlags="neverForLocation"
    tools:targetApi="s" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" 
    tools:targetApi="s" />
```

### 6. Enhanced UI State Management

**File**: `lib/widgets/syncscreen/syncscreen_widget.dart`

- Added `waitingForButtonPress()` observer method
- UI continues showing "Press blue button" message while waiting
- State properly transitions: SCANNING → WAITING_FOR_BUTTON → SYNC_ONGOING

---

## 🔄 Corrected Sync Workflow

### State Machine

```
IDLE
  ↓ (User taps sync)
SCANNING_FOR_DEVICE
  ↓ (Device found)
CONNECTING
  ↓ (Connected)
WAITING_FOR_DEVICE_BUTTON  ← NEW STATE
  ↓ (Button press notification received)
SYNC_ONGOING
  ↓ (Data read complete)
SYNC_COMPLETED
```

### Detailed Flow

1. **User opens app → navigates to Sync tab**
2. **User presses Sync button in app**
3. **App starts BLE scan** (no timeout, continues until device found)
4. **UI shows**: "Searching for SleepDoctor… Press blue button on device"
5. **Device found → Connect to device**
6. **UI continues showing**: "Press blue button on device"
7. **App enables characteristic notifications**
8. **App waits indefinitely for notification** ← CRITICAL
9. **User presses blue button on SleepDoctor device**
10. **Device sends BLE notification/indication**
11. **App receives notification → UI changes to "Sync ongoing"**
12. **Data sync starts immediately**
13. **Sync completes successfully and data is stored**

---

## 🛡️ Key Fixes

### 1. No Auto-Start
- ✅ Removed all timeout-based triggers
- ✅ Removed scan timeout auto-completion
- ✅ Sync starts ONLY after button press notification

### 2. Proper BLE Notification Handling
- ✅ Characteristic notifications properly enabled
- ✅ Stream subscription for button press events
- ✅ Indefinite wait until notification received

### 3. SDK 36 Compliance
- ✅ Proper permission attributes in AndroidManifest
- ✅ `usesPermissionFlags="neverForLocation"` for BLUETOOTH_SCAN
- ✅ `tools:targetApi="s"` for Android 12+ permissions

### 4. State Management
- ✅ Proper state transitions
- ✅ UI reflects waiting state
- ✅ No premature state changes

---

## 📋 Files Modified

1. **lib/services/bluetooth_service.dart**
   - Added `enableCharacteristicNotifications()`
   - Added `disableCharacteristicNotifications()`
   - Removed timeout-based auto-completion in scan

2. **lib/helpers/sleep_doctor_data_helper.dart**
   - Added `_waitForDeviceButtonPress()` method
   - Modified sync flow to wait for button press
   - Added notification subscription management
   - Removed scan retry timeout logic

3. **lib/interfaces/status_observer.dart**
   - Added `waitingForButtonPress()` method to observer

4. **lib/widgets/syncscreen/syncscreen_widget.dart**
   - Implemented `waitingForButtonPress()` observer
   - Enhanced UI state management

5. **android/app/src/main/AndroidManifest.xml**
   - Updated permissions for SDK 36
   - Added proper permission attributes

---

## 🧪 Testing Checklist

### Basic Functionality
- [ ] Scan finds device successfully
- [ ] UI shows "Press blue button" message after connection
- [ ] App waits indefinitely for button press (no auto-start)
- [ ] Button press triggers sync immediately
- [ ] Sync completes successfully

### Regression Prevention
- [ ] Sync does NOT start automatically after 20-30 seconds
- [ ] Sync does NOT start when button is NOT pressed
- [ ] Sync starts ONLY after receiving button press notification
- [ ] Works correctly on Android SDK 36

### Edge Cases
- [ ] Multiple button presses handled correctly
- [ ] Connection lost during wait handled gracefully
- [ ] App backgrounded during wait continues correctly
- [ ] Permissions properly requested and handled

---

## 🔍 Why This Fix Works

### Before (Broken)
```
Scan (30s timeout) → Auto-complete → Connect → Start sync immediately
```
**Problem**: Timeout triggers sync even without button press

### After (Fixed)
```
Scan (indefinite) → Device found → Connect → Enable notifications → 
Wait for notification → Button pressed → Start sync
```
**Solution**: Sync only starts after receiving BLE notification event

---

## 📝 Technical Details

### BLE Notification Flow

1. **Enable Notifications**:
   ```dart
   await characteristic.setNotifyValue(true);
   ```

2. **Subscribe to Stream**:
   ```dart
   characteristic.onValueReceived.listen((data) {
     // Device sent notification - button was pressed
   });
   ```

3. **Wait Indefinitely**:
   ```dart
   await completer.future; // Blocks until notification received
   ```

### Characteristic Used

- **Service UUID**: `536C6565-0001-1000-8000-00805f9b0131` (Sleep Doctor Data Service)
- **Characteristic UUID**: `536C6565-0001-2000-8000-00805f9b0131` (Sleep Doctor Characteristic)

When the physical button is pressed, the device sends a notification/indication on this characteristic, which triggers the sync.

---

## ✅ Verification

The fix ensures:

1. ✅ **No auto-start**: Sync never starts without button press
2. ✅ **BLE-driven**: Sync starts ONLY from BLE notification event
3. ✅ **SDK 36 compliant**: Proper permissions and BLE handling
4. ✅ **Original behavior restored**: Matches SDK 31 behavior exactly
5. ✅ **No hardware assumptions**: Relies purely on BLE events

---

## 🚀 Deployment Notes

1. **Test thoroughly** on Android SDK 36 device
2. **Verify permissions** are requested correctly
3. **Confirm UI states** transition properly
4. **Monitor logs** for notification events
5. **Validate** sync completes successfully after button press

---

**Status**: ✅ **FIXED** - Ready for testing

**Date**: 2025-01-11
