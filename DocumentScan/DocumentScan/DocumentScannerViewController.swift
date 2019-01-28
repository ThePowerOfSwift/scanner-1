import UIKit
import AVFoundation
import Vision
import CoreImage

@objcMembers
class DocumentScannerViewController: UIViewController {
    @IBOutlet weak var scannerView: UIView!
    
    private var captureSession: AVCaptureSession?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private let stillImageOutput = AVCapturePhotoOutput()
    private var detectRectanglesRequest: VNDetectRectanglesRequest?
    private var targetRectLayer = TargetRectLayer()
    private var targetRectangle = VNRectangleObservation()
    
    // MARK: -
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startScanner()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanner()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configurePreviewOrientation()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        // make sure we reconfigure our camera layer's orientation on portrait/landscape changes
        coordinator.animate(alongsideTransition: { _ in
            self.configurePreviewOrientation()
        }, completion: { _ in
            self.configurePreviewOrientation()
        })
    }
    
    // MARK: - Scanner
    private func startScanner() {
        // check for camera
        if !UIImagePickerController.isSourceTypeAvailable(.camera) {
            let alert = UIAlertController(title: "Kamera nicht verfügbar", message: "Dieses Gerät besitzt keine Kamera.", preferredStyle: .alert)
            present(alert, animated: true)
            return
        }
        
        // check auth status
        if [AVAuthorizationStatus.denied, AVAuthorizationStatus.restricted].contains(AVCaptureDevice.authorizationStatus(for: AVMediaType.video)) {
            let alert = UIAlertController(title: "Berechtigung fehlt", message: "Die App hat keine Berechtigung um auf die Kamera zuzugreifen. Bitte erteilen Sie die Berechtigung in den Einstellungen.", preferredStyle: .alert)
            present(alert, animated: true)
            return
        }
        
        if captureSession != nil { // already configured
            configurePreviewOrientation()
        } else {
            let captureDevice = AVCaptureDevice.default(for: AVMediaType.video)
            
            do {
                let captureDeviceInput = try AVCaptureDeviceInput(device: captureDevice!)
                captureSession = AVCaptureSession()
                captureSession?.addInput(captureDeviceInput)
                
                let videoOutput = AVCaptureVideoDataOutput()
                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
                captureSession?.addOutput(videoOutput)
                
                captureSession?.addOutput(stillImageOutput)
                
                let request = VNDetectRectanglesRequest { req, error in
                    DispatchQueue.main.async {
                        if let observation = req.results?.first as? VNRectangleObservation {
                            self.targetRectangle = observation
                            self.targetRectLayer.drawTargetRect(observation: observation, previewLayer: self.previewLayer, animated: false)
                        } else {
                            self.targetRectLayer.drawTargetRect(observation: nil, previewLayer: self.previewLayer, animated: false)
                        }
                    }
                }
                
                request.minimumSize = 0.3
                request.quadratureTolerance = 20
                detectRectanglesRequest = request
                
                // setup view preview layer
                let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
                self.previewLayer = previewLayer
                previewLayer.videoGravity = .resizeAspectFill
                self.scannerView.layer.addSublayer(previewLayer)
                self.scannerView.layer.addSublayer(targetRectLayer)
                configurePreviewOrientation()
            } catch {
                print(error)
                return
            }
        }
        
        captureSession?.startRunning()
        scannerView.isHidden = false
    }
    
    private func stopScanner(animated: Bool = false) {
        captureSession?.stopRunning()
        
        if animated {
            // create a nice hole animation using a mask layer
            let maskLayer = CAShapeLayer()
            maskLayer.frame = scannerView.bounds
            
            // get the sideLength of our assumed square
            let sideLength = max(scannerView.bounds.width, scannerView.bounds.height)
            
            // calculate the diameter that is required to cover the scannerView
            let circleDiameter = sqrt(sideLength * sideLength + sideLength * sideLength)
            
            // create two paths for our animation
            let startPath = UIBezierPath(rect: scannerView.bounds)
            startPath.append(UIBezierPath(ovalIn: CGRect(x: scannerView.bounds.midX, y: scannerView.bounds.midY, width: 0, height: 0)).reversing())
            
            let endPath = UIBezierPath(rect: scannerView.bounds)
            endPath.append(UIBezierPath(ovalIn: CGRect(x: (scannerView.bounds.width - circleDiameter) / 2, y: (scannerView.bounds.height - circleDiameter) / 2, width: circleDiameter, height: circleDiameter)).reversing())
            
            maskLayer.path = startPath.cgPath
            scannerView.layer.mask = maskLayer
            
            // wrap everything in a transaction in order to get a completion callback
            CATransaction.begin()
            let animation = CABasicAnimation(keyPath: "path")
            animation.toValue = endPath.cgPath
            animation.duration = 0.5
            animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
            animation.fillMode = CAMediaTimingFillMode.both
            animation.isRemovedOnCompletion = false
            CATransaction.setCompletionBlock {
                self.scannerView.isHidden = true
            }
            maskLayer.add(animation, forKey: animation.keyPath)
            CATransaction.commit()
        } else {
            scannerView.isHidden = true
        }
    }
    
    // MARK: - Utility
    private func generateFeedback(success: Bool) {
        let feedbackGenerator = UINotificationFeedbackGenerator()
        if success {
            feedbackGenerator.notificationOccurred(.success)
        } else {
            feedbackGenerator.notificationOccurred(.error)
        }
    }
    
    private func configurePreviewOrientation() {
        previewLayer?.frame = scannerView.layer.bounds
        previewLayer?.connection?.videoOrientation = AVCaptureVideoOrientation(rawValue: UIApplication.shared.statusBarOrientation.rawValue) ?? .portrait
    }
    
    // MARK: - Action Methods
    @IBAction func takePhotoButtonTapped(_ sender: Any) {
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        stillImageOutput.capturePhoto(with: settings, delegate: self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let image = sender as? UIImage, let vc = segue.destination as? ImageVC {
            vc.image = image
        }
    }
}

extension DocumentScannerViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation()
            else { return }
        guard let ciImage = CIImage(data: imageData, options: [.applyOrientationProperty : true]) else { return }
        let image = UIImage(ciImage: ciImage)
        
        let imageTopLeft: CGPoint = CGPoint(x: image.size.width * targetRectangle.bottomLeft.x, y: targetRectangle.bottomLeft.y * image.size.height)
        let imageTopRight: CGPoint = CGPoint(x: image.size.width * targetRectangle.bottomRight.x, y: targetRectangle.bottomRight.y * image.size.height)
        let imageBottomLeft: CGPoint = CGPoint(x: image.size.width * targetRectangle.topLeft.x, y: targetRectangle.topLeft.y * image.size.height)
        let imageBottomRight: CGPoint = CGPoint(x: image.size.width * targetRectangle.topRight.x, y: targetRectangle.topRight.y * image.size.height)

        let flattenedImage = image.flattenImage(topLeft: imageTopLeft, topRight: imageTopRight, bottomLeft: imageBottomLeft, bottomRight: imageBottomRight)
        let finalImage = UIImage(ciImage: flattenedImage, scale: image.scale, orientation: image.imageOrientation)

//        performSegue(withIdentifier: "showPhoto", sender: image)
//        performSegue(withIdentifier: "showPhoto", sender: UIImage(ciImage: flattenedImage))
        performSegue(withIdentifier: "showPhoto", sender: finalImage)

    }
}

// MARK: -
extension DocumentScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), let request = detectRectanglesRequest else { return }
        var requestOptions = [VNImageOption: Any]()
        
        if let camData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            requestOptions = [.cameraIntrinsics: camData]
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: requestOptions)
        try? imageRequestHandler.perform([request])
    }
}

private class TargetRectLayer: CAShapeLayer {
    func drawTargetRect(observation: VNRectangleObservation?, previewLayer: AVCaptureVideoPreviewLayer?, animated: Bool) {
        guard let observation = observation, let previewLayer = previewLayer else {
            draw(path: nil, animated: false)
            return
        }
        
        let convertedTopLeft: CGPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: observation.topLeft.x, y: 1 - observation.topLeft.y))
        let convertedTopRight: CGPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: observation.topRight.x, y: 1 - observation.topRight.y))
        let convertedBottomLeft: CGPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: observation.bottomLeft.x, y: 1 - observation.bottomLeft.y))
        let convertedBottomRight: CGPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: observation.bottomRight.x, y: 1 - observation.bottomRight.y))
        
        let rectanglePath = UIBezierPath()
        rectanglePath.move(to: convertedTopLeft)
        rectanglePath.addLine(to: convertedTopRight)
        rectanglePath.addLine(to: convertedBottomRight)
        rectanglePath.addLine(to: convertedBottomLeft)
        rectanglePath.close()
        
        draw(path: rectanglePath, animated: animated)
    }
    
    private func draw(path bezierPath: UIBezierPath?, animated: Bool) {
        if let bezierPath = bezierPath {
            strokeColor = UIColor.green.cgColor
            lineWidth = 4
            fillColor = nil
            path = bezierPath.cgPath
        } else {
            path = nil
            removeAllAnimations()
        }
    }
}

extension UIImage {
    
    func flattenImage(topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) -> CIImage {
        let docImage = self.ciImage!
        let rect = CGRect(origin: CGPoint.zero, size: self.size)
        let perspectiveCorrection = CIFilter(name: "CIPerspectiveCorrection")!
        perspectiveCorrection.setValue(CIVector(cgPoint: self.cartesianForPoint(point: topLeft, extent: rect)), forKey: "inputTopLeft")
        perspectiveCorrection.setValue(CIVector(cgPoint: self.cartesianForPoint(point: topRight, extent: rect)), forKey: "inputTopRight")
        perspectiveCorrection.setValue(CIVector(cgPoint: self.cartesianForPoint(point: bottomLeft, extent: rect)), forKey: "inputBottomLeft")
        perspectiveCorrection.setValue(CIVector(cgPoint: self.cartesianForPoint(point: bottomRight, extent: rect)), forKey: "inputBottomRight")
        perspectiveCorrection.setValue(docImage, forKey: kCIInputImageKey)
        
        return perspectiveCorrection.outputImage!
    }
    
    func cartesianForPoint(point:CGPoint,extent:CGRect) -> CGPoint {
        return CGPoint(x: point.x,y: extent.height - point.y)
    }
}
