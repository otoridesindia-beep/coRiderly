import 'dart:convert';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const CoRiderlyApp());

const purple = Color(0xFF7C3AED);
const ink = Color(0xFF242138);
const muted = Color(0xFF77758A);
const line = Color(0xFFECEAF2);

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

class AppConfig {
  static const projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co',
  );

  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get isConfigured =>
      projectUrl.startsWith('https://') && anonKey.trim().isNotEmpty;
}

class CoRiderlyApp extends StatelessWidget {
  const CoRiderlyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CoRiderly',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: purple),
      scaffoldBackgroundColor: const Color(0xFFFAF9FC),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ink,
      ),
      useMaterial3: true,
    ),
    home: const RidePage(),
  );
}

class RidePage extends StatefulWidget {
  const RidePage({super.key});

  @override
  State<RidePage> createState() => _RidePageState();
}

class _RidePageState extends State<RidePage> {
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            final isWebUrl = uri.scheme == 'http' || uri.scheme == 'https';
            final isWhatsAppUrl =
                isWebUrl &&
                (uri.host == 'wa.me' ||
                    uri.host == 'www.whatsapp.com' ||
                    uri.host == 'api.whatsapp.com');
            const paymentAppSchemes = {
              'upi',
              'intent',
              'paytmmp',
              'tez',
              'gpay',
              'bhim',
              'credpay',
              'amazonpay',
              'mobikwik',
              'freecharge',
            };
            if (uri.scheme == 'tel' ||
                isWhatsAppUrl ||
                paymentAppSchemes.contains(uri.scheme)) {
              unawaited(_openExternalUri(uri));
              return NavigationDecision.prevent;
            }
            return isWebUrl
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadFlutterAsset('assets/web/index.html');
  }

  Future<void> _openExternalUri(Uri uri) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No app is available to open this link.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open link: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: WebViewWidget(controller: controller)),
  );
}

class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF43009E),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.directions_car_filled_rounded,
                        color: Colors.white,
                        size: 62,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'CoRiderly',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 56),
                      const Text(
                        'Better journeys, together',
                        style: TextStyle(
                          color: Color(0xFFE8C9F3),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your next ride starts here.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Find a seat or share your drive. Connect with people going your way and make every trip count.',
                        style: TextStyle(
                          color: Color(0xFFF0E4F4),
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Card(
                        color: Color(0x33FFFFFF),
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'WHERE YOU ARE',
                                      style: TextStyle(
                                        color: Color(0xFFE8D8ED),
                                        fontSize: 11,
                                      ),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'Your starting point',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.directions_car_filled,
                                color: Colors.white,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'WHERE YOU’RE GOING',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        color: Color(0xFFE8D8ED),
                                        fontSize: 11,
                                      ),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'Good company awaits',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 38),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => const AuthPage(),
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF5B21B6),
                          padding: const EdgeInsets.symmetric(vertical: 17),
                        ),
                        child: const Text('Get started'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class SupabaseAuth {
  static String normalizePhoneNumber(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '+91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
    if (phone.trim().startsWith('+') &&
        digits.length >= 8 &&
        digits.length <= 15) {
      return '+$digits';
    }
    throw const FormatException(
      'Enter a valid mobile number, using +country code for numbers outside India.',
    );
  }

  static Future<Map<String, dynamic>> authenticate({
    required String phone,
    required String pin,
    required bool register,
  }) async {
    if (!AppConfig.isConfigured) {
      throw Exception(
        'Set SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define or update AppConfig values before running.',
      );
    }

    final normalizedPhone = normalizePhoneNumber(phone);
    final uri = Uri.parse(
      '${AppConfig.projectUrl}/functions/v1/phone-pin-auth',
    );

    final response = await http.post(
      uri,
      headers: {
        'apikey': AppConfig.anonKey,
        'Authorization': 'Bearer ${AppConfig.anonKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'action': register ? 'register' : 'login',
        'phone': normalizedPhone,
        'pin': pin,
      }),
    );

    final result = _decodeBody(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        result['msg'] ??
            result['message'] ??
            result['error_description'] ??
            'Authentication failed.',
      );
    }

    return result;
  }

  static Map<String, dynamic> _decodeBody(String responseBody) {
    if (responseBody.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      // Fall through to the plain text fallback below.
    }
    return {'message': responseBody};
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  bool _register = true;
  bool _busy = false;
  bool _successMessage = false;
  String? _message;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    late final String normalizedPhone;
    try {
      normalizedPhone = SupabaseAuth.normalizePhoneNumber(_phone.text.trim());
    } on FormatException catch (error) {
      setState(() {
        _successMessage = false;
        _message = error.message;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await SupabaseAuth.authenticate(
        phone: normalizedPhone,
        pin: _pin.text,
        register: _register,
      );
      if (!mounted) return;
      if (_register) {
        setState(() {
          _register = false;
          _successMessage = true;
          _message =
              'Account created. Log in with your mobile number and 4-digit MPIN.';
        });
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RideHome(
            phone: normalizedPhone,
            fullName:
                'Member ${normalizedPhone.substring(normalizedPhone.length - 4)}',
          ),
        ),
      );
    } catch (error) {
      setState(() {
        _successMessage = false;
        _message = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Card(
              color: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Padding(
                padding: const EdgeInsets.all(25),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.directions_car_filled_rounded,
                        size: 44,
                        color: purple,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'CoRiderly',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        _register ? 'Welcome aboard' : 'Welcome back',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Create an account with your mobile number and 4-digit MPIN, then use them to log in.',
                        style: TextStyle(color: muted),
                      ),
                      const SizedBox(height: 20),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            label: Text('Create account'),
                          ),
                          ButtonSegment(value: false, label: Text('Log in')),
                        ],
                        selected: {_register},
                        onSelectionChanged: (value) => setState(() {
                          _register = value.first;
                          _successMessage = false;
                          _message = null;
                        }),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Mobile number',
                          hintText: '+91 98765 43210',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter your mobile number.';
                          }
                          try {
                            SupabaseAuth.normalizePhoneNumber(value);
                          } on FormatException catch (error) {
                            return error.message;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _pin,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: '4-digit MPIN',
                          hintText: 'Enter 4 digits',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                        validator: (value) =>
                            value == null || !RegExp(r'^\d{4}$').hasMatch(value)
                            ? 'Enter a 4-digit MPIN.'
                            : null,
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          style: TextStyle(
                            color: _successMessage
                                ? Colors.green.shade700
                                : Colors.red,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: purple,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: Text(
                          _busy
                              ? 'Please wait…'
                              : _register
                              ? 'Create account'
                              : 'Log in',
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your MPIN is protected and checked by the CoRiderly sign-in service.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class Ride {
  Ride({
    required this.from,
    required this.to,
    required this.time,
    required this.price,
    required this.seats,
    required this.driver,
    required this.phone,
    this.travelDate,
    this.mine = false,
  });

  final String from;
  final String to;
  final String time;
  final String driver;
  final String phone;
  final int price;
  final DateTime? travelDate;
  int seats;
  final bool mine;
}

class RideHome extends StatefulWidget {
  const RideHome({super.key, required this.phone, required this.fullName});

  final String phone;
  final String fullName;

  @override
  State<RideHome> createState() => _RideHomeState();
}

class _RideHomeState extends State<RideHome> {
  final _searchFrom = TextEditingController();
  final _searchTo = TextEditingController();
  final List<Ride> _rides = [
    Ride(
      from: 'San Francisco, CA',
      to: 'Sacramento, CA',
      time: '8:00 AM',
      price: 18,
      seats: 2,
      driver: 'Jordan M.',
      phone: '',
      travelDate: DateTime.now().add(const Duration(days: 1)),
    ),
    Ride(
      from: 'San Francisco, CA',
      to: 'Sacramento, CA',
      time: '9:15 AM',
      price: 22,
      seats: 3,
      driver: 'Lena C.',
      phone: '',
      travelDate: DateTime.now().add(const Duration(days: 1)),
    ),
    Ride(
      from: 'San Francisco, CA',
      to: 'Sacramento, CA',
      time: '11:30 AM',
      price: 15,
      seats: 1,
      driver: 'Avery R.',
      phone: '',
      travelDate: DateTime.now().add(const Duration(days: 1)),
    ),
  ];
  final List<Ride> _bookings = [];
  String _queryFrom = '';
  String _queryTo = '';
  String _sort = 'Recommended';
  DateTime? _searchDate;
  int _passengers = 1;
  late String _fullName = widget.fullName;
  int _tab = 0;

  String get _initials => _fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();

  @override
  void dispose() {
    _searchFrom.dispose();
    _searchTo.dispose();
    super.dispose();
  }

  List<Ride> get _visibleRides {
    var result = _rides.where((ride) {
      final matchesTab = _tab != 1 || ride.mine;
      final matchesFrom = ride.from.toLowerCase().contains(
        _queryFrom.toLowerCase(),
      );
      final matchesTo = ride.to.toLowerCase().contains(_queryTo.toLowerCase());
      final matchesPassengers = ride.seats >= _passengers;
      final matchesDate =
          _searchDate == null ||
          (ride.travelDate != null &&
              ride.travelDate!.year == _searchDate!.year &&
              ride.travelDate!.month == _searchDate!.month &&
              ride.travelDate!.day == _searchDate!.day);
      return matchesTab &&
          matchesFrom &&
          matchesTo &&
          matchesPassengers &&
          matchesDate;
    }).toList();
    if (_sort == 'Lowest price') {
      result.sort((a, b) => a.price.compareTo(b.price));
    }
    return result;
  }

  Future<void> _offerRide() async {
    final result = await Navigator.of(context).push<Ride>(
      MaterialPageRoute(builder: (_) => OfferRidePage(driverName: _fullName)),
    );
    if (result != null) {
      setState(() => _rides.insert(0, result));
    }
  }

  Future<void> _chooseSearchDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: _searchDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (selected != null) setState(() => _searchDate = selected);
  }

  void _book(Ride ride) {
    if (_bookings.contains(ride)) {
      setState(() {
        _bookings.remove(ride);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking removed.')));
      return;
    }
    if (ride.seats < 1) return;
    setState(() {
      ride.seats--;
      _bookings.add(ride);
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Seat booked.')));
  }

  Future<void> _openBookings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MyBookingsPage(
          bookings: List<Ride>.of(_bookings),
          onCancel: (ride) {
            setState(() {
              _bookings.remove(ride);
              ride.seats++;
            });
          },
        ),
      ),
    );
  }

  Future<void> _editProfile() async {
    final updatedName = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ProfilePage(fullName: _fullName, phone: widget.phone),
      ),
    );
    if (updatedName != null && mounted) {
      setState(() => _fullName = updatedName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rides = _visibleRides;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CoRiderly',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: CircleAvatar(
              child: _initials.isEmpty
                  ? const Icon(Icons.person_outline)
                  : Text(_initials),
            ),
            onSelected: (value) {
              if (value == 'profile') _editProfile();
              if (value == 'bookings') _openBookings();
              if (value == 'all') setState(() => _tab = 0);
              if (value == 'mine') setState(() => _tab = 1);
              if (value == 'web') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const RidePage()),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('Edit profile')),
              PopupMenuItem(value: 'all', child: Text('Show all rides')),
              PopupMenuItem(value: 'mine', child: Text('My offered rides')),
              PopupMenuItem(value: 'bookings', child: Text('My bookings')),
              PopupMenuItem(value: 'web', child: Text('Open HTML version')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _offerRide,
        backgroundColor: purple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Offer a ride'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Looking for a ride'),
                        icon: Icon(Icons.search),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Publish a ride'),
                        icon: Icon(Icons.add_road),
                      ),
                    ],
                    selected: const {false},
                    onSelectionChanged: (_) => _offerRide(),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'YOUR NEXT TRIP STARTS HERE',
                  style: TextStyle(
                    color: purple,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Find your carpool',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchFrom,
                          decoration: const InputDecoration(
                            labelText: 'Leaving from',
                            prefixIcon: Icon(Icons.trip_origin),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) =>
                              setState(() => _queryFrom = value),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchTo,
                          decoration: const InputDecoration(
                            labelText: 'Going to',
                            prefixIcon: Icon(Icons.location_on_outlined),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) =>
                              setState(() => _queryTo = value),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _chooseSearchDate,
                                icon: const Icon(Icons.calendar_today_outlined),
                                label: Text(
                                  _searchDate == null
                                      ? 'Travel date'
                                      : _formatDate(_searchDate!),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                initialValue: _passengers,
                                decoration: const InputDecoration(
                                  labelText: 'Passengers',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                items: List.generate(4, (index) => index + 1)
                                    .map(
                                      (count) => DropdownMenuItem(
                                        value: count,
                                        child: Text(
                                          '$count ${count == 1 ? 'passenger' : 'passengers'}',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) =>
                                    setState(() => _passengers = value ?? 1),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () {
                              if (_queryFrom.trim().isEmpty ||
                                  _queryTo.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Enter both departure and destination cities.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              FocusScope.of(context).unfocus();
                            },
                            icon: const Icon(Icons.search),
                            label: const Text('Find a ride'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_tab == 1 ? 'My offered rides' : 'Available rides'} (${rides.length})',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DropdownButton<String>(
                      value: _sort,
                      items: const ['Recommended', 'Lowest price']
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _sort = value!),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: rides.isEmpty
                ? const Center(
                    child: Text(
                      'No rides found. Try another city or adjust your search.',
                      style: TextStyle(color: muted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
                    itemCount: rides.length,
                    itemBuilder: (context, index) {
                      final ride = rides[index];
                      final booked = _bookings.contains(ride);
                      return Card(
                        color: Colors.white,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: const BorderSide(color: line),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.circle,
                                    size: 10,
                                    color: purple,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      ride.from,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(ride.time),
                                ],
                              ),
                              if (ride.travelDate != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _formatDate(ride.travelDate!),
                                  style: const TextStyle(color: muted),
                                ),
                              ],
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: SizedBox(
                                  height: 18,
                                  child: VerticalDivider(
                                    color: line,
                                    thickness: 2,
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    size: 16,
                                    color: purple,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      ride.to,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${ride.seats} seats left',
                                    style: const TextStyle(color: Colors.green),
                                  ),
                                ],
                              ),
                              const Divider(height: 22),
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: const Color(0xFFF1E5F5),
                                    child: Text(
                                      ride.driver
                                          .split(' ')
                                          .map((part) => part[0])
                                          .take(2)
                                          .join(),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      ride.driver,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '₹${ride.price} / seat',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: ride.mine || ride.seats < 1
                                      ? null
                                      : () => _book(ride),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: purple,
                                  ),
                                  child: Text(booked ? 'Booked' : 'Book seat'),
                                ),
                              ),
                            ],
                          ),
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

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.fullName, required this.phone});

  final String fullName;
  final String phone;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final _name = TextEditingController(text: widget.fullName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit profile')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const CircleAvatar(
              radius: 38,
              child: Icon(Icons.person_outline, size: 38),
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Full name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: widget.phone,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                helperText: 'Your sign-in number cannot be changed here.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () {
                final name = _name.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter your full name.')),
                  );
                  return;
                }
                Navigator.of(context).pop(name);
              },
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: const Text('Save profile'),
            ),
          ],
        ),
      ),
    ),
  );
}

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({
    super.key,
    required this.bookings,
    required this.onCancel,
  });

  final List<Ride> bookings;
  final ValueChanged<Ride> onCancel;

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> {
  late final _bookings = List<Ride>.of(widget.bookings);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My bookings')),
    body: _bookings.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_seat_outlined, size: 52, color: muted),
                  SizedBox(height: 14),
                  Text(
                    'You haven’t booked a seat yet.',
                    style: TextStyle(color: muted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _bookings.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final ride = _bookings[index];
              return Card(
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(Icons.directions_car, color: purple),
                  title: Text('${ride.from} → ${ride.to}'),
                  subtitle: Text(
                    '${ride.time} · ${ride.driver} · ₹${ride.price}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Cancel booking',
                    icon: const Icon(Icons.cancel_outlined),
                    onPressed: () {
                      widget.onCancel(ride);
                      setState(() => _bookings.remove(ride));
                    },
                  ),
                ),
              );
            },
          ),
  );
}

class OfferRidePage extends StatefulWidget {
  const OfferRidePage({super.key, this.driverName = 'You'});

  final String driverName;

  @override
  State<OfferRidePage> createState() => _OfferRidePageState();
}

class _OfferRidePageState extends State<OfferRidePage> {
  final _formKey = GlobalKey<FormState>();
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _price = TextEditingController();
  final _vehicleModel = TextEditingController();
  final _vehicleNumber = TextEditingController();
  final Map<String, String> _selectedFiles = {};
  DateTime? _travelDate;
  TimeOfDay? _departureTime;
  int _carCapacity = 5;
  int _availableSeats = 1;
  bool _showDocumentErrors = false;

  static const _documents = <String, String>{
    'profilePhoto': 'Profile photo',
    'aadhaarFront': 'Aadhaar card — front',
    'aadhaarBack': 'Aadhaar card — back',
    'rcFront': 'RC — front',
    'rcBack': 'RC — back',
    'insurance': 'Insurance copy',
  };

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _price.dispose();
    _vehicleModel.dispose();
    _vehicleNumber.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: _travelDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (selected != null) setState(() => _travelDate = selected);
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _departureTime ?? TimeOfDay.now(),
    );
    if (selected != null) setState(() => _departureTime = selected);
  }

  Future<void> _pickDocument(String key) async {
    final isPhoto = key == 'profilePhoto';
    try {
      final selection = await FilePicker.pickFiles(
        type: isPhoto ? FileType.image : FileType.custom,
        allowedExtensions: isPhoto ? null : const ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (selection.isEmpty || !mounted) return;
      setState(() => _selectedFiles[key] = selection.single.name);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not select the file: $error')),
      );
    }
  }

  void _publishRide() {
    if (!_formKey.currentState!.validate()) return;
    if (_travelDate == null || _departureTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a departure date and time.')),
      );
      return;
    }
    final missingDocuments = _documents.keys.any(
      (key) => !_selectedFiles.containsKey(key),
    );
    setState(() => _showDocumentErrors = missingDocuments);
    if (missingDocuments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose all required documents.')),
      );
      return;
    }

    Navigator.pop(
      context,
      Ride(
        from: _from.text.trim(),
        to: _to.text.trim(),
        time: _departureTime!.format(context),
        price: int.parse(_price.text),
        seats: _availableSeats,
        driver: widget.driverName,
        phone: '',
        travelDate: _travelDate,
        mine: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Offer a ride')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Share the journey',
                style: TextStyle(
                  color: purple,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add your trip details and invite passengers to join your ride.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              _field(_from, 'Leaving from'),
              _field(_to, 'Going to'),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  _travelDate == null
                      ? 'Choose departure date'
                      : 'Departure: ${_formatDate(_travelDate!)}',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule),
                label: Text(
                  _departureTime == null
                      ? 'Choose departure time'
                      : 'Departure time: ${_departureTime!.format(context)}',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _carCapacity,
                decoration: const InputDecoration(
                  labelText: 'Vehicle capacity',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5 seats')),
                  DropdownMenuItem(value: 7, child: Text('7 seats')),
                ],
                onChanged: (value) => setState(() {
                  _carCapacity = value ?? 5;
                  if (_availableSeats >= _carCapacity) {
                    _availableSeats = _carCapacity - 1;
                  }
                }),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _availableSeats,
                decoration: const InputDecoration(
                  labelText: 'Available passenger seats',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(_carCapacity - 1, (index) => index + 1)
                    .map((seats) {
                      return DropdownMenuItem(
                        value: seats,
                        child: Text('$seats ${seats == 1 ? 'seat' : 'seats'}'),
                      );
                    })
                    .toList(),
                onChanged: (value) =>
                    setState(() => _availableSeats = value ?? 1),
              ),
              const SizedBox(height: 14),
              _field(_vehicleModel, 'Car name / model'),
              _field(_vehicleNumber, 'Vehicle registration number'),
              _field(
                _price,
                'Price per passenger (₹)',
                keyboard: TextInputType.number,
                validator: (value) {
                  final price = int.tryParse(value ?? '');
                  return price == null || price < 1
                      ? 'Enter a valid price.'
                      : null;
                },
              ),
              const SizedBox(height: 4),
              const Text(
                'Driver documents',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              const Card(
                color: Color(0xFFFFF4E5),
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Privacy: selected documents stay on this device and are not uploaded or saved by this demo. Do not use this for real identity verification.',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ..._documents.entries.map(
                (entry) => _documentPicker(entry.key, entry.value),
              ),
              const Card(
                color: Color(0xFFF3EDFF),
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    '₹39 Pine Labs payment is required to publish each ride. This demo keeps ride details in memory only.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _publishRide,
                style: FilledButton.styleFrom(
                  backgroundColor: purple,
                  padding: const EdgeInsets.all(15),
                ),
                child: const Text('Publish ride'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _documentPicker(String key, String label) {
    final fileName = _selectedFiles[key];
    final showError = _showDocumentErrors && fileName == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => _pickDocument(key),
            icon: Icon(
              fileName == null ? Icons.attach_file : Icons.check_circle_outline,
            ),
            label: Text(
              fileName ?? 'Choose ${key == 'profilePhoto' ? 'photo' : 'file'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showError)
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 12),
              child: Text(
                'Required',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ??
          (value) => value == null || value.trim().isEmpty ? 'Required' : null,
    ),
  );
}
