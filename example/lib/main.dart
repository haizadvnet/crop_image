import 'dart:ui' as ui;
import 'package:flutter/material.dart';
// Assuming your crop_image package files are in a 'lib' folder accessible via package import
// If your library is in the same project, adjust the import path accordingly.
// For example, if your main.dart is in example/lib and your crop library is in lib:
// import 'package:your_project_name/crop_image.dart';
// For this example, let's assume the crop_image.dart from the library is directly accessible
// You would typically import the main export file of your package:
import 'package:crop_image/crop_image.dart'; //

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crop Image Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const CropDemoPage(),
    );
  }
}

class CropDemoPage extends StatefulWidget {
  const CropDemoPage({super.key});

  @override
  State<CropDemoPage> createState() => _CropDemoPageState();
}

class _CropDemoPageState extends State<CropDemoPage> {
  final CropController _cropController = CropController(
    // Default aspect ratio for the crop mask (optional)
    initialCropSizePx:Size(100, 250),
    initialAspectRatio: 0.9,
    initialResizeEnabled: true,
    minCropSize:Size(300, 300),
    // Default crop mask (normalized 0-1 relative to the image viewport)
    initialCropMaskRect: const Rect.fromLTWH(0.1, 0.1, 0.1, 0.1),
  );

  double _currentZoomSliderValue = 1.0;
  // Store the ui.Image to avoid re-resolving if not necessary,
  // though CropImage handles its own ui.Image loading via controller.image
  ui.Image? _displayedImage; 

  @override
  void initState() {
    super.initState();
    _currentZoomSliderValue = _cropController.imageZoomFactor;
    _cropController.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    // Update slider if zoom factor changes in controller for other reasons
    if (_cropController.imageZoomFactor != _currentZoomSliderValue) {
      setState(() {
        _currentZoomSliderValue = _cropController.imageZoomFactor;
      });
    }
    // If you need to react to other controller changes, you can do it here.
    // For example, if the image itself changes in the controller:
    if (_displayedImage != _cropController.image) {
      setState(() {
        _displayedImage = _cropController.image;
      });
    }
  }

  @override
  void dispose() {
    _cropController.removeListener(_onControllerUpdate);
    _cropController.dispose();
    super.dispose();
  }

  Future<void> _cropImage() async {
    final ui.Image? croppedImage = await _cropController.croppedBitmap();

    if (croppedImage != null && mounted) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Cropped Image'),
            content: SizedBox(
              width: double.maxFinite,
              child: RawImage(image: croppedImage, fit: BoxFit.contain),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Close'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to crop image or no image loaded.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Cropper Example'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              color: Colors.black87, // Background for the CropImage area
              padding: const EdgeInsets.all(8.0),
              child: CropImage(
                controller: _cropController,
                // IMPORTANT: You must provide an Image widget.
                // The CropImage widget will resolve it to a ui.Image for the controller.
                image: Image.asset('assets/08272011229.jpg'), // Ensure this asset exists
                // Example: Using a network image (uncomment and replace URL)
                // image: Image.network('https://picsum.photos/seed/picsum/800/600'),
                paddingSize: 0, // Padding around the displayed image area
                scrimColor: Colors.black.withOpacity(0.7),
                onCropMaskChanged: (rect) {
                  // You can get updates when the crop mask is changed by gestures
                  // print("Crop mask updated by gesture: $rect");
                },
              ),
            ),
          ),
          if (_cropController.image != null) // Only show controls if image is loaded
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Row(
                  //   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  //   children: <Widget>[
                  //     IconButton(
                  //       icon: const Icon(Icons.rotate_left),
                  //       tooltip: 'Rotate Left',
                  //       onPressed: () {
                  //         _cropController.rotateLeft();
                  //       },
                  //     ),
                  //     IconButton(
                  //       icon: const Icon(Icons.rotate_right),
                  //       tooltip: 'Rotate Right',
                  //       onPressed: () {
                  //         _cropController.rotateRight();
                  //       },
                  //     ),
                  //   ],
                  // ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      const Text('Zoom:'),
                      Expanded(
                        child: Slider(
                          value: _currentZoomSliderValue,
                          min: 1.0,
                          max: 8.0, // Max zoom factor allowed by controller
                          divisions: 70, // (max-min) * 10 for 0.1 steps
                          label: _currentZoomSliderValue.toStringAsFixed(1),
                          onChanged: (double value) {
                            setState(() {
                              _currentZoomSliderValue = value;
                              _cropController.imageZoomFactor = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  // Example: Aspect ratio control (more advanced to implement fully)
                  // You could have buttons to set _cropController.aspectRatio here
                  // For instance:
                  // ElevatedButton(
                  //   onPressed: () => _cropController.aspectRatio = 16/9,
                  //   child: Text("16:9"),
                  // ),
                  // ElevatedButton(
                  //   onPressed: () => _cropController.aspectRatio = 1/1,
                  //   child: Text("Square"),
                  // ),
                  // ElevatedButton(
                  //   onPressed: () => _cropController.aspectRatio = null, // Freeform
                  //   child: Text("Free"),
                  // ),
                ],
              )
            ),
          const SizedBox(height: 20),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _cropController.image != null ? _cropImage : null,
        tooltip: 'Crop Image',
        backgroundColor: _cropController.image != null ? Theme.of(context).primaryColor : Colors.grey,
        child: const Icon(Icons.crop),
      ),
    );
  }
}