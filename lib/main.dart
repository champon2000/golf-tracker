// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/practice_screen.dart';
import 'screens/history_screen.dart';
import 'services/database_service.dart';
import 'services/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  // Initialize database
  try {
    await DatabaseService.instance.database;
  } catch (e) {
    debugPrint('Database initialization error: $e');
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: MaterialApp(
        title: 'Golf Ball Tracker',
        theme: ThemeData(
          primarySwatch: Colors.green,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          brightness: Brightness.light,
          appBarTheme: const AppBarTheme(
            elevation: 2,
            centerTitle: true,
            systemOverlayStyle: SystemUiOverlayStyle.dark,
          ),
        ),
        darkTheme: ThemeData(
          primarySwatch: Colors.green,
          brightness: Brightness.dark,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const MainScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _permissionsGranted = false;
  bool _isCheckingPermissions = true;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check permissions when app resumes
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    setState(() {
      _isCheckingPermissions = true;
      _permissionError = null;
    });

    try {
      final cameraStatus = await Permission.camera.status;
      
      if (cameraStatus.isDenied) {
        final result = await Permission.camera.request();
        if (result.isGranted) {
          setState(() {
            _permissionsGranted = true;
            _isCheckingPermissions = false;
          });
        } else {
          setState(() {
            _permissionsGranted = false;
            _isCheckingPermissions = false;
            _permissionError = 'Camera permission is required for ball tracking';
          });
        }
      } else if (cameraStatus.isGranted) {
        setState(() {
          _permissionsGranted = true;
          _isCheckingPermissions = false;
        });
      } else if (cameraStatus.isPermanentlyDenied) {
        setState(() {
          _permissionsGranted = false;
          _isCheckingPermissions = false;
          _permissionError = 'Camera permission permanently denied. Please enable in settings.';
        });
      }
    } catch (e) {
      setState(() {
        _permissionsGranted = false;
        _isCheckingPermissions = false;
        _permissionError = 'Error checking permissions: $e';
      });
    }
  }

  Widget _buildPermissionScreen() {
    if (_isCheckingPermissions) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking permissions...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Golf Ball Tracker'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 64,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 16),
              Text(
                'Camera Permission Required',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _permissionError ?? 'This app needs camera access to track golf balls.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _checkPermissions,
                child: const Text('Grant Permission'),
              ),
              if (_permissionError?.contains('permanently denied') == true) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => openAppSettings(),
                  child: const Text('Open Settings'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionsGranted) {
      return _buildPermissionScreen();
    }

    final List<Widget> widgetOptions = <Widget>[
      const PracticeScreen(),
      const HistoryScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Golf Ball Tracker'),
        actions: [
          Consumer<AppState>(
            builder: (context, appState, child) {
              return IconButton(
                icon: Icon(
                  appState.isRecording ? Icons.stop : Icons.fiber_manual_record,
                  color: appState.isRecording ? Colors.red : null,
                ),
                onPressed: () {
                  if (appState.isRecording) {
                    appState.stopRecording();
                  } else {
                    appState.startRecording();
                  }
                },
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: widgetOptions,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.golf_course),
            label: 'Practice',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.green[700],
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}

