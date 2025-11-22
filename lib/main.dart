import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local notifications (with default settings)
  FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final DarwinInitializationSettings initSettingsIOS =
      DarwinInitializationSettings();
  final InitializationSettings initSettings = InitializationSettings(
    android: initSettingsAndroid,
    iOS: initSettingsIOS,
  );
  await notifications.initialize(initSettings);

  // On Android 13+, request notification permission explicitly
  if (await notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestPermission() ??
      false) {
    debugPrint('Notification permission granted');
  }

  runApp(MyApp(notifications: notifications));
}

class MyApp extends StatelessWidget {
  final FlutterLocalNotificationsPlugin notifications;
  const MyApp({Key? key, required this.notifications}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beacon Monitor',
      home: BeaconMonitorPage(notifications: notifications),
    );
  }
}

class BeaconMonitorPage extends StatefulWidget {
  final FlutterLocalNotificationsPlugin notifications;
  const BeaconMonitorPage({Key? key, required this.notifications})
    : super(key: key);

  @override
  _BeaconMonitorPageState createState() => _BeaconMonitorPageState();
}

class _BeaconMonitorPageState extends State<BeaconMonitorPage> {
  List<Beacon> _beacons = []; // list of detected beacons
  StreamSubscription<RangingResult>? _rangingSub;
  StreamSubscription<MonitoringResult>? _monitoringSub;
  Region? _selectedRegion; // region of the chosen beacon
  bool _isInRegion =
      false; // track if currently inside the beacon's region (to debounce events)

  @override
  void initState() {
    super.initState();
    _initBeaconScanning();
  }

  @override
  void dispose() {
    _rangingSub?.cancel();
    _monitoringSub?.cancel();
    super.dispose();
  }

  Future<void> _initBeaconScanning() async {
    try {
      // Initialize flutter_beacon (will check permissions automatically)
      await flutterBeacon
          .initializeAndCheckScanning; // requests location & Bluetooth if not granted
    } on PlatformException catch (e) {
      debugPrint("Failed to initialize scanning: ${e.message}");
      return;
    }

    // Define a region to scan for beacons, don't currently have specific UUIDs (iOS requires UUID)
    List<Region> regions = [];
    if (Platform.isIOS) {
      regions.add(
        Region(
          identifier: 'anyBeacon',
          proximityUUID: '00000000-0000-0000-0000-000000000000',
        ),
      );
    } else {
      regions.add(Region(identifier: 'anyBeacon'));
    }

    // Start ranging (scanning) for beacons in the defined regions
    _rangingSub = flutterBeacon.ranging(regions).listen((RangingResult result) {
      if (!mounted) return;
      setState(() {
        _beacons = result.beacons;
        _beacons.sort((a, b) => a.proximityUUID.compareTo(b.proximityUUID));
      });
    });
  }

  void _onBeaconSelected(Beacon beacon) {
    // Stop scanning once a beacon is selected
    _rangingSub?.cancel();

    // Define the region corresponding to the selected beacon's UUID/major/minor
    Region region = Region(
      identifier: 'TargetBeacon',
      proximityUUID: beacon.proximityUUID,
      major: beacon.major,
      minor: beacon.minor,
    );
    _selectedRegion = region;

    // Start monitoring this beacon region for enter events
    _monitoringSub = flutterBeacon.monitoring([region]).listen((
      MonitoringResult result,
    ) async {
      if (result.region == null) return;
      final eventType =
          result.monitoringEventType; // didEnterRegion, didExitRegion, etc.
      if (eventType == MonitoringEventType.didEnterRegion) {
        if (!_isInRegion) {
          _isInRegion = true;
          // User has entered the beacon’s region: trigger notification, sound, vibration
          await _triggerReminder();
        }
      } else if (eventType == MonitoringEventType.didExitRegion) {
        // Reset state on exit, so we can trigger again on next entry
        _isInRegion = false;
      }
    });
  }

  // Trigger local notification, sound, and vibration
  Future<void> _triggerReminder() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'beacon_channel', // channel ID
          'Beacon Alerts', // channel name
          channelDescription: 'Notifications for beacon entry alerts',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentSound: true,
    );
    const NotificationDetails notifDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await widget.notifications.show(
      0,
      'Beacon in Range',
      'You have entered the beacon’s region.',
      notifDetails,
    );

    // Additional sound/vibration (for foreground use-case)
    // Vibrate device (if supported)
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 1000);
    }
    // TODO: Can also play a custom sound here using an audio player if desired.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Beacon Monitor')),
      body: _selectedRegion == null
          ? _buildScanningView()
          : _buildMonitoringView(),
    );
  }

  // UI to show list of detected beacons for selection
  Widget _buildScanningView() {
    return _beacons.isEmpty
        ? Center(child: Text('Scanning for beacons...'))
        : ListView.builder(
            itemCount: _beacons.length,
            itemBuilder: (context, index) {
              Beacon beacon = _beacons[index];
              return ListTile(
                title: Text('UUID: ${beacon.proximityUUID}'),
                subtitle: Text(
                  'Major: ${beacon.major}, Minor: ${beacon.minor}',
                ),
                onTap: () => _onBeaconSelected(beacon),
              );
            },
          );
  }

  // UI to show monitoring status for the selected beacon
  Widget _buildMonitoringView() {
    return Center(
      child: Text(
        'Monitoring beacon:\nUUID ${_selectedRegion!.proximityUUID}\nMajor ${_selectedRegion!.major}, Minor ${_selectedRegion!.minor}',
        textAlign: TextAlign.center,
      ),
    );
  }
}
