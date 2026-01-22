import 'package:flutter/foundation.dart';

/// Global app state notifier for refreshing UI after data changes
/// Used to notify Statistics and other screens when data is synced or cleared
class AppStateNotifier extends ChangeNotifier {
  static final AppStateNotifier _instance = AppStateNotifier._internal();
  factory AppStateNotifier() => _instance;
  AppStateNotifier._internal();

  /// Notify listeners that data has been synced
  void notifyDataSynced() {
    notifyListeners();
  }

  /// Notify listeners that database has been cleared
  void notifyDatabaseCleared() {
    notifyListeners();
  }
}
