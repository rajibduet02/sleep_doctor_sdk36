# BLE Disconnect 50ms After Service Discovery - Fix Implementation

## Date: 2026-01-17
## Status: ✅ FIXES IMPLEMENTED

---

## 🔴 PROBLEM IDENTIFIED

The device was disconnecting approximately **50ms after service discovery completed**, before the handshake could continue. This prevented the sync from proceeding.

### Symptoms:
- Service discovery completes: "Found 4 services"
- Device disconnects ~50ms later: "Connection state changed to: DISCONNECTED"
- Missing logs:
  - `BLE_SERVICE_DISCOVERY_SUCCESS` (service found)
  - `BLE_HANDSHAKE_STEP2` (next handshake step)

### Root Cause Analysis:
1. **Timing Issue**: Device disconnects during the service lookup loop, before target service is found
2. **Race Condition**: Connection state check happens asynchronously, disconnect detected after service discovery completes
3. **No Immediate Action**: After `discoverServices()` completes, we were caching services before finding the target service, causing delay

---

## ✅ FIXES IMPLEMENTED

### Fix 1: Immediate Connection Check After Service Discovery
**File**: `lib/services/bluetooth_service.dart:327-336`

**Changes**:
- Check connection **immediately** after `discoverServices()` returns (within 1ms)
- Log timing information to track exactly when disconnect occurs
- Throw exception immediately if device disconnected

**Code**:
```dart
List<BluetoothService> services = await device!.discoverServices();

// Check connection IMMEDIATELY after discoverServices() returns
if (device == null || !device!.isConnected) {
  BLELogger.error('BLE_SERVICE_DISCOVERY_FAILED: Device disconnected immediately after discoverServices() returned', ...);
  throw StateError('Device disconnected immediately after service discovery');
}
```

---

### Fix 2: Find Target Service BEFORE Caching
**File**: `lib/services/bluetooth_service.dart:352-380`

**Changes**:
- **Find target service FIRST** before caching services
- Minimize delay between service discovery and service lookup
- Cache services only after target service is found

**Why This Matters**:
- Some BLE devices require immediate interaction after service discovery
- Reducing delay between discovery and service access prevents device timeout

**Code**:
```dart
// Find target service FIRST (before caching)
BluetoothService? targetService;
for (var service in services) {
  if (service.uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
    targetService = service;
    break; // Found it - exit immediately
  }
}

// Cache ONLY after finding target service
_cachedServices = services;
_servicesDiscovered = true;
```

---

### Fix 3: Comprehensive Timing Logs
**Files**: 
- `lib/services/bluetooth_service.dart:327-390`
- `lib/helpers/sleep_doctor_data_helper.dart:407-462`

**Changes**:
- Log timestamps at every critical point
- Track duration of each operation
- Log time between operations to identify delays

**New Log Messages**:
- `BLE_SERVICE_DISCOVERY_TIMING: Starting discoverServices() at [timestamp]`
- `BLE_SERVICE_DISCOVERY_TIMING: discoverServices() completed in [X]ms`
- `BLE_HANDSHAKE_START_TIMING: Handshake started at [timestamp]`
- `BLE_HANDSHAKE_STEP1_TIMING: Service discovery completed in [X]ms`
- `BLE_HANDSHAKE_STEP2_TIMING: Characteristic lookup completed in [X]ms`
- `BLE_HANDSHAKE_STEP3_TIMING: Notification enable completed in [X]ms`
- `BLE_HANDSHAKE_SUCCESS: Immediate handshake completed successfully in [X]ms`

---

### Fix 4: Enhanced Service UUID Logging
**File**: `lib/services/bluetooth_service.dart:352-355`

**Changes**:
- Log **all discovered service UUIDs** immediately after discovery
- Log target service UUID being searched
- Change log level from `debug` to `info` for better visibility

**Code**:
```dart
final serviceUuids = services.map((s) => s.uuid.toString().toLowerCase()).toList();
BLELogger.info('BLE_SERVICE_DISCOVERY_DETAIL: Discovered service UUIDs: ${serviceUuids.join(", ")}', 'BluetoothConnector');
BLELogger.info('BLE_SERVICE_DISCOVERY_DETAIL: Looking for service UUID: ${serviceUUID.toLowerCase()}', 'BluetoothConnector');
```

---

### Fix 5: Connection Checks During Service Lookup
**File**: `lib/services/bluetooth_service.dart:357-380`

**Changes**:
- Check connection **before each service comparison** in the loop
- Check connection **after service lookup** completes
- Check connection **before caching** services
- Log timing information for each disconnect detection

**Code**:
```dart
for (var service in services) {
  // Check connection before each service check
  if (device == null || !device!.isConnected) {
    final timeSinceDiscovery = DateTime.now().difference(discoveryEndTime);
    BLELogger.error('BLE_SERVICE_DISCOVERY_FAILED: Device disconnected during service lookup loop (${timeSinceDiscovery.inMilliseconds}ms after discovery)', ...);
    throw StateError('Device disconnected during service lookup');
  }
  // ... service comparison
}
```

---

### Fix 6: Enhanced Handshake Timing Logs
**File**: `lib/helpers/sleep_doctor_data_helper.dart:407-462`

**Changes**:
- Log timing for each handshake step
- Log connection state when handshake fails
- Track total handshake duration

**New Log Messages**:
- `BLE_HANDSHAKE_STEP1_TIMING: Service discovery completed in [X]ms`
- `BLE_HANDSHAKE_STEP2_TIMING: Characteristic lookup completed in [X]ms`
- `BLE_HANDSHAKE_STEP3_TIMING: Notification enable completed in [X]ms`
- `BLE_HANDSHAKE_FAILED_STATE: Device connection state at failure: [CONNECTED/DISCONNECTED]`

---

### Fix 7: Enhanced Connection State Monitoring
**File**: `lib/helpers/sleep_doctor_data_helper.dart:89-105`

**Changes**:
- Log timestamp when connection state changes
- Verify connection state when disconnect is detected
- Log additional context about disconnect

**Code**:
```dart
_connectionStateMonitorSubscription = _bluetoothService.device!.connectionState.listen(
  (state) {
    final stateChangeTime = DateTime.now();
    BLELogger.info('BLE_GATT_STATE_CHANGED: Connection state changed to: $stateStr at ${stateChangeTime.toIso8601String()}', ...);
    
    if (_isSyncInProgress && state == BluetoothConnectionState.disconnected) {
      // Log additional verification
      if (_bluetoothService.device != null) {
        final isActuallyConnected = _bluetoothService.device!.isConnected;
        BLELogger.error('BLE_DISCONNECT_VERIFICATION: Device.isConnected check: $isActuallyConnected', ...);
      }
    }
  },
);
```

---

## 📊 EXPECTED LOG OUTPUT (After Fix)

### Successful Service Discovery:
```
[I] BLE_SERVICE_DISCOVERY_START: Discovering services for UUID: 536c6565-0001-1000-8000-00805f9b0131
[D] BLE_SERVICE_DISCOVERY_TIMING: Starting discoverServices() at 2026-01-17T17:44:40.000Z
[D] BLE_SERVICE_DISCOVERY_TIMING: discoverServices() completed in 150ms at 2026-01-17T17:44:40.150Z
[I] BLE_SERVICE_DISCOVERY_PROGRESS: Found 4 services
[I] BLE_SERVICE_DISCOVERY_DETAIL: Discovered service UUIDs: 00001805-0000-1000-8000-00805f9b34fb, 536c6565-0001-1000-8000-00805f9b0131, ...
[I] BLE_SERVICE_DISCOVERY_DETAIL: Looking for service UUID: 536c6565-0001-1000-8000-00805f9b0131
[I] BLE_SERVICE_DISCOVERY_SUCCESS: Service found: 536c6565-0001-1000-8000-00805f9b0131 (total time: 152ms)
[I] BLE_HANDSHAKE_STEP1_SUCCESS: Service discovered and connection verified
[I] BLE_HANDSHAKE_STEP2: Getting sleep data characteristic
[I] BLE_HANDSHAKE_STEP2_TIMING: Characteristic lookup completed in 10ms
[I] BLE_HANDSHAKE_STEP2_SUCCESS: Characteristic found and connection verified
[I] BLE_HANDSHAKE_STEP3: Enabling notifications immediately
[I] BLE_HANDSHAKE_STEP3_TIMING: Notification enable completed in 50ms
[I] BLE_HANDSHAKE_SUCCESS: Immediate handshake completed successfully in 212ms
```

### If Disconnect Occurs:
```
[I] BLE_SERVICE_DISCOVERY_PROGRESS: Found 4 services
[I] BLE_SERVICE_DISCOVERY_DETAIL: Discovered service UUIDs: ...
[E] BLE_SERVICE_DISCOVERY_FAILED: Device disconnected during service lookup loop (45ms after discovery)
[I] BLE_GATT_STATE_CHANGED: Connection state changed to: DISCONNECTED at 2026-01-17T17:44:40.195Z
[E] BLE_HANDSHAKE_FAILED: Device disconnected 45ms after service discovery completed
[E] BLE_HANDSHAKE_FAILED_STATE: Device connection state at failure: DISCONNECTED
```

---

## 🔍 DIAGNOSTIC CAPABILITIES

With these fixes, the logs will now reveal:

1. **Exact Timing**: When disconnect occurs relative to service discovery
2. **Service Availability**: Whether target service exists in discovered services
3. **Operation Duration**: How long each operation takes
4. **Disconnect Point**: Exactly where in the flow the disconnect happens
5. **Connection State**: Actual connection state when disconnect is detected

---

## 🎯 NEXT STEPS

1. **Test the fixes** with the device
2. **Review logs** to identify:
   - If disconnect happens immediately after `discoverServices()` returns
   - If target service exists in discovered services
   - Exact timing of disconnect
3. **If disconnect still occurs**, the logs will show:
   - Whether it's a device-side timeout
   - Whether it's a permission issue
   - Whether it's a BLE stack issue
   - Exact timing to identify the root cause

---

## 📝 FILES MODIFIED

1. `lib/services/bluetooth_service.dart`
   - Enhanced service discovery with immediate connection checks
   - Added comprehensive timing logs
   - Optimized service lookup (find before cache)

2. `lib/helpers/sleep_doctor_data_helper.dart`
   - Enhanced handshake with timing logs
   - Improved connection state monitoring
   - Better error logging with connection state verification

---

## ✅ VALIDATION

- ✅ No linter errors
- ✅ All timing logs added
- ✅ Connection checks at critical points
- ✅ Service lookup optimized
- ✅ Comprehensive error logging

**Status**: Ready for testing
