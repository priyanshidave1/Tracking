import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RoadSnapService {
  static const String apiKey = "AIzaSyB52Nlo6Zy4sXw8CQNDgUaha0hEjh3vPAI";

  static Future<List<LatLng>> snapToRoad(List<LatLng> points) async {
    if (points.length < 2) return points;

    final path = points
        .map((p) => "${p.latitude},${p.longitude}")
        .join('|');

    final url =
        "https://roads.googleapis.com/v1/snapToRoads?path=$path&interpolate=true&key=$apiKey";

    final res = await http.get(Uri.parse(url));

    if (res.statusCode != 200) return points;

    final data = jsonDecode(res.body);

    if (data['snappedPoints'] == null) return points;

    return (data['snappedPoints'] as List)
        .map((p) => LatLng(
      p['location']['latitude'],
      p['location']['longitude'],
    ))
        .toList();
  }
}