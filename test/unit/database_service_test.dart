// test/unit/database_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker/services/database_service.dart';
import '../helpers/test_data_generator.dart';
import '../helpers/mock_services.dart';

void main() {
  group('DatabaseService', () {
    late MockDatabaseService databaseService;
    
    setUp(() {
      databaseService = MockDatabaseService();
    });

    tearDown(() {
      databaseService.reset();
    });

    group('Shot Operations', () {
      test('should insert shot and return valid ID', () async {
        final shotData = TestDataGenerator.generateDatabaseShot();
        
        final id = await databaseService.insertShot(shotData);
        
        expect(id, greaterThan(0));
        expect(databaseService.allShots.length, 1);
        
        final insertedShot = databaseService.allShots.first;
        expect(insertedShot['id'], id);
        expect(insertedShot['speed'], shotData['speed']);
        expect(insertedShot['angle'], shotData['angle']);
        expect(insertedShot['carry'], shotData['carry']);
      });

      test('should auto-generate timestamp if not provided', () async {
        final shotData = TestDataGenerator.generateDatabaseShot();
        shotData.remove('timestamp'); // Remove timestamp
        
        final beforeInsert = DateTime.now().millisecondsSinceEpoch;
        await databaseService.insertShot(shotData);
        final afterInsert = DateTime.now().millisecondsSinceEpoch;
        
        final insertedShot = databaseService.allShots.first;
        final timestamp = insertedShot['timestamp'] as int;
        
        expect(timestamp, greaterThanOrEqualTo(beforeInsert));
        expect(timestamp, lessThanOrEqualTo(afterInsert));
      });

      test('should retrieve shot by ID', () async {
        final shotData = TestDataGenerator.generateDatabaseShot();
        final id = await databaseService.insertShot(shotData);
        
        final retrievedShot = await databaseService.getShot(id);
        
        expect(retrievedShot, isNotNull);
        expect(retrievedShot!['id'], id);
        expect(retrievedShot['speed'], shotData['speed']);
        expect(retrievedShot['angle'], shotData['angle']);
      });

      test('should return null for non-existent shot ID', () async {
        final retrievedShot = await databaseService.getShot(999);
        expect(retrievedShot, isNull);
      });

      test('should get all shots with default ordering', () async {
        final shots = <Map<String, dynamic>>[];
        
        // Insert shots with different timestamps
        for (int i = 0; i < 3; i++) {
          final shotData = TestDataGenerator.generateDatabaseShot();
          shotData['timestamp'] = DateTime.now().millisecondsSinceEpoch + i * 1000;
          shots.add(shotData);
          await databaseService.insertShot(shotData);
        }
        
        final retrievedShots = await databaseService.getAllShots();
        
        expect(retrievedShots.length, 3);
        
        // Should be ordered by timestamp DESC (newest first)
        for (int i = 0; i < retrievedShots.length - 1; i++) {
          final currentTimestamp = retrievedShots[i]['timestamp'] as int;
          final nextTimestamp = retrievedShots[i + 1]['timestamp'] as int;
          expect(currentTimestamp, greaterThanOrEqualTo(nextTimestamp));
        }
      });

      test('should filter shots by session ID', () async {
        const sessionId1 = 'session-1';
        const sessionId2 = 'session-2';
        
        // Insert shots for different sessions
        for (int i = 0; i < 3; i++) {
          final shot1 = TestDataGenerator.generateDatabaseShot(sessionId: sessionId1);
          final shot2 = TestDataGenerator.generateDatabaseShot(sessionId: sessionId2);
          await databaseService.insertShot(shot1);
          await databaseService.insertShot(shot2);
        }
        
        final session1Shots = await databaseService.getAllShots(sessionId: sessionId1);
        final session2Shots = await databaseService.getAllShots(sessionId: sessionId2);
        
        expect(session1Shots.length, 3);
        expect(session2Shots.length, 3);
        
        // Verify all shots belong to correct session
        for (final shot in session1Shots) {
          expect(shot['session_id'], sessionId1);
        }
        for (final shot in session2Shots) {
          expect(shot['session_id'], sessionId2);
        }
      });

      test('should respect limit and offset parameters', () async {
        // Insert 10 shots
        for (int i = 0; i < 10; i++) {
          final shotData = TestDataGenerator.generateDatabaseShot();
          await databaseService.insertShot(shotData);
        }
        
        // Test limit
        final limitedShots = await databaseService.getAllShots(limit: 5);
        expect(limitedShots.length, 5);
        
        // Test offset
        final offsetShots = await databaseService.getAllShots(offset: 3);
        expect(offsetShots.length, 7);
        
        // Test limit + offset
        final limitedOffsetShots = await databaseService.getAllShots(limit: 3, offset: 2);
        expect(limitedOffsetShots.length, 3);
      });

      test('should update shot correctly', () async {
        final shotData = TestDataGenerator.generateDatabaseShot();
        final id = await databaseService.insertShot(shotData);
        
        final updates = {
          'speed': 45.5,
          'angle': 18.0,
          'notes': 'Updated shot notes',
        };
        
        final updateCount = await databaseService.updateShot(id, updates);
        expect(updateCount, 1);
        
        final updatedShot = await databaseService.getShot(id);
        expect(updatedShot!['speed'], 45.5);
        expect(updatedShot['angle'], 18.0);
        expect(updatedShot['notes'], 'Updated shot notes');
        
        // Original values should remain unchanged where not updated
        expect(updatedShot['carry'], shotData['carry']);
      });

      test('should return 0 when updating non-existent shot', () async {
        final updateCount = await databaseService.updateShot(999, {'speed': 40.0});
        expect(updateCount, 0);
      });

      test('should delete shot correctly', () async {
        final shotData = TestDataGenerator.generateDatabaseShot();
        final id = await databaseService.insertShot(shotData);
        
        expect(databaseService.allShots.length, 1);
        
        final deleteCount = await databaseService.deleteShot(id);
        expect(deleteCount, 1);
        expect(databaseService.allShots.length, 0);
      });

      test('should return 0 when deleting non-existent shot', () async {
        final deleteCount = await databaseService.deleteShot(999);
        expect(deleteCount, 0);
      });
    });

    group('Session Operations', () {
      test('should create session and return valid ID', () async {
        const sessionName = 'Morning Practice';
        const sessionNotes = 'Working on driver accuracy';
        
        final id = await databaseService.createSession(sessionName, notes: sessionNotes);
        
        expect(id, greaterThan(0));
        expect(databaseService.allSessions.length, 1);
        
        final session = databaseService.allSessions.first;
        expect(session['id'], id);
        expect(session['name'], sessionName);
        expect(session['notes'], sessionNotes);
        expect(session['start_time'], isA<int>());
        expect(session['end_time'], isNull);
      });

      test('should end session correctly', () async {
        final sessionId = await databaseService.createSession('Test Session');
        
        // Add some shots to the session
        for (int i = 0; i < 3; i++) {
          final shot = TestDataGenerator.generateDatabaseShot(sessionId: sessionId.toString());
          await databaseService.insertShot(shot);
        }
        
        final beforeEnd = DateTime.now().millisecondsSinceEpoch;
        final updateCount = await databaseService.endSession(sessionId);
        final afterEnd = DateTime.now().millisecondsSinceEpoch;
        
        expect(updateCount, 1);
        
        final session = databaseService.allSessions.first;
        final endTime = session['end_time'] as int;
        expect(endTime, greaterThanOrEqualTo(beforeEnd));
        expect(endTime, lessThanOrEqualTo(afterEnd));
      });

      test('should get all sessions with correct ordering', () async {
        final sessionNames = ['Session 1', 'Session 2', 'Session 3'];
        
        for (int i = 0; i < sessionNames.length; i++) {
          await Future.delayed(const Duration(milliseconds: 10)); // Ensure different timestamps
          await databaseService.createSession(sessionNames[i]);
        }
        
        final sessions = await databaseService.getAllSessions();
        
        expect(sessions.length, 3);
        
        // Should be ordered by start_time DESC (newest first)
        for (int i = 0; i < sessions.length - 1; i++) {
          final currentTime = sessions[i]['start_time'] as int;
          final nextTime = sessions[i + 1]['start_time'] as int;
          expect(currentTime, greaterThanOrEqualTo(nextTime));
        }
      });

      test('should respect limit and offset for sessions', () async {
        // Create 5 sessions
        for (int i = 0; i < 5; i++) {
          await databaseService.createSession('Session $i');
        }
        
        final limitedSessions = await databaseService.getAllSessions(limit: 3);
        expect(limitedSessions.length, 3);
        
        final offsetSessions = await databaseService.getAllSessions(offset: 2);
        expect(offsetSessions.length, 3);
        
        final limitedOffsetSessions = await databaseService.getAllSessions(limit: 2, offset: 1);
        expect(limitedOffsetSessions.length, 2);
      });
    });

    group('Statistics Operations', () {
      test('should calculate session statistics correctly', () async {
        final sessionId = await databaseService.createSession('Stats Test Session');
        final sessionIdStr = sessionId.toString();
        
        // Add shots with known values
        final shotData = [
          {'speed': 40.0, 'angle': 10.0, 'carry': 200.0},
          {'speed': 50.0, 'angle': 15.0, 'carry': 250.0},
          {'speed': 45.0, 'angle': 12.0, 'carry': 225.0},
        ];
        
        for (final shot in shotData) {
          final shotRecord = TestDataGenerator.generateDatabaseShot(sessionId: sessionIdStr);
          shotRecord['speed'] = shot['speed'];
          shotRecord['angle'] = shot['angle'];
          shotRecord['carry'] = shot['carry'];
          await databaseService.insertShot(shotRecord);
        }
        
        final stats = await databaseService.getSessionStats(sessionIdStr);
        
        expect(stats['total_shots'], 3);
        expect(stats['average_speed'], closeTo(45.0, 0.01)); // (40+50+45)/3
        expect(stats['max_speed'], 50.0);
        expect(stats['min_speed'], 40.0);
        expect(stats['average_angle'], closeTo(12.33, 0.01)); // (10+15+12)/3
        expect(stats['best_distance'], 250.0);
        expect(stats['average_distance'], closeTo(225.0, 0.01)); // (200+250+225)/3
      });

      test('should return zero stats for session with no shots', () async {
        final stats = await databaseService.getSessionStats('non-existent-session');
        
        expect(stats['total_shots'], 0);
        expect(stats['average_speed'], 0.0);
        expect(stats['max_speed'], 0.0);
        expect(stats['min_speed'], 0.0);
        expect(stats['average_angle'], 0.0);
        expect(stats['best_distance'], 0.0);
        expect(stats['average_distance'], 0.0);
      });

      test('should calculate overall statistics correctly', () async {
        // Create multiple sessions with shots
        for (int session = 0; session < 2; session++) {
          final sessionId = await databaseService.createSession('Session $session');
          
          for (int shot = 0; shot < 3; shot++) {
            final shotData = TestDataGenerator.generateDatabaseShot(
              sessionId: sessionId.toString(),
            );
            shotData['speed'] = 30.0 + shot * 10.0; // 30, 40, 50
            shotData['angle'] = 10.0 + shot * 2.0;  // 10, 12, 14
            shotData['carry'] = 150.0 + shot * 25.0; // 150, 175, 200
            
            await databaseService.insertShot(shotData);
          }
        }
        
        final stats = await databaseService.getOverallStats();
        
        expect(stats['total_shots'], 6);
        expect(stats['average_speed'], closeTo(40.0, 0.01)); // Average of 30,40,50,30,40,50
        expect(stats['max_speed'], 50.0);
        expect(stats['min_speed'], 30.0);
        expect(stats['best_distance'], 200.0);
        expect(stats['practice_days'], greaterThan(0));
      });

      test('should return zero overall stats when no shots exist', () async {
        final stats = await databaseService.getOverallStats();
        
        expect(stats['total_shots'], 0);
        expect(stats['average_speed'], 0.0);
        expect(stats['max_speed'], 0.0);
        expect(stats['min_speed'], 0.0);
        expect(stats['average_angle'], 0.0);
        expect(stats['best_distance'], 0.0);
        expect(stats['average_distance'], 0.0);
        expect(stats['practice_days'], 0);
      });
    });

    group('Edge Cases and Error Handling', () {
      test('should handle shots with null/missing values', () async {
        final shotData = {
          'speed': 45.0,
          'angle': null, // Null angle
          'carry': 220.0,
          // Missing session_id and other optional fields
        };
        
        expect(() => databaseService.insertShot(shotData), returnsNormally);
        
        final id = await databaseService.insertShot(shotData);
        expect(id, greaterThan(0));
      });

      test('should handle extreme statistical values', () async {
        final sessionId = await databaseService.createSession('Extreme Test');
        
        final extremeShots = [
          {'speed': 0.0, 'angle': -45.0, 'carry': 0.0},    // Minimum values
          {'speed': 100.0, 'angle': 90.0, 'carry': 400.0}, // Maximum values
        ];
        
        for (final shot in extremeShots) {
          final shotData = TestDataGenerator.generateDatabaseShot(
            sessionId: sessionId.toString(),
          );
          shotData.addAll(shot);
          await databaseService.insertShot(shotData);
        }
        
        final stats = await databaseService.getSessionStats(sessionId.toString());
        
        expect(stats['total_shots'], 2);
        expect(stats['average_speed'], closeTo(50.0, 0.01));
        expect(stats['max_speed'], 100.0);
        expect(stats['min_speed'], 0.0);
      });

      test('should handle concurrent operations safely', () async {
        final futures = <Future<int>>[];
        
        // Simulate concurrent inserts
        for (int i = 0; i < 10; i++) {
          final shotData = TestDataGenerator.generateDatabaseShot();
          futures.add(databaseService.insertShot(shotData));
        }
        
        final ids = await Future.wait(futures);
        
        expect(ids.length, 10);
        expect(ids.toSet().length, 10); // All IDs should be unique
        expect(databaseService.allShots.length, 10);
      });

      test('should maintain data integrity across operations', () async {
        final sessionId = await databaseService.createSession('Integrity Test');
        
        // Insert shots
        final originalShotIds = <int>[];
        for (int i = 0; i < 5; i++) {
          final shotData = TestDataGenerator.generateDatabaseShot(
            sessionId: sessionId.toString(),
          );
          final id = await databaseService.insertShot(shotData);
          originalShotIds.add(id);
        }
        
        // Update some shots
        await databaseService.updateShot(originalShotIds[0], {'speed': 99.9});
        await databaseService.updateShot(originalShotIds[2], {'angle': 99.9});
        
        // Delete one shot
        await databaseService.deleteShot(originalShotIds[4]);
        
        // Verify data integrity
        final remainingShots = await databaseService.getAllShots();
        expect(remainingShots.length, 4);
        
        final updatedShot1 = await databaseService.getShot(originalShotIds[0]);
        expect(updatedShot1!['speed'], 99.9);
        
        final updatedShot2 = await databaseService.getShot(originalShotIds[2]);
        expect(updatedShot2!['angle'], 99.9);
        
        final deletedShot = await databaseService.getShot(originalShotIds[4]);
        expect(deletedShot, isNull);
      });
    });

    group('Performance Considerations', () {
      test('should handle large datasets efficiently', () async {
        const largeDatasetSize = 1000;
        
        final stopwatch = Stopwatch()..start();
        
        // Insert large number of shots
        for (int i = 0; i < largeDatasetSize; i++) {
          final shotData = TestDataGenerator.generateDatabaseShot();
          await databaseService.insertShot(shotData);
        }
        
        stopwatch.stop();
        
        expect(databaseService.allShots.length, largeDatasetSize);
        
        // Performance should be reasonable (adjust threshold as needed)
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // 5 seconds max
      });

      test('should efficiently query with filters and limits', () async {
        // Create test data
        const sessionId = 'performance-test-session';
        for (int i = 0; i < 100; i++) {
          final shotData = TestDataGenerator.generateDatabaseShot(sessionId: sessionId);
          await databaseService.insertShot(shotData);
        }
        
        final stopwatch = Stopwatch()..start();
        
        // Perform various queries
        await databaseService.getAllShots(limit: 10);
        await databaseService.getAllShots(sessionId: sessionId, limit: 20);
        await databaseService.getAllShots(offset: 50, limit: 10);
        await databaseService.getSessionStats(sessionId);
        
        stopwatch.stop();
        
        // Queries should be fast
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // 1 second max
      });
    });
  });
}