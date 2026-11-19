DARWIN TRADING MOBILE - STARTER MILESTONE
========================================

This package contains two separate projects:
  api/DarwinTradingMobileAPI  - ASP.NET Core 10 API for the store Windows PC
  mobile                      - Flutter Android/iPhone UI source

IMPORTANT
---------
This is a working starter foundation, not the finished production rollout. It currently includes:
- Existing DTSIMS2 PBKDF2-SHA256 login verification and JWT sessions
- Dashboard counts, category listing/creation, product listing, supplier listing, delivery listing
- Flutter login, dashboard, product list, delivery list and local offline notes/draft storage
- The local offline draft table is deliberately not allowed to post inventory.

Not yet included: complete delivery editor/item workflow, reliable background sync queue, barcode camera scanning,
product photo upload, full role_permissions/user_permissions enforcement, and device deployment/testing.
Do not use this package to post live inventory until those features and the API have been tested against a COPY
of your database. The API must be hardened and permission checks added before production use.

API SETUP IN VISUAL STUDIO 2026
-------------------------------
1. Close the project you just created or keep it as a backup.
2. Extract this package.
3. Open api/DarwinTradingMobileAPI/DarwinTradingMobileAPI.csproj in Visual Studio 2026.
4. Edit appsettings.json. Set the exact database name, and create a dedicated MySQL account for the API.
   Do not use the MySQL root account. Give it only the database permissions the API needs.
5. Replace Jwt:Key with a long random secret (at least 32 characters). Never share this key.
6. Restore NuGet packages, then run the API. Swagger is available in Development at /swagger.
7. Test GET /health first. Then test login using an existing DTSIMS2 account.

Do not expose MySQL port 3306 to the internet. Only the API should be reachable by phones, preferably through
Tailscale/private networking and HTTPS. Configure Windows Firewall accordingly.

FLUTTER APP SETUP
-----------------
Install Flutter SDK and Android Studio (Android SDK tools). In a terminal:
  cd mobile
  flutter pub get
  flutter run

For Android emulator, the default API URL is http://10.0.2.2:5000.
For a physical Android phone, change Api.base in mobile/lib/main.dart to the Windows PC's LAN/Tailscale IP and
use an HTTPS endpoint for real deployments. iPhone builds require macOS with Xcode; a Windows PC cannot build
iOS apps locally.

DATABASE COMPATIBILITY NOTES
----------------------------
The API queries the existing tables and columns found in the supplied DTSIMS2 source:
users (PBKDF2-SHA256$... password_hash), products, categories, suppliers, deliveries, delivery_items,
and inventory_movements. Product photo fields are not present in the supplied products table.

The archive supplied for review contained a database backup and a signing-key file. Do not put those files in
the mobile/API package or share them. If real credentials/private keys were included in any shared archive,
rotate them. Never send database backups, passwords, JWT secrets, or private signing keys in chat.

NEXT DEVELOPMENT MILESTONE
--------------------------
Complete delivery batch creation/editing, line item add/update/remove, server-side send-to-inventory transaction
matching the desktop DeliveryData.SendToInventory logic, then implement an idempotent offline sync queue and
server-side role/module permission checks. Only after integration tests should the API be connected to live stock.
