//
//  CameraCapturePipeline.swift
//  AppleVisioniOSPOC
//
//  Created by Varun on 27/06/17.
//  Copyright © 2017 Diet Code. All rights reserved.
//

import Foundation
import AVKit
import Vision

protocol CameraCapturePipelineDelegate {
    // specify delegates
    func cameraCapture(Pipeline pipeline: CameraCapturePipeline, didFailWith error: NSError)
    func cameraCapture(Pipeline pipeline: CameraCapturePipeline, didDetectFaces faceDataset: [[String: Any?]])
    func cameraCapture(Pipeline pipeline: CameraCapturePipeline, didUpdateFaces faceDataset: [[String: Any?]])
}

class CameraCapturePipeline: NSObject {
    
    // MARK: Public API's
    var delegate: CameraCapturePipelineDelegate?
    var track: Bool = false
    fileprivate (set) var detectedFaceDataset: [[String: Any?]] = []
    
    // MARK: Private API's
    fileprivate var device: AVCaptureDevice?
    fileprivate var captureSession: AVCaptureSession?
    fileprivate var captureInput: AVCaptureDeviceInput?
    fileprivate var captureOutput: AVCaptureVideoDataOutput?
    fileprivate var outputQueue: DispatchQueue?
    fileprivate var previewLayer: AVCaptureVideoPreviewLayer?
    fileprivate var captureVideoConnection: AVCaptureConnection?
    fileprivate var running: Bool = false
    fileprivate lazy var faceLandmarkRequest: VNDetectFaceLandmarksRequest = {
        let request: VNDetectFaceLandmarksRequest = VNDetectFaceLandmarksRequest(completionHandler: self.didDetectFacesFor )
        return request
    }()
    fileprivate var detectedFaceCount: Int = 0 {
        didSet {
            if self.detectedFaceCount != oldValue {
                self.shoulStartTracking = false
            }
        }
    }
    fileprivate var shoulStartTracking: Bool = false
    fileprivate var faceTrackingRequests: [VNTrackObjectRequest] = []
    fileprivate lazy var sequenceRequestHandler = {
       return VNSequenceRequestHandler()
    }()
    
    // MARK: Initialization
    init(withDelegate delegate: UIViewController) {
        
    }
    
    func openCameraPipeline() {
        // start session
        self.setupCaptureSession()
        guard let session = captureSession else{
            // session optional is nil, propagete error
            return
        }
        session.startRunning()
    }
    
    fileprivate func setupCaptureSession() {
        guard let _ = captureSession else {
            return // return if session instance already exists
        }
        
        // initialize capture session
        self.captureSession = AVCaptureSession()
        // select camera device (prefrabely front camera), if avaliable
        var captureDevice = AVCaptureDevice.default(for: .video)
        let deviceSession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
        for captureDeviceObj in deviceSession.devices {
            if captureDeviceObj.hasMediaType(.video) {
                if captureDeviceObj.position == .front {
                    captureDevice = captureDeviceObj
                    self.device = captureDevice
                }
            }
        }
        
        // initialize capture device input
        do {
            let captureIn = try AVCaptureDeviceInput(device: captureDevice!)
            
            // add input to session
            if self.captureSession?.canAddInput(captureIn) == true {
                self.captureSession?.addInput(captureIn)
                self.captureInput = captureIn
            } else {
                // cannot add output, issue return
                return
            }
        } catch {
            // handle error, could not intialize AVACptureInput
            return
        }
        
        // initialize capture device output and output queue
        // create serial queue, with priority '.userInteractive'
        let outputQueue = DispatchQueue(label: "\(String(describing: Bundle.main.bundleIdentifier))_SerialHighPriourityCaptureOutput")
        outputQueue.setTarget(queue: DispatchQueue.global(qos: .userInteractive) )
        
        // create output
        let captureOut = AVCaptureVideoDataOutput()
        captureOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int( kCVPixelFormatType_32BGRA )]
        captureOut.alwaysDiscardsLateVideoFrames = false
        captureOut.setSampleBufferDelegate(self, queue: outputQueue)
        
        // add output to capture session
        if (self.captureSession?.canAddOutput(captureOut))! == true {
            self.captureSession?.addOutput(captureOut)
            self.captureOutput = captureOut
        }
        
        // get AVVideoConnection
        self.captureVideoConnection = self.captureOutput?.connection(with: .video)
        
        // configure captureDevice 'framerate' and captureSession video 'presets' as per the processor avaliable within the device, to maintain realtime processing and optimising the code, similar performance.
        var framePerSecond = 30
        var sessionVideoPreset = AVCaptureSession.Preset.medium
        if (ProcessInfo.processInfo.processorCount == 1) {
            sessionVideoPreset = AVCaptureSession.Preset.vga640x480
            framePerSecond = 15
        }
        self.captureSession?.sessionPreset = sessionVideoPreset
        
        do {
            if ((try self.device?.lockForConfiguration()) != nil) == true {
                let frameTime = CMTimeMake(Int64( framePerSecond ), Int32( 1 ))
                self.device?.activeVideoMaxFrameDuration = frameTime
                self.device?.activeVideoMinFrameDuration = frameTime
                self.device?.unlockForConfiguration()
            }
        } catch {
            // some error occoured, during device configuration lock and unlock
            return
        }
        
        // add preview layer, to delegate's view, since its a ViewController
        guard let delegatee = self.delegate else {
            // delegate not assigned, is optional nil, throw error
            return
        }
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession!)
        self.previewLayer?.frame = ((delegatee as? UIViewController)?.view.frame)!
        
        (delegatee as? UIViewController)?.view.layer.addSublayer(self.previewLayer!)
    }
    
    // MARK: Utility Methods
    fileprivate func convertPoints(forface landmark: VNFaceLandmarkRegion2D?, having boundingBox: CGRect) -> [CGPoint] {
        guard let points = landmark?.points, let count = landmark?.pointCount else {
            return []
        }
        var arrayToReturn: [CGPoint] = []
        let extractedPoints = self.convert(pointer: points, having: count)
        arrayToReturn = extractedPoints.map{ (inputPoint) -> CGPoint in
            let pointX = inputPoint.x * (boundingBox.size.width + boundingBox.origin.x)
            let pointY = inputPoint.y * (boundingBox.size.height + boundingBox.origin.y)
            return CGPoint(x: pointX, y: pointY)
        }
        return arrayToReturn
    }
    
    func convert(pointer points: UnsafePointer<vector_float2>, having count: Int) -> [CGPoint] {
        var arrToReturn: [CGPoint] = []
        for i in 0...count {
            arrToReturn.append( CGPoint(x: CGFloat(points[i].x), y: CGFloat(points[i].y)) )
        }
        return arrToReturn
    }
    
    fileprivate func createDataset(from observation: VNFaceObservation) -> [String: Any?] {
        let viewSize = UIScreen.main.bounds.size
        let uuid = observation.uuid.uuidString
        let faceBoundingBox = observation.boundingBox.scale(to: viewSize)
        let outerLipCoordinate = self.convertPoints(forface: observation.landmarks?.outerLips, having: faceBoundingBox)
        let noseCoordinates = self.convertPoints(forface: observation.landmarks?.nose, having: faceBoundingBox)
        let noseCrestCoordinates = self.convertPoints(forface: observation.landmarks?.noseCrest, having: faceBoundingBox)
        let faceLandmarkDataset: [String: Any?] = ["uuid": uuid,
                                                   "faceRectangle": faceBoundingBox,
                                                   "lipsCoordinate": outerLipCoordinate.isEmpty == false ? outerLipCoordinate : nil,
                                                   "noseCoordinate": noseCoordinates.isEmpty == false ? noseCoordinates : nil,
                                                   "noseCrestCoordinate": noseCrestCoordinates.isEmpty == false ? noseCrestCoordinates: nil]
        return faceLandmarkDataset
    }
    
    func didDetectFacesFor(request req: VNRequest, error err: Error?) {
        guard let observations = req.results as? [VNFaceObservation], observations.count != 0 else {
            return
        }
        self.detectedFaceCount = observations.count
        
        if self.shoulStartTracking == false && self.detectedFaceCount > 0 && track == true {
            // get all the observation Objects that have not formed the tracking requests in 'faceTrackingRequests'
            let filteredObservations = observations.filter({ (obs) -> Bool in
                var contains: Bool = false
                contains = self.faceTrackingRequests.contains(where: { (trackObj) -> Bool in
                    var containsObs: Bool = false
                    for result in trackObj.results as! [VNFaceObservation] {
                        let biggerRect = CGRect(x: result.boundingBox.origin.x - 20.0, y: result.boundingBox.origin.y - 20.0, width: result.boundingBox.size.width + 40.0, height: result.boundingBox.size.height + 40.0)
                        if biggerRect.contains(obs.boundingBox) == true {
                            containsObs = true
                        }
                    }
                    return containsObs
                })
                return !contains
            })
            
            for filteredObservation in filteredObservations {
                let newTrackRequest = VNTrackObjectRequest(detectedObjectObservation: filteredObservation, completionHandler: self.didTrackFacesFor )
                self.faceTrackingRequests.append(newTrackRequest)
                
                // make dataStructure and fire delegate method to notify viewController of detectedFaceFeatures
                let faceLandmarkDataset = self.createDataset(from: filteredObservation)
                self.detectedFaceDataset.append(faceLandmarkDataset)
            }
            
            for observation in observations {
                if let foundIndex = self.detectedFaceDataset.index(where: { (obs) -> Bool in
                    let boundingBox = obs["faceRectangle"] as! CGRect
                    let biggerBox: CGRect = CGRect(x: boundingBox.origin.x - 20.0, y: boundingBox.origin.y - 20.0, width: boundingBox.size.width + 40.0, height: boundingBox.size.height + 20.0)
                    return biggerBox.contains(observation.boundingBox)
                }) {
                    // matching uuid index found, remove and replace
                    let obs = self.createDataset(from: observation)
                    self.detectedFaceDataset.remove(at: foundIndex)
                    self.detectedFaceDataset.insert(obs, at: foundIndex)
                } else {
                    // matching uuid index not found, create dataSet and add to array
                    let newObs = self.createDataset(from: observation)
                    self.detectedFaceDataset.append(newObs)
                }
            }
            
            self.shoulStartTracking = true
            if self.detectedFaceDataset.isEmpty == false {
                DispatchQueue.main.async {
                    if let delegate = self.delegate {
                        delegate.cameraCapture(Pipeline: self, didDetectFaces: self.detectedFaceDataset)
                    }
                }
            }
        }
    }
    
    func didTrackFacesFor(request req: VNRequest, error err: Error?) {
        // do something, with tracked faces
        guard let observations = req.results as? [VNFaceObservation] else {
            return
        }
        for observation in observations {
            let uuid = observation.uuid.uuidString
            if let foundIndex = self.detectedFaceDataset.index(where: { (obs) -> Bool in
                return String(describing: obs["uuid"]) == uuid
            }) {
                // matching uuid index found, remove and replace
                let obs = self.createDataset(from: observation)
                self.detectedFaceDataset.remove(at: foundIndex)
                self.detectedFaceDataset.insert(obs, at: foundIndex)
            } else {
                // matching uuid index not found, create dataSet and add to array
                let newObs = self.createDataset(from: observation)
                self.detectedFaceDataset.append(newObs)
            }
        }
        if self.detectedFaceDataset.isEmpty == false {
            DispatchQueue.main.async {
                if let delegate = self.delegate {
                    delegate.cameraCapture(Pipeline: self, didUpdateFaces: self.detectedFaceDataset)
                }
            }
        }
    }
}

extension CameraCapturePipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // do something with sample buffer output, get CVPixelBuffer from the C<SampleBuffer
        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        var requestOptions:[VNImageOption: Any] = [:]
        if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics:cameraIntrinsicData]
        }
        
        let videoExifOrientation = self.captureVideoConnection?.videoOrientation
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: Int32(1), options: requestOptions)
        do {
            try imageRequestHandler.perform([self.faceLandmarkRequest])
        } catch {
            // handle error if any
        }
        
        if shoulStartTracking == true {
            do {
                try self.sequenceRequestHandler.perform(self.faceTrackingRequests, on: pixelBuffer, orientation: Int32(1))
            } catch {
                // hndle error
            }
        }
    }
}


extension CGRect {
    func scale(to size: CGSize) -> CGRect {
        return CGRect(x: self.origin.x * size.width,
                      y: self.origin.y * size.height,
                      width: self.size.width * size.width,
                      height: self.size.height * size.height)
    }
}
