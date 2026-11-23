# 🔒 Odak Kilidi

Belirlediğin saatlerde Instagram, YouTube gibi uygulamaları ve Chrome'daki siteleri kapatır.
Telefonda (Android) ve bilgisayarda (Windows) ayrı ayrı, aynı anda çalışır.

## Nasıl çalışır?
- **Kurallar:** Her kuralın kendi adı, günleri, saatleri ve hedefleri var. Örn. *Instagram → hafta içi 09:00–17:00*, *YouTube → her gün 23:00–07:00*.
- **📅 Rutin kural:** Seçtiğin gün ve saatlerde her hafta otomatik kilitlenir.
- **📚 Ders kuralı:** Ana ekrandaki **Ders başlat** ile seçtiğin süre (25 dk – 4 saat) boyunca kilitlenir, erken bitirilemez. İstersen saat de eklersin, o saatlerde otomatik kilitlenir.
- **⭐ Favoriler:** Instagram, YouTube, TikTok, X, Facebook, Reddit, Twitch, Netflix, Snapchat, Discord, Pinterest, WhatsApp — tek tıkla uygulama + site birlikte. Listede olmayanları "Diğer uygulamalar / siteler"den eklersin.
- Saatler elle yazılmaz, **saat seçiciden** seçilir. Başlangıç = bitiş → tüm gün. 23:00 → 07:00 gece yarısını aşar.
- Kısıtlamayı **artıran** değişiklik **hemen**, **azaltan** değişiklik (saat kısaltma, hedef çıkarma, kural silme) **ertesi gün** geçerli olur.
- **Kaldırma:** "Kaldırma izni iste" → izin **ertesi gün, bir gün boyunca** açılır.

---

## 1) GitHub'a yükleme (APK otomatik derlenir)
1. GitHub'da yeni bir **Private** depo aç: `odak-kilidi`
2. Bu klasördeki her şeyi depoya yükle (`.github` klasörü dahil).
   - Web'den sürükle-bırak `.github` klasörünü almazsa: **Add file → Create new file** de, adı
     `.github/workflows/build.yml` yaz ve dosyanın içeriğini yapıştır.
3. **Actions** sekmesinde "Derle" çalışır (~5 dk). Bitince **Releases**'ta iki dosya çıkar:
   - `OdakKilidi.apk` → telefon
   - `OdakKilidi-Windows.zip` → bilgisayar
4. Sonradan kod değişirse yükle → yeni sürüm otomatik çıkar. APK eskisinin **üstüne** kurulur (silmek gerekmez).

> Derleme hata verirse Actions'taki kırmızı adımın hata yazısını kopyalayıp Claude'a gönder.

---

## 2) Telefon (Android) kurulumu
1. `OdakKilidi.apk`'yı indir ve kur ("Bilinmeyen kaynaklara izin ver" diye sorarsa izin ver).
2. **Android 13 ve üstü:** Ayarlar → Uygulamalar → **Odak Kilidi** → sağ üst **⋮** → **Kısıtlanmış ayarlara izin ver**.
   (Bu yapılmazsa erişilebilirlik iznini açamazsın.)
3. Odak Kilidi'ni aç:
   - **Erişilebilirlik ayarlarını aç** → *Yüklü uygulamalar* → Odak Kilidi → **Aç**
   - **Cihaz yöneticisini etkinleştir** → **Etkinleştir**
4. Yasak saatleri yaz, engellenecek uygulamaları işaretle, siteleri yaz → **Kaydet**.

**Ne yapıyor?**
- Yasak saatte işaretli uygulama açılınca ana ekrana atar, kilit ekranı gösterir.
- Chrome, Samsung Internet, Edge, Brave, Opera, Firefox'ta yasaklı siteye girilince kapatır.
- Koruma: Ayarlar'da Odak Kilidi'nin göründüğü ekranlar (uygulama bilgisi, erişilebilirlik, cihaz yöneticisi, silme ekranı) açılınca geri atar. Bu yüzden erişilebilirlik ve cihaz yöneticisi kapatılamaz, uygulama silinemez.

---

## 3) Bilgisayar (Windows) kurulumu
1. `OdakKilidi-Windows.zip`'i indir, bir klasöre çıkar.
2. **Kur.bat**'a çift tıkla → yönetici izni sor → **Evet**.
3. Masaüstündeki **Odak Kilidi** kısayolunu aç → saatleri, programları, siteleri yaz → **Kaydet**.

**Ne yapıyor?**
- Arka planda **SYSTEM** hesabıyla çalışan bir görev (kapatılsa bile 1 dk içinde geri açılır, bilgisayar açılınca kendiliğinden başlar).
- Yasak saatte listedeki programları kapatır (örn. `Discord`, `WhatsApp`).
- Siteleri iki yoldan engeller:
  - **Chrome / Edge / Brave yönetici politikası** (`URLBlocklist`) — gizli sekmede de geçerli, tarayıcıdan kaldırılamaz.
  - **hosts dosyası** — Firefox dahil tüm tarayıcılarda.
- Yasak saatte Görev Zamanlayıcı / Hizmetler / Kayıt Defteri (mmc, regedit) açılınca kapatır.
- Kaldırma: Ayarlardan izin iste → ertesi gün ayar penceresinde **Şimdi kaldır** çıkar (veya `Kaldir.bat`).
- Güncelleme: yeni zip'teki `Kur.bat`'ı çalıştır, ayarların korunur.

---

## ⚠️ Dürüst sınırlar
Kendi cihazında %100 kırılamaz bir engelleyici yok. Amaç anlık isteğe yenik düşmeni engellemek.
- **Android:** Güvenli mod veya fabrika ayarlarına sıfırlama korumayı aşar. Ayarlar'da uygulama listesine bakarken Odak Kilidi'ye tıklarsan atılırsın (normal).
- **Windows:** Yönetici yetkisi olan, ne yaptığını bilen biri komut satırından görevi silebilir. Bunu bilerek yapmak "anlık istek" değildir 🙂
