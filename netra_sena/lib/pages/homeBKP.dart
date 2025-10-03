// lib/pages/home.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../services/api_service.dart';

class HomePageContent extends StatefulWidget {
  const HomePageContent({super.key});

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> {
  // ====== Configure Backend / Model URLs HERE ======
  // Leave verify empty if you don't want verify POSTs from the app
  final String _verifyBaseUrl = '';

  // OCR model endpoints (use the exact working paths)
  final String _dlOcrUrl = 'https://dl-extractor-api-209690283535.us-central1.run.app/extract-dl';
  final String _rcOcrUrl = 'https://my-ml-api-995937866035.us-central1.run.app/recognize_plate/';

  // Field names used when sending multipart to each OCR endpoint.
  final String _dlOcrFieldName = 'dl_image'; // as used in your curl
  final String _rcOcrFieldName = 'file';
  // ================================================

  // App theme colors to match government portal
  static const Color _primaryBlue = Color(0xFF1E3A8A);
  static const Color _lightGray = Color(0xFFF8FAFC);
  static const Color _borderGray = Color(0xFFE2E8F0);
  static const Color _textGray = Color(0xFF64748B);

  // Controllers & state for the Home UI
  final TextEditingController _dlController = TextEditingController();
  final TextEditingController _rcController = TextEditingController();

  String? _dlImageName;
  String? _rcImageName;
  String? _driverImageName;

  // Keep references to actual picked files so we can attach them later
  XFile? _lastDlXFile;
  PlatformFile? _lastDlPFile;

  XFile? _lastRcXFile;
  PlatformFile? _lastRcPFile;

  XFile? _lastDriverXFile;
  PlatformFile? _lastDriverPFile;

  // Loading / extracting states
  bool _isVerifying = false;
  bool _dlExtracting = false;
  bool _rcExtracting = false;

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    _dlController.dispose();
    _rcController.dispose();
    super.dispose();
  }

  // ----------------- Helpers: create MultipartFile ---------------------
  Future<http.MultipartFile?> _makeMultipartFromPicked({
    required String fieldName,
    XFile? xfile,
    PlatformFile? pfile,
  }) async {
    try {
      if (!kIsWeb && xfile != null && xfile.path.isNotEmpty) {
        final filename = p.basename(xfile.path);
        return await http.MultipartFile.fromPath(fieldName, xfile.path, filename: filename);
      }

      if (pfile != null) {
        if (pfile.bytes != null) {
          return http.MultipartFile.fromBytes(fieldName, pfile.bytes!, filename: pfile.name);
        } else if (pfile.path != null && pfile.path!.isNotEmpty) {
          return await http.MultipartFile.fromPath(fieldName, pfile.path!, filename: pfile.name);
        }
      }

      if (xfile != null) {
        final bytes = await xfile.readAsBytes();
        return http.MultipartFile.fromBytes(fieldName, bytes, filename: xfile.name);
      }
    } catch (e) {
      // ignore and return null
    }
    return null;
  }


  Future<void> _uploadForOcrAndFill({
    required String uploadUrl,
    required String primaryFieldName,
    required bool isDlModel,
    XFile? xfile,
    PlatformFile? pfile,
    required ValueSetter<String?> setFileName,
    required TextEditingController controller,
    required VoidCallback setExtractingTrue,
    required VoidCallback setExtractingFalse,
  }) async {
    setExtractingTrue();
    controller.text = 'Extracting...';

    try {
      // Fix/append model-specific path if user provided a base host without path
      String effectiveUrl = uploadUrl;
      if (effectiveUrl.contains('my-ml-api-995937866035.us-central1.run.app') &&
          !effectiveUrl.contains('recognize_plate')) {
        effectiveUrl = '${effectiveUrl.replaceAll(RegExp(r'/+$'), '')}/recognize_plate/';
        debugPrint('Adjusted RC URL to: $effectiveUrl');
      }
      if (effectiveUrl.contains('dl-extractor-api-209690283535.us-central1.run.app') &&
          !effectiveUrl.contains('extract-dl')) {
        effectiveUrl = '${effectiveUrl.replaceAll(RegExp(r'/+$'), '')}/extract-dl';
        debugPrint('Adjusted DL URL to: $effectiveUrl');
      }

      // Choose field candidates: for DL prefer dl_image, for RC prefer file
      final List<String> fieldCandidates = isDlModel
          ? [primaryFieldName, 'dl_image', 'image', 'file']
          : [primaryFieldName, 'file'];

      final Uri uri = Uri.parse(effectiveUrl);

      bool success = false;

      for (final fieldName in fieldCandidates) {
        final mp = await _makeMultipartFromPicked(fieldName: fieldName, xfile: xfile, pfile: pfile);
        if (mp == null) {
          debugPrint('Could not build multipart for field "$fieldName"');
          continue;
        }

        final req = http.MultipartRequest('POST', uri);
        req.files.clear();
        req.files.add(mp);

        debugPrint('Posting to $effectiveUrl (field="$fieldName")');
        try {
          final streamed = await req.send();
          final res = await http.Response.fromStream(streamed);

          debugPrint('Response status ${res.statusCode} from $effectiveUrl (field="$fieldName")');

          if (res.statusCode != 200) {
            debugPrint('Body: ${res.body}');
            continue;
          }

          final body = res.body.isNotEmpty ? jsonDecode(res.body) : null;

          String? extractedValue;

          if (isDlModel) {
            // 1) prefer dl_numbers[0]
            if (body != null &&
                body['dl_numbers'] != null &&
                body['dl_numbers'] is List &&
                (body['dl_numbers'] as List).isNotEmpty) {
              final first = (body['dl_numbers'] as List).first;
              if (first != null && first is String && first.trim().isNotEmpty) {
                extractedValue = first.trim();
              }
            }

            // 2) fallback to extracted_text if exists
            if (extractedValue == null && body != null && body['extracted_text'] != null) {
              final t = (body['extracted_text'] as String).trim();
              if (t.isNotEmpty) extractedValue = t;
            }

            // 3) fallback: hunt in raw_text for DL-like token
            if (extractedValue == null && body != null && body['raw_text'] != null) {
              String raw = (body['raw_text'] as String).toUpperCase();

              // Normalize: replace non-alphanumeric with space (keeps letters+digits)
              final cleaned = raw.replaceAll(RegExp(r'[^A-Z0-9\s]'), ' ');
              // Find candidate tokens 6..25 chars long
              final tokenReg = RegExp(r'\b([A-Z0-9]{6,25})\b', caseSensitive: false);
              final matches = tokenReg.allMatches(cleaned).map((m) => m.group(1)!).toList();

              String? best;
              for (final tok in matches) {
                final letters = RegExp(r'[A-Z]').allMatches(tok).length;
                final digits = RegExp(r'\d').allMatches(tok).length;
                // heuristic: at least one letter and >=4 digits (DL numbers are long)
                if (letters >= 1 && digits >= 4) {
                  best = tok;
                  break;
                }
              }

              // 4) looser pattern if none found above
              if (best == null) {
                final loose = RegExp(r'([A-Z]{1,2}\s*\d{2,}\s*[A-Z0-9]{0,3}\s*\d{3,})', caseSensitive: false);
                final m = loose.firstMatch(raw);
                if (m != null) best = m.group(1);
              }

              if (best != null) {
                // normalize
                extractedValue = best.replaceAll(RegExp(r'\s+'), '');
              }
            }
          } else {
            // RC model: prefer plate_number, then extracted_text, then raw_text regex
            if (body != null && body['plate_number'] != null && (body['plate_number'] as String).trim().isNotEmpty) {
              extractedValue = (body['plate_number'] as String).trim();
            }
            if (extractedValue == null && body != null && body['extracted_text'] != null) {
              final t = (body['extracted_text'] as String).trim();
              if (t.isNotEmpty) extractedValue = t;
            }
            if (extractedValue == null && body != null && body['raw_text'] != null) {
              final raw = (body['raw_text'] as String).toUpperCase();
              final reg = RegExp(r'([A-Z]{2}\s*\d{1,2}\s*[A-Z]{0,2}\s*\d{3,4})', caseSensitive: false);
              final match = reg.firstMatch(raw);
              if (match != null) extractedValue = match.group(1)?.replaceAll(RegExp(r'\s+'), '');
            }
          }

          if (extractedValue != null && extractedValue.isNotEmpty) {
            controller.text = extractedValue;
            if (body != null && body['filename'] != null) {
              setFileName(body['filename'] as String);
            }
            success = true;
            debugPrint('OCR success from $effectiveUrl (field="$fieldName"), extracted="$extractedValue"');
            break;
          } else {
            debugPrint('OCR returned 200 but no usable text. Body: ${res.body}');
            continue;
          }
        } catch (e) {
          debugPrint('Exception during OCR POST to $effectiveUrl (field="$fieldName"): $e');
          continue;
        }
      }

      if (!success) {
        _showErrorSnackBar('OCR failed for the provided endpoint. Check endpoint/field names.');
        controller.text = '';
      }
    } catch (err) {
      controller.text = '';
      _showErrorSnackBar('An error occurred while communicating with the OCR service.');
    } finally {
      setExtractingFalse();
    }
  }



  // ----------------- Pick handlers (camera/gallery/file) --------------
  Future<void> _pickDlImage() async {
    _showImageSourceOptions(
      title: 'Select Driving License',
      onCamera: () async {
        final XFile? picked = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (picked != null) {
          setState(() {
            _dlImageName = picked.name;
            _lastDlXFile = picked;
            _lastDlPFile = null;
          });
          await _uploadForOcrAndFill(
            uploadUrl: _dlOcrUrl,
            primaryFieldName: _dlOcrFieldName,
            isDlModel: true,
            xfile: picked,
            setFileName: (s) => setState(() => _dlImageName = s),
            controller: _dlController,
            setExtractingTrue: () => setState(() => _dlExtracting = true),
            setExtractingFalse: () => setState(() => _dlExtracting = false),
          );
        }
      },
      onGallery: () async {
        final XFile? picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (picked != null) {
          setState(() {
            _dlImageName = picked.name;
            _lastDlXFile = picked;
            _lastDlPFile = null;
          });
          await _uploadForOcrAndFill(
            uploadUrl: _dlOcrUrl,
            primaryFieldName: _dlOcrFieldName,
            isDlModel: true,
            xfile: picked,
            setFileName: (s) => setState(() => _dlImageName = s),
            controller: _dlController,
            setExtractingTrue: () => setState(() => _dlExtracting = true),
            setExtractingFalse: () => setState(() => _dlExtracting = false),
          );
        }
      },
      onFile: () async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final pfile = result.files.single;
          setState(() {
            _dlImageName = pfile.name;
            _lastDlPFile = pfile;
            _lastDlXFile = null;
          });
          await _uploadForOcrAndFill(
            uploadUrl: _dlOcrUrl,
            primaryFieldName: _dlOcrFieldName,
            isDlModel: true,
            pfile: pfile,
            setFileName: (s) => setState(() => _dlImageName = s),
            controller: _dlController,
            setExtractingTrue: () => setState(() => _dlExtracting = true),
            setExtractingFalse: () => setState(() => _dlExtracting = false),
          );
        }
      },
    );
  }

  Future<void> _pickRcImage() async {
    _showImageSourceOptions(
      title: 'Select Vehicle Registration (RC)',
      onCamera: () async {
        final XFile? picked = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (picked != null) {
          setState(() {
            _rcImageName = picked.name;
            _lastRcXFile = picked;
            _lastRcPFile = null;
          });
          await _uploadForOcrAndFill(
            uploadUrl: _rcOcrUrl,
            primaryFieldName: _rcOcrFieldName,
            isDlModel: false,
            xfile: picked,
            setFileName: (s) => setState(() => _rcImageName = s),
            controller: _rcController,
            setExtractingTrue: () => setState(() => _rcExtracting = true),
            setExtractingFalse: () => setState(() => _rcExtracting = false),
          );
        }
      },
      onGallery: () async {
        final XFile? picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (picked != null) {
          setState(() {
            _rcImageName = picked.name;
            _lastRcXFile = picked;
            _lastRcPFile = null;
          });
          await _uploadForOcrAndFill(
            uploadUrl: _rcOcrUrl,
            primaryFieldName: _rcOcrFieldName,
            isDlModel: false,
            xfile: picked,
            setFileName: (s) => setState(() => _rcImageName = s),
            controller: _rcController,
            setExtractingTrue: () => setState(() => _rcExtracting = true),
            setExtractingFalse: () => setState(() => _rcExtracting = false),
          );
        }
      },
      onFile: () async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final pfile = result.files.single;
          setState(() {
            _rcImageName = pfile.name;
            _lastRcPFile = pfile;
            _lastRcXFile = null;
          });
          await _uploadForOcrAndFill(
            uploadUrl: _rcOcrUrl,
            primaryFieldName: _rcOcrFieldName,
            isDlModel: false,
            pfile: pfile,
            setFileName: (s) => setState(() => _rcImageName = s),
            controller: _rcController,
            setExtractingTrue: () => setState(() => _rcExtracting = true),
            setExtractingFalse: () => setState(() => _rcExtracting = false),
          );
        }
      },
    );
  }

  Future<void> _pickDriverImage() async {
    _showImageSourceOptions(
      title: 'Select Driver Image',
      onCamera: () async {
        final XFile? picked = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (picked != null) {
          setState(() {
            _driverImageName = picked.name;
            _lastDriverXFile = picked;
            _lastDriverPFile = null;
          });
        }
      },
      onGallery: () async {
        final XFile? picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (picked != null) {
          setState(() {
            _driverImageName = picked.name;
            _lastDriverXFile = picked;
            _lastDriverPFile = null;
          });
        }
      },
      onFile: () async {
        final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
        if (result != null && result.files.isNotEmpty) {
          final pfile = result.files.single;
          setState(() {
            _driverImageName = pfile.name;
            _lastDriverPFile = pfile;
            _lastDriverXFile = null;
          });
        }
      },
    );
  }

  // ----------------- Bottom sheet (minimal) ----------------------------
  void _showImageSourceOptions({
    required String title,
    required VoidCallback onCamera,
    required VoidCallback onGallery,
    required VoidCallback onFile,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Take Photo (Camera)'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onCamera();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Pick from Gallery'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Choose file (Files)'),
                  subtitle: const Text('Images and PDFs'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onFile();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

// ---------- Replace your existing _handleVerification with this ----------
  Future<void> _handleVerification() async {
    final dlNumber = _dlController.text.trim();
    final rcNumber = _rcController.text.trim();

    if (dlNumber.isEmpty && rcNumber.isEmpty && _driverImageName == null) {
      _showErrorSnackBar('Please provide a DL number, a Vehicle number, or a Driver Image to verify.');
      return;
    }

    // If verify backend not configured, show a local summary dialog instead of calling backend.
    if (_verifyBaseUrl.trim().isEmpty) {
      final summary = {
        'dl_number': dlNumber,
        'rc_number': rcNumber,
        'driverImageProvided': _driverImageName != null,
        'note': 'Verification endpoint not configured in app (_verifyBaseUrl is empty).'
      };
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Verification (not sent)'),
          content: SingleChildScrollView(child: Text(const JsonEncoder.withIndent('  ').convert(summary))),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          ],
        ),
      );
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    try {
      // Prepare driver Image File (if any)
      File? driverFile;
      // _lastDriverXFile assumed to be an XFile (image_picker) and _lastDriverPFile a PlatformFile (file_picker)
      if (_lastDriverXFile != null && _lastDriverXFile!.path.isNotEmpty) {
        driverFile = File(_lastDriverXFile!.path);
      } else if (_lastDriverPFile != null && _lastDriverPFile!.path != null && _lastDriverPFile!.path!.isNotEmpty) {
        driverFile = File(_lastDriverPFile!.path!);
      }

      // Call ApiService.verifyDriver
      final api = ApiService();
      final result = await api.verifyDriver(
        dlNumber: dlNumber.isNotEmpty ? dlNumber : null,
        rcNumber: rcNumber.isNotEmpty ? rcNumber : null,
        location: 'Toll-Plaza-1',
        tollgate: 'Gate-A',
        driverImage: driverFile,
      );

      if (result['ok'] == true) {
        final body = result['data'];
        // body expected to be the server JSON { dlData, rcData, driverData, suspicious }
        _showVerificationResultDialog(body);
      } else {
        // Prefer server message if available
        final message = result['message'] ??
            (result['body'] != null ? const JsonEncoder.withIndent('  ').convert(result['body']) : 'Unknown error');
        _showErrorSnackBar('Verification failed: $message');
      }
    } catch (err) {
      _showErrorSnackBar('An error occurred during verification. Please check the server. Error: $err');
    } finally {
      setState(() {
        _isVerifying = false;
        // Reset selected names (like your JS did)
        _dlImageName = null;
        _rcImageName = null;
        _driverImageName = null;
        // keep extracted text in controllers
        _lastDlXFile = _lastDlPFile = null;
        _lastRcXFile = _lastRcPFile = null;
        _lastDriverXFile = _lastDriverPFile = null;
      });
    }
  }


// Replace _showVerificationResultDialog with this rich version:
  void _showVerificationResultDialog(dynamic body) {
    final Map<String, dynamic> mapBody = (body is Map) ? Map<String, dynamic>.from(body) : {'raw': body};

    final Map<String, dynamic>? dlData = mapBody['dlData'] is Map ? Map<String, dynamic>.from(mapBody['dlData']) : null;
    final Map<String, dynamic>? rcData = mapBody['rcData'] is Map ? Map<String, dynamic>.from(mapBody['rcData']) : null;
    final Map<String, dynamic>? driverData = mapBody['driverData'] is Map ? Map<String, dynamic>.from(mapBody['driverData']) : null;
    final bool suspiciousFlag = mapBody['suspicious'] == true;

    // Determine server-side suspicious reasons (mirror server logic as much as possible)
    final List<String> suspiciousReasons = [];
    if (dlData != null) {
      final dlStatus = (dlData['status'] ?? '').toString().toLowerCase();
      if (dlStatus == 'blacklisted') suspiciousReasons.add('Driving License is BLACKLISTED');
      if (dlStatus == 'not_found') suspiciousReasons.add('DL not found in DB');
    }
    if (rcData != null) {
      final rcStatus = (rcData['status'] ?? rcData['verification'] ?? '').toString().toLowerCase();
      if (rcStatus == 'blacklisted') suspiciousReasons.add('Vehicle / RC is BLACKLISTED');
      if (rcStatus == 'not_found') suspiciousReasons.add('RC / Vehicle not found in DB');
    }
    if (driverData != null) {
      final drvStatus = (driverData['status'] ?? '').toString().toUpperCase();
      if (drvStatus == 'ALERT') suspiciousReasons.add('Driver matched a SUSPECT (face recognition ALERT)');
      if (drvStatus == 'SERVICE_UNAVAILABLE') suspiciousReasons.add('Face recognition service unavailable');
    }
    if (suspiciousFlag && suspiciousReasons.isEmpty) {
      suspiciousReasons.add('System raised a suspicious flag (details in raw JSON)');
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setStateDialog) {
          return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('Verification Result', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                if (suspiciousFlag)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                    child: const Text('SUSPICIOUS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // --- Suspicious reasons summary ---
                if (suspiciousReasons.isNotEmpty) ...[
                  const Text('Alerts / Reasons', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  for (final r in suspiciousReasons)
                    Row(children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r, style: const TextStyle(fontWeight: FontWeight.w600))),
                    ]),
                  const Divider(),
                ],

                // --- DL Data ---
                const Text('Driving License (DL)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (dlData == null)
                  const Text('No DL data returned.')
                else
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _twoColumn('Status', dlData['status'] ?? 'N/A'),
                    _twoColumn('License No', dlData['licenseNumber'] ?? dlData['dl_number'] ?? 'N/A'),
                    _twoColumn('Name', dlData['name'] ?? 'N/A'),
                    _twoColumn('Validity', dlData['validity'] ?? 'N/A'),
                    _twoColumn('Phone', dlData['phone_number'] ?? 'N/A'),
                    // show any extra keys present in DL object that server might include
                    _optionalKeyList(dlData, ['other', 'extra']),
                  ]),
                const SizedBox(height: 12),
                const Divider(),

                // --- RC Data ---
                const Text('Vehicle / RC', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (rcData == null)
                  const Text('No RC data returned.')
                else
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // server sometimes returns status under 'status' or 'verification'
                    _twoColumn('Status', rcData['status'] ?? rcData['verification'] ?? 'N/A'),
                    _twoColumn('Regn No', rcData['regn_number'] ?? rcData['regn_number'] ?? 'N/A'),
                    _twoColumn('Owner', rcData['owner_name'] ?? 'N/A'),
                    _twoColumn('Maker Class', rcData['maker_class'] ?? 'N/A'),
                    _twoColumn('Vehicle Class', rcData['vehicle_class'] ?? 'N/A'),
                    _twoColumn('Wheel Type', rcData['wheel_type'] ?? 'N/A'),
                    _twoColumn('Engine No', rcData['engine_number'] ?? 'N/A'),
                    _twoColumn('Chassis No', rcData['chassis_number'] ?? 'N/A'),
                    if (rcData['crime_involved'] != null) _twoColumn('Crime Involved', rcData['crime_involved']),
                    _optionalKeyList(rcData, ['other', 'extra']),
                  ]),
                const SizedBox(height: 12),
                const Divider(),

                // --- Driver / Face Data ---
                const Text('Driver / Face Recognition', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (driverData == null)
                  const Text('No driver image / face data returned.')
                else
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _twoColumn('Status', driverData['status'] ?? 'N/A'),
                    if (driverData['name'] != null) _twoColumn('Name', driverData['name']),
                    if (driverData['message'] != null) _twoColumn('Message', driverData['message']),
                    _optionalKeyList(driverData, ['confidence', 'score', 'meta']),
                  ]),

                const SizedBox(height: 12),
                const Divider(),

                // Raw JSON viewer
                const Text('Raw JSON Response', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                  child: SelectableText(const JsonEncoder.withIndent('  ').convert(mapBody)),
                ),

                const SizedBox(height: 12),

                // DL usage button (calls API to fetch recent usage logs for this DL)
                if (dlData != null && (dlData['licenseNumber'] ?? dlData['dl_number']) != null)
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.list_alt),
                        label: const Text('View DL usage (2 days)'),
                        onPressed: () async {
                          final dlNum = (dlData['licenseNumber'] ?? dlData['dl_number']).toString();
                          // Show a small loading dialog while fetching
                          showDialog(
                            context: ctx2,
                            barrierDismissible: false,
                            builder: (loadingCtx) => const AlertDialog(
                              content: SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
                            ),
                          );
                          final api = ApiService();
                          final usage = await api.getDLUsage(dlNum);
                          Navigator.of(ctx2).pop(); // close loading
                          if (usage['ok'] == true) {
                            final data = usage['data'] ?? [];
                            _showDLUsageDialog(dlNum, data);
                          } else {
                            final msg = usage['message'] ?? 'Failed to fetch DL usage';
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      if (suspiciousReasons.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            // Copy reasons to clipboard or show a focused dialog
                            showDialog(
                              context: ctx2,
                              builder: (dctx) => AlertDialog(
                                title: const Text('Suspicious Reasons'),
                                content: SingleChildScrollView(child: Text(suspiciousReasons.join('\n'))),
                                actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('Close'))],
                              ),
                            );
                          },
                          child: const Text('View Suspicious Reasons'),
                        )
                    ],
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
            ],
          );
        });
      },
    );
  }

// Helper widget for two-column label/value
  Widget _twoColumn(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value == null ? 'N/A' : value.toString())),
        ],
      ),
    );
  }

// Helper to optionally show other keys (defensive)
  Widget _optionalKeyList(Map<String, dynamic> map, List<String> ignoreKeys) {
    // Show any keys not in ignoreKeys and not already displayed; keep limited to avoid huge output
    final displayed = <String>{
      'status',
      'licenseNumber',
      'dl_number',
      'name',
      'validity',
      'phone_number',
      'regn_number',
      'owner_name',
      'maker_class',
      'vehicle_class',
      'wheel_type',
      'engine_number',
      'chassis_number',
      'crime_involved',
      'verification',
      'message',
    };
    final extras = <String>[];
    for (final k in map.keys) {
      if (!displayed.contains(k) && !ignoreKeys.contains(k)) extras.add(k);
    }
    if (extras.isEmpty) return const SizedBox.shrink();
    // limit to first 8 extras
    final limited = extras.take(8);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text('Other fields:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        for (final k in limited) _twoColumn(k, map[k]),
        if (extras.length > 8) Text('+ ${extras.length - 8} more fields'),
      ],
    );
  }

// Show DL usage dialog (list of recent logs)
  void _showDLUsageDialog(String dlNumber, dynamic logs) {
    final List logsList = (logs is List) ? logs : [];
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('DL Usage: $dlNumber (last 2 days)'),
          content: SizedBox(
            width: double.maxFinite,
            child: logsList.isEmpty
                ? const Text('No recent usage logs found for this DL in last 2 days.')
                : ListView.separated(
              shrinkWrap: true,
              itemBuilder: (c, i) {
                final item = logsList[i] is Map ? Map<String, dynamic>.from(logsList[i]) : {'raw': logsList[i]};
                final ts = item['timestamp'] ?? item['time'] ?? '';
                return ListTile(
                  title: Text(item['vehicle_number'] ?? item['vehicle'] ?? 'Vehicle: N/A'),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (item['dl_number'] != null) Text('DL: ${item['dl_number']}'),
                    if (item['alert_type'] != null) Text('Alert: ${item['alert_type']}'),
                    if (item['description'] != null) Text('Desc: ${item['description']}'),
                    if (ts != null) Text('Time: ${ts.toString()}'),
                  ]),
                );
              },
              separatorBuilder: (_, __) => const Divider(),
              itemCount: logsList.length,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          ],
        );
      },
    );
  }
  // ----------------- Snackbars ----------------------------------------
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ----------------- Build UI (kept same & minimal) -------------------
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _lightGray,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header section with government branding
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'Driving License and Vehicle Registration Certificate Verification Portal',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _primaryBlue,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Main form container
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Driving License Section
                  _buildSectionHeader(
                    icon: Icons.credit_card,
                    title: 'Upload Driving License',
                    subtitle: 'Upload your driving license document',
                  ),
                  const SizedBox(height: 16),

                  _buildFileUploadCard(
                    label: 'Choose Driving License File',
                    fileName: _dlImageName,
                    onTap: _pickDlImage,
                    icon: Icons.upload_file,
                  ),

                  const SizedBox(height: 12),

                  _buildTextInput(
                    controller: _dlController,
                    label: 'Driving License Number',
                    hint: _dlExtracting ? 'Extracting...' : 'Select image or enter manually',
                    prefixIcon: Icons.confirmation_number,
                    enabled: !_dlExtracting,
                  ),

                  const SizedBox(height: 24),

                  // Vehicle Registration Section
                  _buildSectionHeader(
                    icon: Icons.directions_car,
                    title: 'Upload Vehicle Registration Number (Number Plate Number)',
                    subtitle: 'Upload your vehicle registration certificate',
                  ),
                  const SizedBox(height: 16),

                  _buildFileUploadCard(
                    label: 'Choose Vehicle Registration File',
                    fileName: _rcImageName,
                    onTap: _pickRcImage,
                    icon: Icons.upload_file,
                  ),

                  const SizedBox(height: 12),

                  _buildTextInput(
                    controller: _rcController,
                    label: 'Vehicle Number',
                    hint: _rcExtracting ? 'Extracting...' : 'Select image or enter manually',
                    prefixIcon: Icons.directions_car,
                    enabled: !_rcExtracting,
                  ),

                  const SizedBox(height: 24),

                  // Driver Image Section
                  _buildSectionHeader(
                    icon: Icons.person,
                    title: 'Upload Driver Image',
                    subtitle: 'Upload a clear photo of the driver',
                  ),
                  const SizedBox(height: 16),

                  _buildFileUploadCard(
                    label: 'Choose Driver Image File',
                    fileName: _driverImageName,
                    onTap: _pickDriverImage,
                    icon: Icons.person_add_alt_1,
                  ),

                  const SizedBox(height: 32),

                  // Verify Information Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isVerifying ? null : _handleVerification,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: Colors.grey.shade400,
                      ),
                      child: _isVerifying
                          ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Verifying...', style: TextStyle(fontSize: 16)),
                        ],
                      )
                          : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.verified_user, size: 20),
                          SizedBox(width: 8),
                          Text('Verify Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Info note
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade600, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AI-powered verification will extract information from uploaded documents automatically.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _primaryBlue, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: _textGray,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFileUploadCard({
    required String label,
    required String? fileName,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: _borderGray),
          borderRadius: BorderRadius.circular(8),
          color: fileName != null ? Colors.green.shade50 : _lightGray,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: fileName != null ? Colors.green.shade600 : _textGray,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                fileName ?? label,
                style: TextStyle(
                  fontSize: 14,
                  color: fileName != null ? Colors.green.shade700 : _textGray,
                  fontWeight: fileName != null ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
            if (fileName != null) Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(prefixIcon, size: 18),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _borderGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _borderGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
