
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
  bool showContacts = false; // Track whether to show contacts

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

// Define a global or class-level variable to track dialog state
  bool isDialogOpen = false;

  void callStateHandler(PhoneState state) async {
    if (state.status == PhoneStateStatus.CALL_INCOMING) {
      String number = state.number?.trim() ?? "Unknown";

      // Normalize phone number (removing spaces, dashes, etc.)
      String normalizedNumber = number.replaceAll(RegExp(r'\D'), '');

      bool isKnown = contacts.any((contact) =>
      contact.phones?.any((phone) =>
      phone.value?.replaceAll(RegExp(r'\D'), '') == normalizedNumber) ??
          false);

      Position? position;
      String location = "Location unavailable";

      if (await Permission.location.isGranted) {
        try {
          position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high);
          location = "Lat: ${position.latitude}, Lng: ${position.longitude}";
        } catch (e) {
          location = "Error fetching location";
        }
      }

      // Store call details
      await storage.write(key: "last_call", value: "$number - $location");

      if (mounted) {
        setState(() {
          callStatus =
          "Incoming call from $number\nKnown Contact: $isKnown\nLocation: $location";
        });

        // Ensure only one alert is displayed
        if (!isDialogOpen) {
          isDialogOpen = true; // Mark that a dialog is open

          Future.delayed(Duration.zero, () {
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(isKnown ? "Known Caller" : "Unknown Caller"),
                  content: Text("Incoming call from: $number\n$location"),
                  actions: [
                    TextButton(
                      onPressed: () {
                        isDialogOpen = false; // Reset dialog state
                        Navigator.pop(context);
                      },
                      child: Text("OK"),
                    ),
                  ],
                ),
              );
            }
          });
        }
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Call Monitor")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(hasPermission ? 'Monitoring Calls' : 'No Permission'),
            SizedBox(height: 10),
            Text(callStatus, textAlign: TextAlign.center),
            SizedBox(height: 20),

            // Show button only if contacts are not visible
            if (!showContacts)
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    showContacts = true;
                  });
                },
                child: Text("Show Contact List"),
              ),

            // Display contacts when button is clicked
            if (showContacts)
              Expanded(
                child: ListView.builder(
                  itemCount: contacts.length,
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    return ListTile(
                      title: Text(contact.displayName ?? "Unknown"),
                      subtitle: Text(
                        contact.phones?.isNotEmpty == true
                            ? contact.phones!.first.value ?? "No number"
                            : "No number",
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
