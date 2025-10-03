import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'auth.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Example user data
  final String userName = 'Aishwary Raj';
  final String userEmail = 'aishwary2316@gmail.com';

  // Drawer colors (unchanged as requested)
  static const Color _drawerBlue = Color(0xFF162170);
  static const Color _drawerTopBand = Color(0xFF1A2A83);
  static const Color _selectedBand = Color(0xFF0E1A55);

  // App theme colors to match government portal
  static const Color _primaryBlue = Color(0xFF1E3A8A);
  static const Color _headerBlue = Color(0xFF1E40AF);
  static const Color _lightGray = Color(0xFFF8FAFC);
  static const Color _borderGray = Color(0xFFE2E8F0);
  static const Color _textGray = Color(0xFF64748B);

  final double _menuWidth = 220;
  final bool _isActive = true;
  int _selectedIndex = 0;

  // Controllers & state for the Home UI
  final TextEditingController _dlController = TextEditingController();
  final TextEditingController _rcController = TextEditingController();

  String? _dlImageName;
  String? _rcImageName;
  String? _driverImageName;

  // Loading states for future API integration
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _dlController.dispose();
    _rcController.dispose();
    super.dispose();
  }

  // File picker methods (unchanged core logic)
  Future<void> _pickDlImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _dlImageName = result.files.single.name;
        // TODO: Integrate with OCR API when ready
        _dlController.text = ''; // Will be populated by OCR
      });
    }
  }

  Future<void> _pickRcImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _rcImageName = result.files.single.name;
        // TODO: Integrate with RC OCR API when ready
        _rcController.text = ''; // Will be populated by OCR
      });
    }
  }

  Future<void> _pickDriverImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _driverImageName = result.files.single.name;
      });
    }
  }

  // Enhanced Home page UI matching the government portal design
  Widget _buildHomeContent() {
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
                  // Government logo and ministry name
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.account_balance,
                          size: 40,
                          color: _primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'GOVERNMENT OF INDIA',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _textGray,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'MINISTRY OF ROAD TRANSPORT & HIGHWAYS',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _primaryBlue,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Main title
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
                    hint: 'Select image or enter manually',
                    prefixIcon: Icons.confirmation_number,
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
                    hint: 'Select image or enter manually',
                    prefixIcon: Icons.directions_car,
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
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text('Verifying...', style: TextStyle(fontSize: 16)),
                        ],
                      )
                          : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.verified_user, size: 20),
                          const SizedBox(width: 8),
                          const Text('Verify Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
        child: Column(
          children: [
            Row(
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
                if (fileName != null)
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
              ],
            ),
            if (fileName == null) ...[
              const SizedBox(height: 8),
              Text(
                'No file chosen',
                style: TextStyle(fontSize: 12, color: _textGray),
              ),
            ],
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
  }) {
    return TextFormField(
      controller: controller,
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

  Future<void> _handleVerification() async {
    // Basic validation
    if (_dlController.text.isEmpty && _dlImageName == null) {
      _showErrorSnackBar('Please provide driving license information');
      return;
    }

    if (_rcController.text.isEmpty && _rcImageName == null) {
      _showErrorSnackBar('Please provide vehicle registration information');
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    // Simulate API call delay
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isVerifying = false;
    });

    // TODO: Implement actual API calls to your AI models
    _showInfoSnackBar('Verification completed! (API integration pending)');
  }

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

  // Other page contents (unchanged)
  List<Widget> get _pages => [
    _buildHomeContent(),
    _buildPlaceholderPage('User Management', Icons.group),
    _buildPlaceholderPage('Vehicle Logs', Icons.directions_car),
    _buildPlaceholderPage('Alert Logs', Icons.warning_amber_rounded),
    _buildPlaceholderPage('Blacklist Management', Icons.do_not_disturb_on),
    _buildPlaceholderPage('Settings', Icons.settings),
  ];

  Widget _buildPlaceholderPage(String title, IconData icon) {
    return Container(
      color: _lightGray,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(icon, size: 64, color: _primaryBlue),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This page is under development',
                    style: TextStyle(
                      fontSize: 14,
                      color: _textGray,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Navigation and menu methods (unchanged as requested)
  void _onSelect(BuildContext context, int index, String label) {
    setState(() {
      _selectedIndex = index;
    });
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label selected')));
  }

  Future<void> _showCustomMenu(BuildContext context) async {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final double top = media.padding.top + kToolbarHeight;
    final double left = screenWidth - _menuWidth - 12;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(left, top, 12, 0),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'settings',
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: const [
                Icon(Icons.settings, size: 20, color: Colors.black87),
                SizedBox(width: 14),
                Text('Settings', style: TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'profile',
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: const [
                Icon(Icons.person, size: 20, color: Colors.black87),
                SizedBox(width: 14),
                Text('Profile', style: TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Row(
              children: const [
                Icon(Icons.logout, size: 20, color: Colors.red),
                SizedBox(width: 14),
                Text(
                  'Logout',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      color: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
    );

    if (selected != null) {
      if (selected == 'settings') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings clicked')));
      } else if (selected == 'profile') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile clicked')));
      } else if (selected == 'logout') {
        //ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logout clicked')));
        Navigator.push(context, MaterialPageRoute(builder: (context) => const AuthPage()),);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Roboto',
      ),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            backgroundColor: _headerBlue,
            foregroundColor: Colors.white,
            title: const Text(
              "DL/RC Verification Portal",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () => _showCustomMenu(context),
              ),
            ],
            elevation: 2,
          ),
          drawer: Drawer(
            child: Container(
              color: _drawerBlue,
              child: Column(
                children: [
                  Container(height: 24, color: _drawerTopBand),
                  Container(
                    color: _drawerBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    child: Stack(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.white,
                                  child: Icon(Icons.person, size: 34, color: _drawerTopBand),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  userName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  userEmail,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                        Positioned(
                          top: 6,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _drawerTopBand.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _isActive ? Colors.greenAccent : Colors.redAccent,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: (_isActive ? Colors.greenAccent : Colors.redAccent).withOpacity(0.6),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isActive ? 'Active' : 'Inactive',
                                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 20, color: Colors.white24, indent: 16, endIndent: 16),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _buildDrawerTile(context, icon: Icons.home, title: 'Home', selected: _selectedIndex == 0, onTap: () => _onSelect(context, 0, 'Home')),
                        _buildDrawerTile(context, icon: Icons.group, title: 'User Management', selected: _selectedIndex == 1, onTap: () => _onSelect(context, 1, 'User Management')),
                        _buildDrawerTile(context, icon: Icons.directions_car, title: 'Vehicle Logs', selected: _selectedIndex == 2, onTap: () => _onSelect(context, 2, 'Vehicle Logs')),
                        _buildDrawerTile(context, icon: Icons.warning_amber_rounded, title: 'Alert Logs', selected: _selectedIndex == 3, onTap: () => _onSelect(context, 3, 'Alert Logs')),
                        _buildDrawerTile(context, icon: Icons.do_not_disturb_on, title: 'Blacklist Management', selected: _selectedIndex == 4, onTap: () => _onSelect(context, 4, 'Blacklist Management')),
                        const Divider(height: 20, color: Colors.white24, indent: 16, endIndent: 16),
                        _buildDrawerTile(context, icon: Icons.settings, title: 'Settings', selected: _selectedIndex == 5, onTap: () => _onSelect(context, 5, 'Settings')),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 56,
                          width: double.infinity,
                          child: Image.asset(
                            'assets/namedLogo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Version 1.0.0',
                          style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: _pages[_selectedIndex],
        ),
      ),
    );
  }

  Widget _buildDrawerTile(
      BuildContext context, {
        required IconData icon,
        required String title,
        bool selected = false,
        required VoidCallback onTap,
      }) {
    return Container(
      color: selected ? _selectedBand : Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: Icon(icon, color: Colors.white, size: 22),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          maxLines: 2,
          softWrap: true,
        ),
        onTap: onTap,
      ),
    );
  }
}