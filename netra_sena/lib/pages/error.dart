// lib/pages/error.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';

class SnowFoxErrorPage extends StatefulWidget {
  final String errorMessage;
  final VoidCallback? onRetry;

  const SnowFoxErrorPage({
    Key? key,
    this.errorMessage = "Something went wrong!",
    this.onRetry,
  }) : super(key: key);

  @override
  State<SnowFoxErrorPage> createState() => _SnowFoxErrorPageState();
}

class _SnowFoxErrorPageState extends State<SnowFoxErrorPage> {
  String? processedHtmlContent;
  bool isLoading = true;
  String? errorLoadingHtml;

  @override
  void initState() {
    super.initState();
    _loadAndProcessHtml();
  }

  Future<void> _loadAndProcessHtml() async {
    try {
      // Load all files
      final htmlFile = await rootBundle.loadString('lib/animation/index.html');
      final styleCSS = await rootBundle.loadString('lib/animation/style.css');
      final assetCSS = await rootBundle.loadString('lib/animation/asset.css');

      // Process the HTML to inject CSS
      String processedHtml = await _injectCSSIntoHtml(htmlFile, styleCSS, assetCSS);

      setState(() {
        processedHtmlContent = processedHtml;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading HTML files: $e');
      setState(() {
        errorLoadingHtml = e.toString();
        isLoading = false;
      });
    }
  }

  Future<String> _injectCSSIntoHtml(String htmlContent, String styleCSS, String assetCSS) async {
    // Find the head section and inject CSS
    String injectedCSS = '''
<style>
/* Style CSS */
$styleCSS

/* Asset CSS */
$assetCSS

/* Additional styling for Flutter integration */
body {
  margin: 0;
  padding: 0;
  background: transparent !important;
  overflow: hidden;
}
</style>''';

    // Check if there's already a <head> tag
    if (htmlContent.contains('<head>')) {
      // Insert CSS after the opening <head> tag
      return htmlContent.replaceFirst('<head>', '<head>\n$injectedCSS');
    } else if (htmlContent.contains('<html>')) {
      // Insert a head section after the opening <html> tag
      return htmlContent.replaceFirst('<html>', '<html>\n<head>\n$injectedCSS\n</head>');
    } else {
      // Wrap everything with proper HTML structure
      return '''
<!DOCTYPE html>
<html>
<head>
$injectedCSS
</head>
<body>
$htmlContent
</body>
</html>
      ''';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF9095B9),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Fox Animation Container
                // Use LayoutBuilder to make the container responsive
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Set a max width and calculate a dynamic height to maintain aspect ratio
                    final double maxWidth = 470;
                    final double maxHeight = 335;
                    final double width = constraints.maxWidth > maxWidth ? maxWidth : constraints.maxWidth;
                    final double height = (width / maxWidth) * maxHeight;

                    return Container(
                      width: width,
                      height: height,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _buildAnimationContent(),
                    );
                  },
                ),

                const SizedBox(height: 40),

                // Error Text
                Text(
                  widget.errorMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 20),

                // Retry Button
                if (widget.onRetry != null)
                  ElevatedButton(
                    onPressed: widget.onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF9095B9),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: const Text(
                      'Try Again',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                // Tap hint
                const Text(
                  'Tap the fox for snow! ❄️',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimationContent() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      );
    }

    if (errorLoadingHtml != null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 60,
                color: Colors.red,
              ),
              const SizedBox(height: 10),
              const Text(
                'Failed to load animation',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Error: ${errorLoadingHtml!.length > 50 ? errorLoadingHtml!.substring(0, 50) + "..." : errorLoadingHtml}',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (processedHtmlContent != null) {
      return GestureDetector(
        onTap: () {
          // Handle tap events for snow toggle
          print('HTML animation tapped');
        },
        child: Html(
          data: processedHtmlContent!,
          style: {
            "body": Style(
              margin: Margins.zero,
              padding: HtmlPaddings.zero,
              backgroundColor: Colors.transparent,
            ),
            "html": Style(
              margin: Margins.zero,
              padding: HtmlPaddings.zero,
              backgroundColor: Colors.transparent,
            ),
          },
        ),
      );
    }

    return Container(
        decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: Colors.white.withOpacity(0.3)),
    ),
    child: const Center(
    child: Text(
    'No content to display',
    style: TextStyle(
    color: Colors.white70,
    fontSize: 16,
    ),
    ),
    )
    );
  }
}


// Example usage:
class ErrorPageExample extends StatelessWidget {
  const ErrorPageExample({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SnowFoxErrorPage(
        errorMessage: "Oops! Something went wrong.\nPlease try again.",
        onRetry: () {
          // Handle retry logic here
          debugPrint("Retry button pressed");
        },
      ),
    );
  }
}