// lib/services/database_service.dart
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('shots.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const integerType = 'INTEGER NOT NULL';
    const realType = 'REAL NOT NULL';
    const textType = 'TEXT';

    await db.execute('''
      CREATE TABLE shots (
        id $idType,
        timestamp $integerType,
        speed $realType,
        angle $realType,
        carry $realType,
        session_id $textType,
        club_type $textType,
        notes $textType,
        created_at $integerType DEFAULT (strftime('%s', 'now') * 1000)
      )
    ''');

    await db.execute('''
      CREATE TABLE sessions (
        id $idType,
        name $textType NOT NULL,
        start_time $integerType NOT NULL,
        end_time $integerType,
        total_shots $integerType DEFAULT 0,
        average_speed $realType DEFAULT 0.0,
        best_distance $realType DEFAULT 0.0,
        notes $textType,
        created_at $integerType DEFAULT (strftime('%s', 'now') * 1000)
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_shots_timestamp ON shots(timestamp)');
    await db.execute('CREATE INDEX idx_shots_session_id ON shots(session_id)');
    await db.execute('CREATE INDEX idx_sessions_start_time ON sessions(start_time)');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns for version 2
      await db.execute('ALTER TABLE shots ADD COLUMN session_id TEXT');
      await db.execute('ALTER TABLE shots ADD COLUMN club_type TEXT');
      await db.execute('ALTER TABLE shots ADD COLUMN notes TEXT');
      
      if (oldVersion < 2) {
        await db.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            start_time INTEGER NOT NULL,
            end_time INTEGER,
            total_shots INTEGER DEFAULT 0,
            average_speed REAL DEFAULT 0.0,
            best_distance REAL DEFAULT 0.0,
            notes TEXT,
            created_at INTEGER DEFAULT (strftime('%s', 'now') * 1000)
          )
        ''');
        
        await db.execute('CREATE INDEX idx_sessions_start_time ON sessions(start_time)');
      }
    }
  }

  // Shot operations
  Future<int> insertShot(Map<String, dynamic> shot) async {
    final db = await instance.database;
    
    // Ensure timestamp is set
    shot['timestamp'] ??= DateTime.now().millisecondsSinceEpoch;
    
    try {
      final id = await db.insert('shots', shot);
      
      // Update session statistics if session_id is provided
      if (shot['session_id'] != null) {
        await _updateSessionStats(shot['session_id']);
      }
      
      return id;
    } catch (e) {
      print('Error inserting shot: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAllShots({
    int? limit,
    int? offset,
    String? sessionId,
    String? orderBy,
  }) async {
    final db = await instance.database;
    
    String query = 'SELECT * FROM shots';
    List<dynamic> whereArgs = [];
    
    if (sessionId != null) {
      query += ' WHERE session_id = ?';
      whereArgs.add(sessionId);
    }
    
    query += ' ORDER BY ${orderBy ?? 'timestamp DESC'}';
    
    if (limit != null) {
      query += ' LIMIT $limit';
      if (offset != null) {
        query += ' OFFSET $offset';
      }
    }
    
    try {
      return await db.rawQuery(query, whereArgs);
    } catch (e) {
      print('Error getting shots: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getShot(int id) async {
    final db = await instance.database;
    
    try {
      final maps = await db.query(
        'shots',
        where: 'id = ?',
        whereArgs: [id],
      );
      
      if (maps.isNotEmpty) {
        return maps.first;
      }
      return null;
    } catch (e) {
      print('Error getting shot: $e');
      return null;
    }
  }

  Future<int> updateShot(int id, Map<String, dynamic> shot) async {
    final db = await instance.database;
    
    try {
      return await db.update(
        'shots',
        shot,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print('Error updating shot: $e');
      return 0;
    }
  }

  Future<int> deleteShot(int id) async {
    final db = await instance.database;
    
    try {
      return await db.delete(
        'shots',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print('Error deleting shot: $e');
      return 0;
    }
  }

  // Session operations
  Future<int> createSession(String name, {String? notes}) async {
    final db = await instance.database;
    
    final session = {
      'name': name,
      'start_time': DateTime.now().millisecondsSinceEpoch,
      'notes': notes,
    };
    
    try {
      return await db.insert('sessions', session);
    } catch (e) {
      print('Error creating session: $e');
      rethrow;
    }
  }

  Future<int> endSession(int sessionId) async {
    final db = await instance.database;
    
    try {
      await _updateSessionStats(sessionId.toString());
      
      return await db.update(
        'sessions',
        {'end_time': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    } catch (e) {
      print('Error ending session: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getAllSessions({
    int? limit,
    int? offset,
  }) async {
    final db = await instance.database;
    
    String query = 'SELECT * FROM sessions ORDER BY start_time DESC';
    
    if (limit != null) {
      query += ' LIMIT $limit';
      if (offset != null) {
        query += ' OFFSET $offset';
      }
    }
    
    try {
      return await db.rawQuery(query);
    } catch (e) {
      print('Error getting sessions: $e');
      return [];
    }
  }

  // Statistics operations
  Future<Map<String, dynamic>> getSessionStats(String sessionId) async {
    final db = await instance.database;
    
    try {
      final result = await db.rawQuery('''
        SELECT 
          COUNT(*) as total_shots,
          AVG(speed) as average_speed,
          MAX(speed) as max_speed,
          MIN(speed) as min_speed,
          AVG(angle) as average_angle,
          MAX(carry) as best_distance,
          AVG(carry) as average_distance
        FROM shots 
        WHERE session_id = ?
      ''', [sessionId]);
      
      return result.first;
    } catch (e) {
      print('Error getting session stats: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> getOverallStats() async {
    final db = await instance.database;
    
    try {
      final result = await db.rawQuery('''
        SELECT 
          COUNT(*) as total_shots,
          AVG(speed) as average_speed,
          MAX(speed) as max_speed,
          MIN(speed) as min_speed,
          AVG(angle) as average_angle,
          MAX(carry) as best_distance,
          AVG(carry) as average_distance,
          COUNT(DISTINCT DATE(timestamp/1000, 'unixepoch')) as practice_days
        FROM shots
      ''');
      
      return result.first;
    } catch (e) {
      print('Error getting overall stats: $e');
      return {};
    }
  }

  // Private helper methods
  Future<void> _updateSessionStats(String sessionId) async {
    final stats = await getSessionStats(sessionId);
    final db = await instance.database;
    
    try {
      await db.update(
        'sessions',
        {
          'total_shots': stats['total_shots'] ?? 0,
          'average_speed': stats['average_speed'] ?? 0.0,
          'best_distance': stats['best_distance'] ?? 0.0,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    } catch (e) {
      print('Error updating session stats: $e');
    }
  }

  // Database maintenance
  Future<void> deleteOldShots({int daysToKeep = 90}) async {
    final db = await instance.database;
    final cutoffTime = DateTime.now().subtract(Duration(days: daysToKeep)).millisecondsSinceEpoch;
    
    try {
      await db.delete(
        'shots',
        where: 'timestamp < ?',
        whereArgs: [cutoffTime],
      );
    } catch (e) {
      print('Error deleting old shots: $e');
    }
  }

  Future<void> vacuum() async {
    final db = await instance.database;
    try {
      await db.execute('VACUUM');
    } catch (e) {
      print('Error vacuuming database: $e');
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}