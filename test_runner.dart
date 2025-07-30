// test_runner.dart
/// Standalone test runner script for Golf Tracker quality assurance
/// 
/// Usage:
///   dart test_runner.dart [options]
/// 
/// Options:
///   --unit           Run unit tests only
///   --integration    Run integration tests only
///   --performance    Run performance benchmarks only
///   --validation     Run validation tests only
///   --ci             Run CI/CD optimized test suite
///   --full           Run complete test suite (default)
///   --help           Show this help message

import 'dart:io';
import 'test/performance/benchmark_suite.dart';
import 'test/quality/validation_suite.dart';
import 'test/quality/test_runner.dart';

Future<void> main(List<String> args) async {
  print('🏌️ Golf Tracker Test Runner v1.0.0\n');

  // Parse command line arguments
  final options = _parseArguments(args);
  
  if (options['help'] == true) {
    _printUsage();
    return;
  }

  final startTime = DateTime.now();
  bool success = false;

  try {
    if (options['ci'] == true) {
      print('Running CI/CD optimized test suite...\n');
      success = await GolfTrackerTestRunner.runCITestSuite();
      
    } else if (options['unit'] == true) {
      print('Running unit tests only...\n');
      final report = await GolfTrackerTestRunner.runCompleteTestSuite(
        runUnitTests: true,
        runIntegrationTests: false,
        runPerformanceTests: false,
        runValidationTests: false,
      );
      success = report.success;
      
    } else if (options['integration'] == true) {
      print('Running integration tests only...\n');
      final report = await GolfTrackerTestRunner.runCompleteTestSuite(
        runUnitTests: false,
        runIntegrationTests: true,
        runPerformanceTests: false,
        runValidationTests: false,
      );
      success = report.success;
      
    } else if (options['performance'] == true) {
      print('Running performance benchmarks only...\n');
      final results = await GolfTrackerTestRunner.runPerformanceBenchmarks();
      success = results.isNotEmpty;
      
    } else if (options['validation'] == true) {
      print('Running validation tests only...\n');
      final report = await GolfTrackerTestRunner.runValidationOnly();
      success = report.allTestsPassed;
      
    } else {
      // Default: run full test suite
      print('Running complete test suite...\n');
      final report = await GolfTrackerTestRunner.runCompleteTestSuite();
      success = report.success;
    }

    final duration = DateTime.now().difference(startTime);
    
    print('\n' + '=' * 60);
    print('TEST RUNNER SUMMARY');
    print('=' * 60);
    print('Status: ${success ? '✅ PASSED' : '❌ FAILED'}');
    print('Duration: ${duration.inMilliseconds}ms');
    print('Completed: ${DateTime.now().toIso8601String()}');
    
    if (!success) {
      print('\n⚠️  Some tests failed. Check the detailed output above.');
      print('💡 Consider running individual test suites to isolate issues:');
      print('   dart test_runner.dart --unit');
      print('   dart test_runner.dart --integration');
      print('   dart test_runner.dart --performance');
      print('   dart test_runner.dart --validation');
    } else {
      print('\n🎉 All tests passed! The golf tracker is ready for production.');
    }
    
  } catch (e, stackTrace) {
    print('❌ Test runner failed with error: $e');
    if (options['verbose'] == true) {
      print('Stack trace: $stackTrace');
    }
    success = false;
  }

  // Exit with appropriate code for CI/CD systems
  exit(success ? 0 : 1);
}

/// Parse command line arguments
Map<String, dynamic> _parseArguments(List<String> args) {
  final options = <String, dynamic>{
    'help': false,
    'unit': false,
    'integration': false,
    'performance': false,
    'validation': false,
    'ci': false,
    'full': false,
    'verbose': false,
  };

  for (final arg in args) {
    switch (arg) {
      case '--help':
      case '-h':
        options['help'] = true;
        break;
      case '--unit':
      case '-u':
        options['unit'] = true;
        break;
      case '--integration':
      case '-i':
        options['integration'] = true;
        break;
      case '--performance':
      case '-p':
        options['performance'] = true;
        break;
      case '--validation':
      case '-v':
        options['validation'] = true;
        break;
      case '--ci':
        options['ci'] = true;
        break;
      case '--full':
      case '-f':
        options['full'] = true;
        break;
      case '--verbose':
        options['verbose'] = true;
        break;
      default:
        print('⚠️  Unknown option: $arg');
        print('Use --help to see available options.\n');
        break;
    }
  }

  // Default to full test suite if no specific option is set
  if (!options.values.any((value) => value == true) || options['full'] == true) {
    options['full'] = true;
  }

  return options;
}

/// Print usage information
void _printUsage() {
  print('''
Golf Tracker Test Runner

USAGE:
    dart test_runner.dart [OPTIONS]

OPTIONS:
    --unit, -u           Run unit tests only
    --integration, -i    Run integration tests only  
    --performance, -p    Run performance benchmarks only
    --validation, -v     Run validation tests only
    --ci                 Run CI/CD optimized test suite
    --full, -f           Run complete test suite (default)
    --verbose            Show detailed error information
    --help, -h           Show this help message

EXAMPLES:
    dart test_runner.dart                    # Run all tests
    dart test_runner.dart --unit             # Unit tests only
    dart test_runner.dart --performance      # Performance tests only
    dart test_runner.dart --ci               # CI optimized suite
    dart test_runner.dart --validation       # Quality assurance tests

DESCRIPTION:
    The Golf Tracker Test Runner provides comprehensive testing capabilities
    for the golf ball tracking application. It includes:
    
    • Unit Tests: Individual component testing
    • Integration Tests: End-to-end pipeline testing  
    • Performance Tests: 240fps processing benchmarks
    • Validation Tests: Quality assurance and accuracy validation
    
    The test runner generates detailed reports and can be integrated into
    CI/CD pipelines for automated quality assurance.

EXIT CODES:
    0    All tests passed
    1    Some tests failed or error occurred
''');
}