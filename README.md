# Klawiatura iOS do skanowania kodów kreskowych/QR

Ten projekt składa się z:
- Aplikacji kontenerowej (SwiftUI) z modułem skanowania (VisionKit / AVFoundation fallback)
- Rozszerzenia klawiatury (Keyboard Extension), które:
  - uruchamia skaner w aplikacji
  - po powrocie wstawia zeskanowane kody do aktywnego pola w innej aplikacji

W trybie wielu skanów kody są wstawiane z separatorami nowej linii, co zwykle powoduje przejście do kolejnych komórek np. w Excelu (zachowanie zależne od aplikacji docelowej).

WAŻNE ograniczenie iOS: rozszerzenia klawiatury NIE mają dostępu do aparatu. Skanowanie odbywa się w aplikacji kontenerowej, a wyniki są przekazywane do klawiatury poprzez App Group.

## Struktura folderów

- `App/` – aplikacja kontenerowa (SwiftUI)
- `KeyboardExtension/` – rozszerzenie klawiatury (`UIInputViewController`)
- `Shared/` – kod współdzielony (App Group storage, modele, routing URL)

## Szybki start (konfiguracja w Xcode)

1) Utwórz nowy projekt iOS App w Xcode (SwiftUI, Swift). Nazwa np. "BarcodeKeyboard".
2) Dodaj nowy Target: App Extension → Custom Keyboard Extension. Nazwa np. "KeyboardExtension".
3) Skonfiguruj App Group dla obu targetów:
   - W obu targetach w zakładce Signing & Capabilities dodaj App Groups.
   - Dodaj grupę np. `group.pl.twojefirma.klawiatura` i zaznacz ją w obu targetach.
   - Zaktualizuj stałą `SharedStorage.appGroupIdentifier` w `Shared/SharedStorage.swift`.
4) Uprawnienia i Info.plist:
   - W aplikacji: dodaj `NSCameraUsageDescription` (np. "Aplikacja używa aparatu do skanowania kodów").
   - W aplikacji: dodaj URL Scheme `barcodekb` (URL Types), by klawiatura mogła uruchomić skaner (np. `barcodekb://scan?mode=single`).
   - W rozszerzeniu klawiatury: w `Info.plist` ustaw `NSExtensionPointIdentifier = com.apple.keyboard-service` oraz `RequestsOpenAccess = YES` (w `NSExtensionAttributes`).
5) Skopiuj pliki z tego repo do odpowiednich grup w projekcie:
   - `App/*` do targetu aplikacji
   - `KeyboardExtension/*` do targetu rozszerzenia
   - `Shared/*` do obu targetów (zaznacz w Target Membership)
6) Zbuduj i uruchom aplikację na urządzeniu z iOS 16+ (VisionKit DataScanner). Na starszych/nieobsługiwanych urządzeniach działa fallback AVFoundation.
7) Włącz klawiaturę w Ustawienia → Ogólne → Klawiatura → Klawiatury → Dodaj nową… → wybierz Twoją klawiaturę → zezwól na Pełny Dostęp.

## Użycie

- Tryb pojedynczy: uruchom z klawiatury → automatycznie po zeskanowaniu kod zostanie zapisany i po powrocie do pola wstawiony od razu.
- Tryb wielu: uruchom z klawiatury → skanuj wiele kodów (w prawym górnym rogu ikona z licznikiem) → zakończ → po powrocie do pola klawiatura wstawi wszystkie kody, oddzielone nową linią.

## Dostosowanie dla Excela / arkuszy

Wstawianie wielu kodów używa separatora nowej linii ("\n"). W większości arkuszy powoduje to przejście do kolejnych komórek w dół. Jeśli Twoja aplikacja wymaga innego separatora (np. Tab), zmień `TextInsertionFormatter.joinedText(for:)` w `Shared/TextInsertionFormatter.swift`.

## Wymagania

- iOS 15+ (AVFoundation fallback), iOS 16+ dla VisionKit DataScanner
- Urządzenie z aparatem
- Xcode 15+

## Schemat przepływu

1) Klawiatura → otwiera `barcodekb://scan?mode=single|multi`
2) Aplikacja → uruchamia skaner (reticle, podświetlenie wykrytego kodu, licznik)
3) Zakończenie → zapis kodów do App Group
4) Klawiatura (po ponownym wyświetleniu) → odczytuje i wstawia kody do aktywnego pola

## Uwaga dot. prywatności

Dane są przechowywane wyłącznie lokalnie w App Group (UserDefaults). Nie ma połączenia sieciowego.

