# App Store Connect metadata

Source of truth for what is pasted into App Store Connect. No printer brand
anywhere in this file except the App Review reply, which says none is used.
Limits: name 30, subtitle 30, keywords 100, promotional text 170 characters.

## App information

- Name: `Scan to Me` (fallback if taken: `Scan to Me: Printer to Phone`)
- Subtitle: `Scans from your printer, here`
- Bundle ID: `com.obarlier.scantome`
- SKU: `scantome-ios`
- Primary category: Productivity; secondary: Utilities
- Support URL: https://olibar.github.io/scan-to-me/
- Marketing URL: https://olibar.github.io/scan-to-me/
- Privacy Policy URL: https://olibar.github.io/scan-to-me/privacy/
- Copyright: `2026 Olivier Barlier`
- Age rating: 4+ (no objectionable content)
- App Privacy: Data Not Collected

## Keywords

```
scan,scanner,printer,all-in-one,pdf,jpeg,wifi,scan to computer,document,multipage,feeder,receive
```

## Promotional text

```
Press Scan on your printer, pick your iPhone, and the pages land in Files as a PDF. No cables, no cloud, no account.
```

## Description

```
Scan to Me turns your iPhone or iPad into a destination for the Scan to Computer button of your network all-in-one printer.

Press Scan on the printer, choose Computer, pick your phone from the list, and the pages arrive over Wi-Fi a few seconds later, as a PDF or as JPEG images.

- Uses the Scan to Computer button on the printer's own panel: no cables, no cloud, no account.
- Multi-page PDFs, page by page from the glass or the whole stack from the document feeder.
- Saves into the app's folder, any folder in Files, iCloud Drive or another file provider. JPEG scans can also go to Photos.
- Finds printers on your network automatically, or add one by IP address. Several printers at once.
- Follows the printer when its network address changes.
- Private by design: scans travel only between the printer and your device. Nothing is uploaded; no analytics, no tracking.

REQUIREMENTS
A network all-in-one printer with a Scan to Computer function, on the same Wi-Fi network as your device. The list of printers known to work is on our website; if yours is not listed, tell us and we will look into it.

Your phone appears on the printer while Scan to Me is open and listening: iOS does not let apps listen in the background.

Scan to Me is an independent app, not affiliated with any printer manufacturer.
```

## What's New (1.0.0)

```
First release.
```

## Screenshots

6.9" iPhone (1320x2868) and 13" iPad (2064x2752). Before taking them:

- Add the printer by IP address so the list shows an address, not a model
  name: the Bonjour name the printer announces contains its brand.
- Rename the saved scans and the "Name shown on the printer" to neutral
  values; no printer photos, logos or model names in any frame.

## App Review Information

Sign-in required: no.

Notes:

```
Scan to Me receives scans from a network all-in-one printer when the user presses Scan on the printer's own control panel. It needs such a printer on the same Wi-Fi network, so a screen recording of a complete scan on a real printer is attached.

To try it: Printers tab > + > pick the printer found on the network (or enter its IP address) > Listen tab > Start listening. On the printer: Scan > Computer > the phone's name > Start. The PDF appears under Recent scans and in Files > On My iPhone > Scan to Me.

The app talks only to the printer on the local network (plain HTTP to the printer's built-in web interface); it has no server, no account and no analytics.

Third-party content: the app contains none and retrieves none. No printer manufacturer's code, SDK, logo, image or document is included, and no brand is named in the app or its metadata. The app is independent and not affiliated with any printer manufacturer; the printers known to work are listed on the support website only.
```

Attachment: screen recording of a real scan (phone screen and printer panel).

## Reply to App Review if Guideline 5.2 comes up again

This is a new app record, so the earlier rejection (filed against the SiniMed
record) has no thread here; the Notes above pre-empt it. If App Review raises
5.2 again, paste this into the Resolution Center:

```
Hello,

Thank you for the review. We have resolved the issue by removing all third-party references, as suggested:

1. The app name, subtitle, keywords, description, screenshots and every text inside the app no longer name any printer manufacturer, brand or product line. The app is described generically as working with network all-in-one printers that offer a Scan to Computer function.

2. The app contains no third-party content and retrieves none. It includes no code, SDK, library, firmware, logo, image, font or document from a printer manufacturer; all code and artwork are our own. The app does not modify the printer, unlock features or bypass any access control.

3. How the app works: the user's own printer offers, on the user's local network, a built-in web interface through which a device can register as a scan destination and receive the pages the user scans at the printer. Scan to Me uses that interface, on the user's initiative and with the user's own device, exactly as a desktop computer on the same network would.

4. Compatibility details are given only on our support website, which states that the app is independent and not affiliated with or endorsed by any printer manufacturer, and that product names are used only to describe compatibility.

A screen recording of a complete scan is attached in App Review Information.

Thank you,
Olivier Barlier
```
