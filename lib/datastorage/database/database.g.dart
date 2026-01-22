// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// **************************************************************************
// FloorGenerator
// **************************************************************************

// ignore: avoid_classes_with_only_static_members
class $FloorSleepDoctorDatabase {
  /// Creates a database builder for a persistent database.
  /// Once a database is built, you should keep a reference to it and re-use it.
  static _$SleepDoctorDatabaseBuilder databaseBuilder(String name) =>
      _$SleepDoctorDatabaseBuilder(name);

  /// Creates a database builder for an in memory database.
  /// Information stored in an in memory database disappears when the process is killed.
  /// Once a database is built, you should keep a reference to it and re-use it.
  static _$SleepDoctorDatabaseBuilder inMemoryDatabaseBuilder() =>
      _$SleepDoctorDatabaseBuilder(null);
}

class _$SleepDoctorDatabaseBuilder {
  _$SleepDoctorDatabaseBuilder(this.name);

  final String? name;

  final List<Migration> _migrations = [];

  Callback? _callback;

  /// Adds migrations to the builder.
  _$SleepDoctorDatabaseBuilder addMigrations(List<Migration> migrations) {
    _migrations.addAll(migrations);
    return this;
  }

  /// Adds a database [Callback] to the builder.
  _$SleepDoctorDatabaseBuilder addCallback(Callback callback) {
    _callback = callback;
    return this;
  }

  /// Creates the database and initializes it.
  Future<SleepDoctorDatabase> build() async {
    final path = name != null
        ? await sqfliteDatabaseFactory.getDatabasePath(name!)
        : ':memory:';
    final database = _$SleepDoctorDatabase();
    database.database = await database.open(
      path,
      _migrations,
      _callback,
    );
    return database;
  }
}

class _$SleepDoctorDatabase extends SleepDoctorDatabase {
  _$SleepDoctorDatabase([StreamController<String>? listener]) {
    changeListener = listener ?? StreamController<String>.broadcast();
  }

  SleepDoctorDataDao? _sleepDataDaoInstance;

  Future<sqflite.Database> open(
    String path,
    List<Migration> migrations, [
    Callback? callback,
  ]) async {
    final databaseOptions = sqflite.OpenDatabaseOptions(
      version: 1,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onOpen: (database) async {
        await callback?.onOpen?.call(database);
      },
      onUpgrade: (database, startVersion, endVersion) async {
        await MigrationAdapter.runMigrations(
            database, startVersion, endVersion, migrations);

        await callback?.onUpgrade?.call(database, startVersion, endVersion);
      },
      onCreate: (database, version) async {
        await database.execute(
            'CREATE TABLE IF NOT EXISTS `sleep_data` (`fromTime` INTEGER NOT NULL, `toTime` INTEGER NOT NULL, `mode` INTEGER NOT NULL, `stimulation` INTEGER NOT NULL, `orientation` INTEGER NOT NULL, `sleep_phase` INTEGER NOT NULL, PRIMARY KEY (`fromTime`))');

        await callback?.onCreate?.call(database, version);
      },
    );
    return sqfliteDatabaseFactory.openDatabase(path, options: databaseOptions);
  }

  @override
  SleepDoctorDataDao get sleepDataDao {
    return _sleepDataDaoInstance ??=
        _$SleepDoctorDataDao(database, changeListener);
  }
}

class _$SleepDoctorDataDao extends SleepDoctorDataDao {
  _$SleepDoctorDataDao(
    this.database,
    this.changeListener,
  )   : _queryAdapter = QueryAdapter(database),
        _sleepDoctorDataInsertionAdapter = InsertionAdapter(
            database,
            'sleep_data',
            (SleepDoctorData item) => <String, Object?>{
                  'fromTime': _dateTimeConverter.encode(item.fromTime),
                  'toTime': _dateTimeConverter.encode(item.toTime),
                  'mode': item.mode,
                  'stimulation': item.stimulation ? 1 : 0,
                  'orientation': item.orientation,
                  'sleep_phase': item.sleepPhase
                });

  final sqflite.DatabaseExecutor database;

  final StreamController<String> changeListener;

  final QueryAdapter _queryAdapter;

  final InsertionAdapter<SleepDoctorData> _sleepDoctorDataInsertionAdapter;

  @override
  Future<List<SleepDoctorData>> getSleepData() async {
    return _queryAdapter.queryList('SELECT * FROM sleep_data',
        mapper: (Map<String, Object?> row) => SleepDoctorData(
            mode: row['mode'] as int,
            stimulation: (row['stimulation'] as int) != 0,
            orientation: row['orientation'] as int,
            sleepPhase: row['sleep_phase'] as int,
            fromTime: _dateTimeConverter.decode(row['fromTime'] as int),
            toTime: _dateTimeConverter.decode(row['toTime'] as int)));
  }

  @override
  Future<List<SleepDoctorData>> getSleepDataSince(DateTime dateTime) async {
    return _queryAdapter.queryList(
        'SELECT * FROM sleep_data WHERE fromTime >= ?1',
        mapper: (Map<String, Object?> row) => SleepDoctorData(
            mode: row['mode'] as int,
            stimulation: (row['stimulation'] as int) != 0,
            orientation: row['orientation'] as int,
            sleepPhase: row['sleep_phase'] as int,
            fromTime: _dateTimeConverter.decode(row['fromTime'] as int),
            toTime: _dateTimeConverter.decode(row['toTime'] as int)),
        arguments: [_dateTimeConverter.encode(dateTime)]);
  }

  @override
  Future<void> deleteAllSleepData() async {
    await _queryAdapter.queryNoReturn('DELETE FROM sleep_data');
  }

  @override
  Future<void> insertSleepData(SleepDoctorData data) async {
    await _sleepDoctorDataInsertionAdapter.insert(
        data, OnConflictStrategy.replace);
  }
}

// ignore_for_file: unused_element
final _dateTimeConverter = DateTimeConverter();
