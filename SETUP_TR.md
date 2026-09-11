GitHub'da APK alma
GitHub'da boş bir repo aç: örn. tirnav.
Bu klasördeki dosyaları repo köküne yükle.
GitHub → Settings → Secrets and variables → Actions → New repository secret.
Name: ORS_API_KEY
Value: HeiGIT'ten aldığın YENİ anahtar.
Actions → Build TIRNAV APK → Run workflow.
Workflow bitince tirnav-release-apk artifact'ini indir.
Not: API key'i Dart kaynak koduna yazma. Mobil uygulamada kullanılan key yine APK içinden teknik olarak çıkarılabilir; ticari/üretim sürümünde backend proxy kullan.
