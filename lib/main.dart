import 'dart:ui';
import 'package:phone_state/phone_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  await FlutterBackgroundService().startService();
  FlutterBackgroundService().invoke("setAsForeground");
  Future.delayed(const Duration(seconds: 7), () {
    FlutterBackgroundService().invoke("listenIncoming");
  });
  runApp(MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
    ),
  );
  service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
    service.on('listenIncoming').listen((event) {});
    service.setForegroundNotificationInfo(
      title: "Background Service Running",
      content: "Monitoring calls...",
    );
  }
  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: CallMonitorScreen(),
    );
  }
}

class CallMonitorScreen extends StatefulWidget {
  @override
  _CallMonitorScreenState createState() => _CallMonitorScreenState();
}

class _CallMonitorScreenState extends State<CallMonitorScreen> {
  List<Contact> contacts = [];
  String callStatus = "Waiting for call...";
  bool hasPermission = false;
  final storage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () async {
      await requestPermissions();
      if (hasPermission) {
        await fetchContacts();
        PhoneState.stream.listen(callStateHandler);
      } else {
        print("Permissions not granted, skipping call monitoring.");
      }
    });
  }

  Future<void> requestPermissions() async {
    var statuses = await [
      Permission.contacts,
      Permission.phone,
      Permission.location,
    ].request();

    setState(() {
      hasPermission = statuses[Permission.contacts]?.isGranted == true &&
          statuses[Permission.phone]?.isGranted == true &&
          statuses[Permission.location]?.isGranted == true;
    });

    if (!hasPermission) {
      print("Permissions not fully granted: $statuses");
    }
  }

  Future<void> fetchContacts() async {
    if (await Permission.contacts.isGranted) {
      Iterable<Contact> fetchedContacts = await ContactsService.getContacts();
      setState(() {
        contacts = fetchedContacts.toList();
      });
    }
  }

  void callStateHandler(PhoneState state) async {
    if (state.status == PhoneStateStatus.CALL_INCOMING) {
      String? number = state.number ?? "Unknown";
      bool isKnown = contacts.any((contact) =>
      contact.phones?.any((phone) => phone.value == number) ?? false);

      Position? position;
      if (await Permission.location.isGranted) {
        position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
      }

      String location = position != null
          ? "Lat: \${position.latitude}, Lng: \${position.longitude}"
          : "Location unavailable";

      await storage.write(key: "last_call", value: "$number - $location");

      setState(() {
        callStatus = "Incoming call from $number\nKnown Contact: $isKnown\nLocation: $location";
      });

      Future.delayed(Duration.zero, () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(isKnown ? "Known Caller" : "Unknown Caller"),
            content: Text("Incoming call from: $number\n$location"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("OK"),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Call Monitor")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              hasPermission ? 'Monitoring Calls' : 'No Permission',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              callStatus,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: contacts.length,
              itemBuilder: (context, index) {
                return Card(
                  elevation: 2,
                  margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: Icon(Icons.contact_phone, color: Colors.blue),
                    title: Text(contacts[index].displayName ?? "Unknown"),
                    subtitle: Text(contacts[index].phones?.isNotEmpty == true
                        ? contacts[index].phones!.first.value ?? "No number"
                        : "No number"),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
