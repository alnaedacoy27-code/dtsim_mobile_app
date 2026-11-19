# Darwin Trading Mobile — Milestone 1

This is the Flutter mobile UI starter that sits beside (not inside) the existing `DarwinTradingMobileAPI` ASP.NET Core project.

## Included
- Login screen with API login placeholder and demo preview mode
- Dashboard
- Product catalogue sample screen
- Barcode scanner screen
- Delivery drafts stored locally using SharedPreferences
- API base URL setting

## Open and run
1. Extract this folder beside `DarwinTradingMobileAPI`.
2. Open a terminal in `darwin_trading_mobile`.
3. Run:
   ```bash
   flutter pub get
   flutter run
   ```

## Important configuration
- Android emulator reaches the Windows host using `http://10.0.2.2:5159` by default.
- A physical phone must use the PC's LAN/Tailscale address and a properly configured HTTPS certificate.
- Login currently calls `POST /api/auth/login` with `{ "username": "...", "password": "..." }`. This is a placeholder contract; confirm/update it to match the actual API controller and response.
- Product/dashboard figures are sample placeholders, not live database information.
- Delivery drafts are local only. There is no inventory posting or synchronization yet. Posting to stock must remain server-side and use the existing transactional DTSIMS2 logic.

## Next integration milestone
Inspect the API controllers and existing DTSIMS2 delivery routines, then implement matching authenticated endpoints for login, products, suppliers, delivery batches/items, draft synchronization, and inventory posting.
