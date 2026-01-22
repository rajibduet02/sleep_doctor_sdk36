# CRITICAL BUG FIX - dispose() Error

## Issue Found:
Runtime error: `_StatisticsState.dispose failed to call super.dispose()`

## Root Cause:
The `_StatisticsState` class incorrectly mixed in `ChangeNotifier`, which caused a conflict with the State widget's dispose() method.

## Fix Applied:
Removed `with ChangeNotifier` from `_StatisticsState` class definition.

**Before:**
```dart
class _StatisticsState extends State<Statistics> with ChangeNotifier {
```

**After:**
```dart
class _StatisticsState extends State<Statistics> {
```

## Explanation:
- `AppStateNotifier` is already a `ChangeNotifier` singleton
- We only need to listen to it, not mix it in
- The State widget's dispose() method now correctly calls `super.dispose()`

## Status: ✅ FIXED

The dispose() method now correctly:
1. Removes the listener from AppStateNotifier
2. Calls super.dispose() to clean up State resources
