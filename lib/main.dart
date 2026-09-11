import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

const String orsApiKey = String.fromEnvironment('ORS_API_KEY', defaultValue: '');
const String orsBase = 'https://api.heigit.org';
const String tileUrl = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

void main() => runApp(const TirnavApp());

class TirnavApp extends StatefulWidget {
  const TirnavApp({super.key});
  @override State<TirnavApp> createState() => _TirnavAppState();
}

class _TirnavAppState extends State<TirnavApp> {
  ThemeMode mode = ThemeMode.dark;
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'TIRNAV',
    themeMode: mode,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.light, colorSchemeSeed: Colors.blue),
    darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: const Color(0xff061321), colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark)),
    home: MainShell(onThemeChanged: (v) => setState(() => mode = v ? ThemeMode.dark : ThemeMode.light)),
  );
}

class TruckProfile {
  String type = 'Çekici + Dorse';
  double length = 16.50, width = 2.55, height = 4.00, weight = 40.0, axleload = 10.0;
  bool hazmat = false, trailer = true;
  Map<String, dynamic> get restrictions => {
    'length': length, 'width': width, 'height': height, 'weight': weight, 'axleload': axleload, 'hazmat': hazmat,
  };
}

class RouteResult {
  final List<LatLng> points;
  final double km;
  final Duration duration;
  final List<String> steps;
  RouteResult(this.points, this.km, this.duration, this.steps);
}

class OrsService {
  Future<List<Map<String, dynamic>>> geocode(String text) async {
    if (orsApiKey.isEmpty) return [];
    final uri = Uri.parse('$orsBase/pelias/v1/search').replace(queryParameters: {'text': text, 'size': '5', 'lang': 'tr'});
    final r = await http.get(uri, headers: {'Authorization': orsApiKey});
    if (r.statusCode >= 400) throw Exception('Geocoding ${r.statusCode}: ${r.body}');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return ((data['features'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  Future<RouteResult> route({required LatLng start, required LatLng end, required TruckProfile truck, bool avoidTolls = false}) async {
    if (orsApiKey.isEmpty) throw Exception('ORS_API_KEY tanımlı değil.');
    final body = {
      'coordinates': [[start.longitude, start.latitude], [end.longitude, end.latitude]],
      'instructions': true,
      'instructions_format': 'text',
      'language': 'tr',
      'units': 'km',
      'geometry': true,
      'extra_info': ['waytype', 'steepness'],
      'options': {
        'vehicle_type': 'hgv',
        if (avoidTolls) 'avoid_features': ['tollways'],
        'profile_params': {'restrictions': truck.restrictions},
      },
    };
    final uri = Uri.parse('$orsBase/openrouteservice/v2/directions/driving-hgv');
    final r = await http.post(uri, headers: {'Authorization': orsApiKey, 'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (r.statusCode >= 400) throw Exception('Rota ${r.statusCode}: ${r.body}');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final route = (data['routes'] as List).first as Map<String, dynamic>;
    final summary = route['summary'] as Map<String, dynamic>;
    final geometry = route['geometry'];
    final points = _decodeGeometry(geometry);
    final segments = (route['segments'] as List?) ?? [];
    final steps = <String>[];
    for (final s in segments) {
      for (final st in ((s as Map)['steps'] as List? ?? [])) {
        final m = st as Map;
        final instruction = (m['instruction'] ?? '').toString();
        if (instruction.isNotEmpty) steps.add(instruction);
      }
    }
    return RouteResult(points, (summary['distance'] as num).toDouble(), Duration(seconds: (summary['duration'] as num).round()), steps);
  }

  List<LatLng> _decodeGeometry(dynamic geometry) {
    if (geometry is String) return _polylineDecode(geometry);
    if (geometry is Map && geometry['coordinates'] is List) {
      return (geometry['coordinates'] as List).map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())).toList();
    }
    return [];
  }

  List<LatLng> _polylineDecode(String encoded) {
    final result = <LatLng>[]; int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int shift = 0, resultInt = 0;
      while (true) { final b = encoded.codeUnitAt(index++) - 63; resultInt |= (b & 0x1f) << shift; shift += 5; if (b < 0x20) break; }
      lat += (resultInt & 1) != 0 ? ~(resultInt >> 1) : (resultInt >> 1);
      shift = 0; resultInt = 0;
      while (true) { final b = encoded.codeUnitAt(index++) - 63; resultInt |= (b & 0x1f) << shift; shift += 5; if (b < 0x20) break; }
      lng += (resultInt & 1) != 0 ? ~(resultInt >> 1) : (resultInt >> 1);
      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }
}

class MainShell extends StatefulWidget {
  final ValueChanged<bool> onThemeChanged;
  const MainShell({super.key, required this.onThemeChanged});
  @override State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0; final truck = TruckProfile(); final ors = OrsService();
  LatLng? location; LatLng? destination; RouteResult? routeResult; bool loading = false; String? error; bool avoidTolls = false;
  final destinationCtrl = TextEditingController();
  final mapController = MapController();

  @override void initState() { super.initState(); _locate(); }
  @override void dispose() { destinationCtrl.dispose(); super.dispose(); }

  Future<void> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) setState(() => location = LatLng(pos.latitude, pos.longitude));
    } catch (_) {}
  }

  Future<void> _searchAndRoute() async {
    if (destinationCtrl.text.trim().isEmpty || location == null) return;
    setState(() {loading = true; error = null;});
    try {
      final places = await ors.geocode(destinationCtrl.text.trim());
      if (places.isEmpty) throw Exception('Varış noktası bulunamadı.');
      final c = places.first['geometry']['coordinates'] as List;
      final dest = LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
      final rr = await ors.route(start: location!, end: dest, truck: truck, avoidTolls: avoidTolls);
      setState(() {destination = dest; routeResult = rr; tab = 1;});
      if (rr.points.isNotEmpty) mapController.fitCamera(CameraFit.coordinates(coordinates: rr.points, padding: const EdgeInsets.fromLTRB(40, 150, 40, 230)));
    } catch (e) { setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => loading = false); }
  }

  @override Widget build(BuildContext context) {
    final pages = [
      HomePage(truck: truck, location: location, destinationCtrl: destinationCtrl, onRoute: _searchAndRoute, loading: loading, error: error),
      NavigationPage(mapController: mapController, location: location, destination: destination, route: routeResult, onRecenter: _locate),
      ServicesPage(),
      VehiclePage(truck: truck, onSaved: () => setState(() {})),
      SettingsPage(onTheme: widget.onThemeChanged),
    ];
    return Scaffold(body: IndexedStack(index: tab, children: pages), bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Ana Sayfa'),
      NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Harita'),
      NavigationDestination(icon: Icon(Icons.local_parking_outlined), selectedIcon: Icon(Icons.local_parking), label: 'Parklar'),
      NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Araç'),
      NavigationDestination(icon: Icon(Icons.menu), selectedIcon: Icon(Icons.menu), label: 'Diğer'),
    ]));
  }
}

class HomePage extends StatelessWidget {
  final TruckProfile truck; final LatLng? location; final TextEditingController destinationCtrl; final VoidCallback onRoute; final bool loading; final String? error;
  const HomePage({super.key, required this.truck, required this.location, required this.destinationCtrl, required this.onRoute, required this.loading, required this.error});
  @override Widget build(BuildContext context) => Stack(children: [
    Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xff06182b), Color(0xff0b2942), Color(0xff071525)]))),
    SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      const Icon(Icons.local_shipping, size: 68, color: Colors.white),
      const SizedBox(height: 6),
      RichText(textAlign: TextAlign.center, text: const TextSpan(style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 1), children: [TextSpan(text: 'TIR', style: TextStyle(color: Colors.white)), TextSpan(text: 'NAV', style: TextStyle(color: Colors.blueAccent))])),
      const Text('Tırların Yol Arkadaşı', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15)),
      const Spacer(),
      _InputTile(icon: Icons.location_on, title: 'Mevcut konum', value: location == null ? 'Konum alınıyor…' : 'GPS konumu hazır', color: Colors.greenAccent),
      const SizedBox(height: 10),
      TextField(controller: destinationCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(prefixIcon: const Icon(Icons.location_on, color: Colors.redAccent), labelText: 'Varış noktası', hintText: 'Adres, şehir veya ülke girin', filled: true, fillColor: const Color(0xff0b2135), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      const SizedBox(height: 12),
      SizedBox(height: 56, child: FilledButton.icon(onPressed: loading ? null : onRoute, icon: loading ? const SizedBox(width: 20,height:20,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.route), label: Text(loading ? 'Rota hesaplanıyor…' : 'Rota Oluştur', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)))),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center)),
      const SizedBox(height: 14),
      const Text('TIRNAV • Ağır vasıta için tasarlanmıştır', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)),
    ])))
  ]);
}

class _InputTile extends StatelessWidget { final IconData icon; final String title, value; final Color color; const _InputTile({required this.icon,required this.title,required this.value,required this.color}); @override Widget build(BuildContext c)=>Container(padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:const Color(0xff0b2135),borderRadius:BorderRadius.circular(12),border:Border.all(color:Colors.white12)),child:Row(children:[Icon(icon,color:color),const SizedBox(width:12),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(color:Colors.white54,fontSize:12)),Text(value,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w600))]),const Spacer(),const Icon(Icons.chevron_right,color:Colors.white54)])); }

class NavigationPage extends StatelessWidget {
  final MapController mapController; final LatLng? location, destination; final RouteResult? route; final VoidCallback onRecenter;
  const NavigationPage({super.key,required this.mapController,required this.location,required this.destination,required this.route,required this.onRecenter});
  @override Widget build(BuildContext context) {
    final center = location ?? const LatLng(41.08, 29.28);
    return Stack(children: [FlutterMap(mapController: mapController, options: MapOptions(initialCenter:center,initialZoom:12,minZoom:4,maxZoom:19), children:[
      TileLayer(urlTemplate: tileUrl, subdomains: const ['a','b','c','d'], userAgentPackageName:'com.tirnav.app'),
      if (route != null) PolylineLayer(polylines:[Polyline(points:route!.points,color:Colors.blueAccent,strokeWidth:7,borderColor:Colors.black54,borderStrokeWidth:2)]),
      MarkerLayer(markers:[if(location!=null) Marker(point:location!,width:54,height:54,child:Container(decoration:BoxDecoration(color:Colors.blue,borderRadius:BorderRadius.circular(30),border:Border.all(color:Colors.white,width:3)),child:const Icon(Icons.navigation,color:Colors.white))),if(destination!=null) Marker(point:destination!,width:45,height:45,child:const Icon(Icons.location_on,color:Colors.redAccent,size:44))]),
      RichAttributionWidget(attributions:[TextSourceAttribution('OpenStreetMap contributors / CARTO')]),
    ]),
    SafeArea(child: Column(children:[
      Container(margin:const EdgeInsets.all(12),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xee071a2c),borderRadius:BorderRadius.circular(16),border:Border.all(color:Colors.blueAccent.withOpacity(.5))),child:Row(children:[const Icon(Icons.arrow_upward,size:32,color:Colors.white),const SizedBox(width:12),Expanded(child:Text(route==null?'Rota bekleniyor':'Tır için optimize edilmiş rota',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold,fontSize:17))),IconButton(onPressed:onRecenter,icon:const Icon(Icons.my_location,color:Colors.white))])),
      const Spacer(),
      if(route!=null) Container(margin:const EdgeInsets.all(12),padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:const Color(0xf2071a2c),borderRadius:BorderRadius.circular(18)),child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[_Stat('${route!.km.toStringAsFixed(0)} km','Mesafe'),_Stat(_duration(route!.duration),'Süre'),_Stat(_eta(route!.duration),'Tahmini varış')])),
    ]))]);
  }
  static String _duration(Duration d)=>'${d.inHours} sa ${(d.inMinutes%60).toString().padLeft(2,'0')} dk';
  static String _eta(Duration d){final t=DateTime.now().add(d); return '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';}
}
class _Stat extends StatelessWidget { final String a,b; const _Stat(this.a,this.b); @override Widget build(BuildContext c)=>Column(children:[Text(a,style:const TextStyle(color:Colors.white,fontSize:19,fontWeight:FontWeight.w800)),Text(b,style:const TextStyle(color:Colors.white54,fontSize:11))]); }

class VehiclePage extends StatefulWidget { final TruckProfile truck; final VoidCallback onSaved; const VehiclePage({super.key,required this.truck,required this.onSaved}); @override State<VehiclePage> createState()=>_VehiclePageState(); }
class _VehiclePageState extends State<VehiclePage> {
  late TextEditingController l,w,h,wt,ax;
  @override void initState(){super.initState();final t=widget.truck;l=TextEditingController(text:t.length.toString());w=TextEditingController(text:t.width.toString());h=TextEditingController(text:t.height.toString());wt=TextEditingController(text:t.weight.toString());ax=TextEditingController(text:t.axleload.toString());}
  @override void dispose(){for(final c in [l,w,h,wt,ax])c.dispose();super.dispose();}
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Araç Profili')),body:ListView(padding:const EdgeInsets.all(18),children:[
    const Icon(Icons.local_shipping,size:100), _field('Araç türü',widget.truck.type), _num('Uzunluk (m)',l),_num('Genişlik (m)',w),_num('Yükseklik (m)',h),_num('Ağırlık (ton)',wt),_num('Aks yükü (ton)',ax),
    SwitchListTile(title:const Text('ADR (Tehlikeli madde)'),value:widget.truck.hazmat,onChanged:(v)=>setState(()=>widget.truck.hazmat=v)),SwitchListTile(title:const Text('Römork'),value:widget.truck.trailer,onChanged:(v)=>setState(()=>widget.truck.trailer=v)),
    const SizedBox(height:10),SizedBox(height:52,child:FilledButton(onPressed:(){widget.truck.length=double.tryParse(l.text)??widget.truck.length;widget.truck.width=double.tryParse(w.text)??widget.truck.width;widget.truck.height=double.tryParse(h.text)??widget.truck.height;widget.truck.weight=double.tryParse(wt.text)??widget.truck.weight;widget.truck.axleload=double.tryParse(ax.text)??widget.truck.axleload;widget.onSaved();ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('Araç profili kaydedildi')));},child:const Text('Kaydet')))
  ]));
  Widget _num(String x,TextEditingController c)=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:c,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:x,border:const OutlineInputBorder())));
  Widget _field(String x,String y)=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(readOnly:true,controller:TextEditingController(text:y),decoration:InputDecoration(labelText:x,border:const OutlineInputBorder())));
}

class ServicesPage extends StatelessWidget { const ServicesPage({super.key}); @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Tır İçin Hizmet Noktaları')),body:ListView(padding:const EdgeInsets.all(16),children:[_Service(icon:Icons.local_parking,title:'Tır Parkları',sub:'Yakındaki uygun park alanlarını haritada göster'),_Service(icon:Icons.local_gas_station,title:'Akaryakıt',sub:'Tır girişine uygun istasyonlar'),_Service(icon:Icons.restaurant,title:'Dinlenme Tesisi',sub:'Dinlenme ve yemek noktaları'),_Service(icon:Icons.warning_amber,title:'Yol Kısıtlamaları',sub:'Yükseklik, ağırlık ve tır yasakları') ]));}}
class _Service extends StatelessWidget {final IconData icon;final String title,sub;const _Service({required this.icon,required this.title,required this.sub});@override Widget build(BuildContext c)=>Card(child:ListTile(leading:CircleAvatar(child:Icon(icon)),title:Text(title),subtitle:Text(sub),trailing:const Icon(Icons.chevron_right)));}

class SettingsPage extends StatefulWidget { final ValueChanged<bool> onTheme; const SettingsPage({super.key,required this.onTheme}); @override State<SettingsPage> createState()=>_SettingsPageState(); }
class _SettingsPageState extends State<SettingsPage>{bool voice=true,notif=true;@override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Ayarlar')),body:ListView(children:[const ListTile(title:Text('Uygulama Ayarları')),SwitchListTile(title:const Text('Navigasyon Sesleri'),value:voice,onChanged:(v)=>setState(()=>voice=v)),ListTile(leading:const Icon(Icons.language),title:const Text('Dil'),trailing:const Text('Türkçe')),ListTile(leading:const Icon(Icons.straighten),title:const Text('Birimler'),trailing:const Text('Kilometre')),SwitchListTile(title:const Text('Bildirimler'),value:notif,onChanged:(v)=>setState(()=>notif=v)),const Divider(),ListTile(leading:const Icon(Icons.dark_mode),title:const Text('Gece modu'),subtitle:const Text('Harita koyu görünüm kullanır'),trailing:Switch(value:true,onChanged:(v)=>widget.onTheme(v))),const ListTile(leading:Icon(Icons.info_outline),title:Text('Hakkında'),subtitle:Text('TIRNAV • Ağır vasıta navigasyon prototipi'))]));}

