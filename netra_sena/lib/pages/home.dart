// lib/pages/home.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:http_parser/http_parser.dart';

import 'verification.dart'; // <- uses verifyDriverAndShowDialog()

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
  final String _dlOcrUrl = 'https://dl-extractor-service-777302308889.us-central1.run.app';
  // UPDATED RC API endpoint
  final String _rcOcrUrl = 'https://enhanced-alpr-980624091991.us-central1.run.app/recognize_plate/';

  // Field names used when sending multipart to each OCR endpoint.
  final String _dlOcrFieldName = 'image_file';
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

  // Helper to know if we can enable the Verify button
  bool get _hasInput {
    if (_dlController.text.trim().isNotEmpty) return true;
    if (_rcController.text.trim().isNotEmpty) return true;
    if (_lastDriverXFile != null) return true;
    if (_lastDriverPFile != null) return true;
    return false;
  }

  // ----------------- Helpers: create MultipartFile ---------------------
  // Determine media type from filename extension; return null if unknown/non-image
  MediaType? _mediaTypeForFilename(String filename) {
    final ext = p.extension(filename).toLowerCase();
    if (ext == '.jpg' || ext == '.jpeg') return MediaType('image', 'jpeg');
    if (ext == '.png') return MediaType('image', 'png');
    if (ext == '.webp') return MediaType('image', 'webp');
    if (ext == '.bmp') return MediaType('image', 'bmp');
    if (ext == '.gif') return MediaType('image', 'gif');
    // Add other image types if needed
    return null;
  }

  bool _isImageFilename(String filename) => _mediaTypeForFilename(filename) != null;

  Future<http.MultipartFile?> _makeMultipartFromPicked({
    required String fieldName,
    XFile? xfile,
    PlatformFile? pfile,
  }) async {
    try {
      String? filename;
      if (!kIsWeb && xfile != null && xfile.path.isNotEmpty) {
        filename = p.basename(xfile.path);
        final mediaType = _mediaTypeForFilename(filename);
        if (mediaType != null) {
          return await http.MultipartFile.fromPath(
            fieldName,
            xfile.path,
            filename: filename,
            contentType: mediaType,
          );
        } else {
          // if unknown extension, still try to send (server might accept), but prefer bytes fallback
          final bytes = await xfile.readAsBytes();
          final fallbackName = xfile.name.isNotEmpty ? xfile.name : filename;
          final fallbackMedia = _mediaTypeForFilename(fallbackName ?? '');
          if (fallbackMedia != null) {
            return http.MultipartFile.fromBytes(fieldName, bytes, filename: fallbackName, contentType: fallbackMedia);
          } else {
            // unknown/unsupported: return null so caller can skip quickly
            return null;
          }
        }
      }

      if (pfile != null) {
        filename = pfile.name;
        final mediaType = _mediaTypeForFilename(filename);
        if (mediaType != null) {
          if (pfile.bytes != null) {
            return http.MultipartFile.fromBytes(fieldName, pfile.bytes!, filename: filename, contentType: mediaType);
          } else if (pfile.path != null && pfile.path!.isNotEmpty) {
            return await http.MultipartFile.fromPath(fieldName, pfile.path!, filename: filename, contentType: mediaType);
          }
        } else {
          // not an image (e.g., pdf). Return null quickly.
          return null;
        }
      }

      if (xfile != null) {
        // fallback reading bytes for web or if path wasn't available earlier
        final bytes = await xfile.readAsBytes();
        final fallbackName = xfile.name;
        final mediaType = _mediaTypeForFilename(fallbackName);
        if (mediaType != null) {
          return http.MultipartFile.fromBytes(fieldName, bytes, filename: fallbackName, contentType: mediaType);
        } else {
          return null;
        }
      }
    } catch (e) {
      debugPrint('[_makeMultipartFromPicked] error: $e');
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
      if (effectiveUrl.contains('dl-extractor-service-777302308889.us-central1.run.app') &&
          !effectiveUrl.contains('extract/')) {
        effectiveUrl = '${effectiveUrl.replaceAll(RegExp(r'/+$'), '')}/extract/';
        debugPrint('Adjusted DL URL to: $effectiveUrl');
      }

      // Choose field candidates: for DL prefer image_file, for RC prefer file
      final List<String> fieldCandidates = isDlModel
          ? [primaryFieldName, 'image_file', 'dl_image', 'image', 'file']
          : [primaryFieldName, 'file'];

      final Uri uri = Uri.parse(effectiveUrl);

      // QUICK CHECK: if RC endpoint, ensure chosen file is an image (avoid repeated 400s)
      String? chosenName;
      if (_lastRcPFile != null || _lastRcXFile != null || _lastDlPFile != null || _lastDlXFile != null) {
        // determine for current call which file is being used (prioritize xfile/pfile args)
        if (xfile != null) chosenName = xfile.name.isNotEmpty ? xfile.name : p.basename(xfile.path);
        else if (pfile != null) chosenName = pfile.name;
      }

      if (!isDlModel) {
        // RC endpoint requires an image — if filename extension isn't an image, bail fast
        if (chosenName != null && !_isImageFilename(chosenName)) {
          controller.text = '';
          _showErrorSnackBar('Selected file is not a supported image. Please choose JPG/PNG for number plate detection.');
          setExtractingFalse();
          return;
        }
      }

      bool success = false;

      for (final fieldName in fieldCandidates) {
        final mp = await _makeMultipartFromPicked(fieldName: fieldName, xfile: xfile, pfile: pfile);
        if (mp == null) {
          debugPrint('Could not build multipart for field "$fieldName" (likely unsupported file type or missing bytes)');
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
            if (body != null && body['dl_numbers'] is List && (body['dl_numbers'] as List).isNotEmpty) {
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
              final cleaned = raw.replaceAll(RegExp(r'[^A-Z0-9\s]'), ' ');
              final tokenReg = RegExp(r'\b([A-Z0-9]{6,25})\b', caseSensitive: false);
              final matches = tokenReg.allMatches(cleaned).map((m) => m.group(1)!).toList();
              String? best;
              for (final tok in matches) {
                final letters = RegExp(r'[A-Z]').allMatches(tok).length;
                final digits = RegExp(r'\d').allMatches(tok).length;
                if (letters >= 1 && digits >= 4) {
                  best = tok;
                  break;
                }
              }
              if (best == null) {
                final loose = RegExp(r'([A-Z]{1,2}\s*\d{2,}\s*[A-Z0-9]{0,3}\s*\d{3,})', caseSensitive: false);
                final m = loose.firstMatch(raw);
                if (m != null) best = m.group(1);
              }
              if (best != null) {
                extractedValue = best.replaceAll(RegExp(r'\s+'), '');
              }
            }
          } else {
            // -------- RC model (NEW) --------
            // New API (enhanced-alpr) returns a structure like:
            // {
            //   "success": true,
            //   "plates_detected": 1,
            //   "results": [ { "plate_text": "22BH65174", "ocr_confidence": "89.66%", ... } ]
            // }
            // We prefer results[0].plate_text when present.
            if (body != null && body['results'] is List && (body['results'] as List).isNotEmpty) {
              final firstPlate = (body['results'] as List)[0];
              if (firstPlate is Map) {
                final plateTextRaw = (firstPlate['plate_text'] ?? '').toString().trim();
                if (plateTextRaw.isNotEmpty) {
                  extractedValue = plateTextRaw;
                }
              }
            }

            // Defensive legacy fallbacks (rare)
            if (extractedValue == null && body != null && body['extracted_text'] != null) {
              final t = (body['extracted_text'] as String).trim();
              if (t.isNotEmpty) extractedValue = t;
            } else if (extractedValue == null && body != null && body['raw_text'] != null) {
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

  // Re-run RC extraction by re-sending the last-picked RC image to the server.
  Future<void> _refreshRcExtraction() async {
    if (_lastRcXFile == null && _lastRcPFile == null) {
      _showInfoSnackBar('No vehicle image selected to refresh.');
      return;
    }

    await _uploadForOcrAndFill(
      uploadUrl: _rcOcrUrl,
      primaryFieldName: _rcOcrFieldName,
      isDlModel: false,
      xfile: _lastRcXFile,
      pfile: _lastRcPFile,
      setFileName: (s) => setState(() => _rcImageName = s),
      controller: _rcController,
      setExtractingTrue: () => setState(() => _rcExtracting = true),
      setExtractingFalse: () => setState(() => _rcExtracting = false),
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

  // ---------------- Verification: delegate to verification.dart ----------
  Future<void> _handleVerification() async {
    final dlNumber = _dlController.text.trim();
    final rcNumber = _rcController.text.trim();

    // Build driverFile (if any) - only on non-web platforms we can build a dart:io File
    File? driverFile;
    if (!kIsWeb) {
      if (_lastDriverXFile != null && _lastDriverXFile!.path.isNotEmpty) {
        driverFile = File(_lastDriverXFile!.path);
      } else if (_lastDriverPFile != null && _lastDriverPFile!.path != null && _lastDriverPFile!.path!.isNotEmpty) {
        driverFile = File(_lastDriverPFile!.path!);
      }
    } else {
      // On web: cannot convert picked file into dart:io File.
      // If only driver image is selected on web, inform user that face verification via file path is not supported.
      if (dlNumber.isEmpty && rcNumber.isEmpty && (_lastDriverXFile != null || _lastDriverPFile != null)) {
        _showErrorSnackBar('Face verification from web is currently unsupported. Try from a mobile device or enter DL/RC numbers.');
        return;
      }
      // If DL/RC present, proceed without driverFile (face verification skipped in backend call)
      driverFile = null;
    }

    if (dlNumber.isEmpty && rcNumber.isEmpty && driverFile == null) {
      _showErrorSnackBar('Please provide a DL number, a Vehicle number, or a Driver Image to verify.');
      return;
    }

    setState(() => _isVerifying = true);

    try {
      await verifyDriverAndShowDialog(
        context,
        dlNumber: dlNumber.isNotEmpty ? dlNumber : null,
        rcNumber: rcNumber.isNotEmpty ? rcNumber : null,
        driverImageFile: driverFile,
        location: 'Toll-Plaza-1',
        tollgate: 'Gate-A',
      );
    } catch (e) {
      _showErrorSnackBar('An error occurred during verification: $e');
    } finally {
      setState(() {
        _isVerifying = false;
        // Reset selected names and file references (keep extracted text in controllers so user can edit if desired)
        _dlImageName = null;
        _rcImageName = null;
        _driverImageName = null;
        _lastDlXFile = _lastDlPFile = null;
        _lastRcXFile = _lastRcPFile = null;
        _lastDriverXFile = _lastDriverPFile = null;
      });
    }
  }

  // ----------------- Driver image helpers for preview -----------------

  /// Load driver image bytes from whichever source is available.
  Future<Uint8List?> _loadDriverImageBytes() async {
    try {
      if (_lastDriverPFile != null) {
        if (_lastDriverPFile!.bytes != null) return _lastDriverPFile!.bytes;
        if (_lastDriverPFile!.path != null && _lastDriverPFile!.path!.isNotEmpty) {
          return await File(_lastDriverPFile!.path!).readAsBytes();
        }
      }

      if (_lastDriverXFile != null) {
        // On native platforms xfile.path is usually available
        if (!kIsWeb && _lastDriverXFile!.path.isNotEmpty) {
          return await File(_lastDriverXFile!.path).readAsBytes();
        }
        // On web or fallback, read bytes from XFile
        return await _lastDriverXFile!.readAsBytes();
      }
    } catch (e) {
      debugPrint('[_loadDriverImageBytes] error: $e');
    }
    return null;
  }

  /// Show fullscreen preview of driver image (tappable thumbnail opens this).
  void _openFullScreenDriverPreview() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(0),
          backgroundColor: Colors.black,
          child: ConstrainedBox( // Responsive container for the image
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(ctx).size.width * 0.9,
              maxHeight: MediaQuery.of(ctx).size.height * 0.9,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: FutureBuilder<Uint8List?>(
                    future: _loadDriverImageBytes(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      }
                      if (!snap.hasData || snap.data == null) {
                        return const Center(child: Text('Unable to load image', style: TextStyle(color: Colors.white)));
                      }
                      return InteractiveViewer(
                        maxScale: 5.0,
                        child: Center(
                          child: Image.memory(
                            snap.data!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Close button top-right
                Positioned(
                  top: 28,
                  right: 16,
                  child: SafeArea(
                    child: CircleAvatar(
                      backgroundColor: Colors.black45,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final double horizontalPadding = screenWidth > 600 ? screenWidth * 0.1 : 16.0;

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
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Container(
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
                      isDriver: false,
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
                      isDriver: false,
                    ),

                    const SizedBox(height: 12),

                    _buildTextInput(
                      controller: _rcController,
                      label: 'Vehicle Number',
                      hint: _rcExtracting ? 'Extracting...' : 'Select image or enter manually',
                      prefixIcon: Icons.directions_car,
                      enabled: !_rcExtracting,
                      // Show refresh button when an RC image is present; pressing it will re-call the RC API.
                      showAlternateButton: (_lastRcXFile != null || _lastRcPFile != null),
                      onAlternatePressed: _refreshRcExtraction,
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
                      isDriver: true, // <--- show thumbnail + preview behavior
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

  /// fileName: display label
  /// isDriver: when true, we render a small thumbnail if driver image is selected and allow tap-to-enlarge
  Widget _buildFileUploadCard({
    required String label,
    required String? fileName,
    required VoidCallback onTap,
    required IconData icon,
    bool isDriver = false,
  }) {
    Widget trailing = const SizedBox.shrink();
    // If this is the driver card and an image is selected, create a small thumbnail
    if (isDriver && (_lastDriverPFile != null || _lastDriverXFile != null)) {
      trailing = GestureDetector(
        onTap: _openFullScreenDriverPreview,
        child: FutureBuilder<Uint8List?>(
          future: _loadDriverImageBytes(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey.shade200),
                child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }
            if (!snap.hasData || snap.data == null) {
              // fallback small icon
              return Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey.shade100),
                child: Icon(Icons.image, color: Colors.grey.shade600),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                snap.data!,
                width: 46,
                height: 46,
                fit: BoxFit.cover,
              ),
            );
          },
        ),
      );
    } else if (fileName != null) {
      trailing = Icon(Icons.check_circle, color: Colors.green.shade600, size: 18);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            const SizedBox(width: 8),
            trailing,
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
    bool showAlternateButton = false,
    VoidCallback? onAlternatePressed,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(prefixIcon, size: 18),
        suffixIcon: showAlternateButton
            ? IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: onAlternatePressed,
        )
            : null,
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
