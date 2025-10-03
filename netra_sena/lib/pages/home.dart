// lib/pages/home.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http; // Kept for platform compatibility, though OCR helpers removed

import 'verification.dart'; // <- uses verifyDriverAndShowDialog()

class HomePageContent extends StatefulWidget {
  const HomePageContent({super.key});

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> {
  // Removed DL/RC OCR Configuration

  // App theme colors (unchanged)
  static const Color _primaryBlue = Color(0xFF1E3A8A);
  static const Color _lightGray = Color(0xFFF8FAFC);
  static const Color _borderGray = Color(0xFFE2E8F0);
  static const Color _textGray = Color(0xFF64748B);

  // Controllers & state - ONLY FACE/DRIVER REMAINS
  // Removed _dlController, _rcController

  String? _driverImageName;

  // Removed DL/RC file references
  XFile? _lastDriverXFile;
  PlatformFile? _lastDriverPFile;

  // Loading / extracting states
  bool _isVerifying = false;
  // Removed _dlExtracting, _rcExtracting

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    // DL/RC controllers were removed, so only calling super.dispose is necessary.
    super.dispose();
  }

  // Helper to know if we can enable the Verify button
  bool get _hasInput {
    // Only checks for driver image
    if (_lastDriverXFile != null) return true;
    if (_lastDriverPFile != null) return true;
    return false;
  }

  // Removed all OCR/DL/RC related helper methods.

  // Only the driver image picker remains
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
                  subtitle: const Text('Images only'), // Updated subtitle
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
    // Removed dlNumber and rcNumber

    // Build driverFile (if any) - only on non-web platforms we can build a dart:io File
    File? driverFile;
    if (!kIsWeb) {
      if (_lastDriverXFile != null && _lastDriverXFile!.path.isNotEmpty) {
        driverFile = File(_lastDriverXFile!.path);
      } else if (_lastDriverPFile != null && _lastDriverPFile!.path != null && _lastDriverPFile!.path!.isNotEmpty) {
        driverFile = File(_lastDriverPFile!.path!);
      }
    } else {
      // On web: only driver image selected is not supported.
      if (_lastDriverXFile != null || _lastDriverPFile != null) {
        _showErrorSnackBar('Face verification from web is currently unsupported. Try from a mobile device.');
        return;
      }
      driverFile = null;
    }

    if (driverFile == null) {
      _showErrorSnackBar('Please provide a Driver Image to verify.');
      return;
    }

    setState(() => _isVerifying = true);

    try {
      // Call the MODIFIED verification function (removed dlNumber and rcNumber args)
      await verifyDriverAndShowDialog(
        context,
        driverImageFile: driverFile,
        location: 'Toll-Plaza-1',
        tollgate: 'Gate-A',
      );
    } catch (e) {
      _showErrorSnackBar('An error occurred during verification: $e');
    } finally {
      setState(() {
        _isVerifying = false;
        // Reset selected names and file references
        _driverImageName = null;
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

  // ----------------- Build UI -------------------
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double horizontalPadding = screenWidth > 600 ? screenWidth * 0.1 : 16.0;

    return Container(
      color: _lightGray,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header section
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'Face Surveillance Portal', // UPDATED TITLE
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
                    // REMOVED Driving License Section
                    // REMOVED Vehicle Registration Section

                    // Driver Image Section (Kept)
                    _buildSectionHeader(
                      icon: Icons.person,
                      title: 'Upload Driver Image',
                      subtitle: 'Upload a clear photo of the driver for face recognition', // UPDATED SUBTITLE
                    ),
                    const SizedBox(height: 16),

                    _buildFileUploadCard(
                      label: 'Choose Driver Image File',
                      fileName: _driverImageName,
                      onTap: _pickDriverImage,
                      icon: Icons.person_add_alt_1,
                      isDriver: true,
                    ),

                    const SizedBox(height: 32),

                    // Verify Information Button (Modified onClick and text)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isVerifying ? null : (_hasInput ? _handleVerification : null),
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
                            Text('Verify Driver Face', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), // UPDATED TEXT
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Info note (Updated text)
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
                              'AI-powered facial recognition will verify the driver against the suspect database.', // UPDATED TEXT
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
          color: fileName != null ? Colors.green.shade50 : _lightGray,
          borderRadius: BorderRadius.circular(8),
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

// REMOVED _buildTextInput as text fields are no longer needed.
}