TIRNAV 🚛
Tır ve ağır vasıta sürücüleri için Flutter navigasyon uygulaması. Gönderdiğin görseldeki koyu mavi arayüz mantığına göre hazırlanmış çalışan başlangıç sürümüdür.
Neler çalışıyor?
GPS ile mevcut konumu alma
Adres/şehir arama (HeiGIT Pelias)
Ağır vasıta rotası (driving-hgv)
Araç uzunluk/genişlik/yükseklik/ağırlık/aks yükü ve ADR parametreleri
Rota çizgisini gerçek haritada gösterme
Mesafe/süre/tahmini varış
Koyu harita + alt menü + araç profili + hizmet noktaları + ayarlar ekranları
GitHub Actions ile otomatik APK üretimi
Önemli: API anahtarını yenile
API anahtarını sohbet mesajında paylaştığın için eski anahtarı HeiGIT panelinden iptal edip yeni bir anahtar oluşturmanı öneriyorum. Yeni anahtarı GitHub'a dosya içinde koyma; Settings → Secrets and variables → Actions → New repository secret ile ORS_API_KEY olarak ekle.
Yerelde çalıştır
Flutter 3.47.x veya daha yeni bir Flutter SDK kur.
flutter create . --platforms=android
flutter pub get
flutter run --dart-define=ORS_API_KEY=YENI_KEY
Release APK
flutter build apk --release --dart-define=ORS_API_KEY=YENI_KEY
APK: build/app/outputs/flutter-apk/app-release.apk
GitHub Actions
.github/workflows/android.yml dosyası ORS_API_KEY secret'ını kullanarak APK üretir ve Actions artifact olarak yükler.
Harita
Bu prototip CARTO'nun dark tile katmanını, veri kaynağı olarak OpenStreetMap'i kullanır. Üretim uygulamasında tile sağlayıcısının kullanım şartlarını ve attribution koşullarını ayrıca kontrol et.
Gerçek ürün için sonraki adımlar
API key'i mobil uygulamadan saklamak için kendi backend/proxy katmanı.
Trafik verisi ve dinamik ETA.
Köprü/yükseklik/tonaj uyarıları için route extras + OSM kısıtlarının daha gelişmiş işlenmesi.
Tır parkı/akaryakıt/dinlenme POI entegrasyonu.
Arka planda sesli turn-by-turn navigasyon.
Offline harita ve offline rota cache'i.
