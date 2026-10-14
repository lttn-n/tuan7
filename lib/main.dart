import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MapNavigatorScreen(),
    );
  }
}

class MapNavigatorScreen extends StatefulWidget {
  const MapNavigatorScreen({super.key});

  @override
  State<MapNavigatorScreen> createState() => _MapNavigatorScreenState();
}

class _MapNavigatorScreenState extends State<MapNavigatorScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  LatLng? _destinationLatLng;

  // API KEY CỦA BẠN
  static const String googleApiKey = "AIzaSyCasZK24xXioOoMwHyBP-Dq1AuXu8kFyew";

  static const LatLng _initialCameraPosition = LatLng(10.806692, 106.628561);

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  // 1. Lấy vị trí hiện tại
  Future<void> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = position;
      _markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: LatLng(position.latitude, position.longitude),
          infoWindow: const InfoWindow(title: 'Vị trí hiện tại'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    });

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude),
        15.0,
      ),
    );
  }

  // 2. Nhấp chọn điểm đích
  void _onMapTapped(LatLng position) {
    setState(() {
      _destinationLatLng = position;

      _markers.removeWhere((m) => m.markerId.value == 'destination');
      _markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: position,
          infoWindow: const InfoWindow(title: 'Điểm đến'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    });
  }

  // 3. Giải mã Polyline
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng((lat / 1E5), (lng / 1E5)));
    }
    return poly;
  }

  // 4. Gọi Directions API
  Future<void> _fetchDirections() async {
    if (_currentPosition == null || _destinationLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn điểm đến trên bản đồ!')),
      );
      return;
    }

    final String url =
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
        '&destination=${_destinationLatLng!.latitude},${_destinationLatLng!.longitude}'
        '&key=$googleApiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String status = data['status'] ?? '';

        if (status == 'OK') {
          final points = data['routes'][0]['overview_polyline']['points'];
          List<LatLng> polylineCoordinates = _decodePolyline(points);

          setState(() {
            _polylines.clear();
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                color: Colors.blue,
                width: 5,
                points: polylineCoordinates,
              ),
            );
          });

          _fitBounds();
        } else {
          String errorMsg = data['error_message'] ?? status;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi Google API ($status): $errorMsg')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi HTTP Status: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi kết nối: $e')),
      );
    }
  }

  void _fitBounds() {
    if (_currentPosition == null || _destinationLatLng == null) return;

    double southLat = _currentPosition!.latitude < _destinationLatLng!.latitude
        ? _currentPosition!.latitude
        : _destinationLatLng!.latitude;
    double northLat = _currentPosition!.latitude > _destinationLatLng!.latitude
        ? _currentPosition!.latitude
        : _destinationLatLng!.latitude;
    double westLng = _currentPosition!.longitude < _destinationLatLng!.longitude
        ? _currentPosition!.longitude
        : _destinationLatLng!.longitude;
    double eastLng = _currentPosition!.longitude > _destinationLatLng!.longitude
        ? _currentPosition!.longitude
        : _destinationLatLng!.longitude;

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(southLat, westLng),
          northeast: LatLng(northLat, eastLng),
        ),
        100.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Navigator - Tìm đường'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _initialCameraPosition,
              zoom: 14.0,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _markers,
            polylines: _polylines,
            onTap: _onMapTapped,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _fetchDirections,
              child: const Text(
                'Tìm đường đi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}