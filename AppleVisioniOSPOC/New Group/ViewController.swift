//
//  ViewController.swift
//  AppleVisioniOSPOC
//
//  Created by Varun on 27/06/17.
//  Copyright © 2017 Diet Code. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    // MARK: Public API's
    
    // MARK: Private API's
    fileprivate var faceDatasetArray: [[String: Any?]] = []
    fileprivate var mustacheLayerArray: [CALayer?] = []
    fileprivate var overlayLayer: CALayer = CALayer()
    fileprivate lazy var cameraPipeline: CameraCapturePipeline = {
       return CameraCapturePipeline(withDelegate: self)
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    // MARK: Lifecycle Methods
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let _ = self.cameraPipeline
        
        self.overlayLayer.frame = self.view.bounds
        // since it is reported, that the co-ordinate system is reversed in Vision.Framework
        self.overlayLayer.setAffineTransform( CGAffineTransform(translationX: -1.0, y: -1.0) )
        self.view.layer.addSublayer(self.overlayLayer)
        
        self.cameraPipeline.openCameraPipeline()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: Utility Methods
    fileprivate func configureMustache() {
        for i in 0..<self.faceDatasetArray.count {
            let obj = self.faceDatasetArray[i]
            if let outerLipsCoordinate = obj["lipsCoordinate"] as? [CGPoint],
                let noseCoordinate = obj["noseCoordinate"] as? [CGPoint],
                let noseCrestCoordinate = obj["noseCrestCoordinate"] as? [CGPoint] {
                if let maxXPoint = outerLipsCoordinate.max(by: { (obj1, obj2) -> Bool in
                    return obj1.x < obj2.x
                }), let minXPoint = outerLipsCoordinate.min(by: { (obj1, obj2) -> Bool in
                    return obj1.x < obj2.x
                }), let maxYPoint = outerLipsCoordinate.min(by: { (obj1, obj2) -> Bool in
                    return obj1.y < obj2.y
                }), let minYPoint = noseCoordinate.max(by: { (obj1, obj2) -> Bool in
                    return obj1.y < obj2.y
                }), let minYPoint1 = noseCrestCoordinate.max(by: { (obj1, obj2) -> Bool in
                    return obj1.y < obj2.y
                }) {
                    let maxX = maxXPoint.x
                    let minX = minXPoint.x
                    let maxY = maxYPoint.y
                    let minY = max(minYPoint.y, minYPoint1.y)
                    let width = maxX - minX
                    let height = maxY - minY
                    let mustacheRect = CGRect(x: minX, y: minY, width: width, height: height)
                    let newMustacheOrigin = CGPoint(x: minX, y: minY)
                    if let mustacheLayer = self.mustacheLayerArray[i] {
                        // not nil, there is already an element in the array
                        self.configureAnimationFor(mustacheLayer: mustacheLayer, to: newMustacheOrigin, with: mustacheRect)
                    } else {
                        // nil, create an element and add itvto the index in the array
                        let image = UIImage(named: "some")?.ciImage
                        let mustacheLayer = CALayer()
                        mustacheLayer.frame = mustacheRect
                        mustacheLayer.opacity = 1.0
                        mustacheLayer.contents = image
                        mustacheLayer.contentsGravity = kCAGravityResizeAspect
                        mustacheLayer.contentsRect = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
                        self.overlayLayer.addSublayer(mustacheLayer)
                        self.mustacheLayerArray.insert(mustacheLayer, at: i)
                        self.configureAnimationFor(mustacheLayer: mustacheLayer, to: newMustacheOrigin, with: mustacheRect)
                    }
                }
            }
        }
    }
    
    fileprivate func configureAnimationFor(mustacheLayer layer: CALayer, to position: CGPoint, with bounds: CGRect) {
        layer.removeAllAnimations()
        
        let positionAnimation = CABasicAnimation(keyPath: "position")
        positionAnimation.fromValue = layer.frame.origin
        positionAnimation.toValue = position
        positionAnimation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
        positionAnimation.fillMode = kCAFillModeForwards
        positionAnimation.isRemovedOnCompletion = false
        positionAnimation.duration = Double( self.cameraPipeline.frameRate != nil ? ( 1.0/CGFloat(self.cameraPipeline.frameRate!) ) : ( 1.0/30.0 ) )
        layer.add(positionAnimation, forKey: "positionAnimation")
        
        let frameAnimation = CABasicAnimation(keyPath: "bounds")
        frameAnimation.fromValue = CGRect(x: layer.bounds.origin.x, y: layer.bounds.origin.x, width: layer.bounds.width, height: layer.bounds.width)
        frameAnimation.toValue = CGRect(x: layer.bounds.origin.x, y: layer.bounds.origin.x, width: bounds.size.width, height: bounds.size.height)
        frameAnimation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
        frameAnimation.fillMode = kCAFillModeForwards
        frameAnimation.isRemovedOnCompletion = false
        frameAnimation.duration = Double( self.cameraPipeline.frameRate != nil ? ( 1.0/CGFloat(self.cameraPipeline.frameRate!) ) : ( 1.0/30.0 ) )
        layer.add(frameAnimation, forKey: "frameAnimation")
        
    }
    
    fileprivate func cofigureFaceDataset(with obj: [String: Any?]) {
        let objectRect: CGRect = obj["faceRectangle"] as! CGRect
        if let index = self.faceDatasetArray.index(where: { (obj) -> Bool in
            var containsObj: Bool = false
            let objRect: CGRect = obj["faceRectangle"] as! CGRect
            let biggerRect: CGRect = CGRect(x: objRect.origin.x - 20.0, y: objRect.origin.y - 20.0, width: objRect.size.width - 40.0, height: objRect.size.width - 40.0)
            containsObj = biggerRect.contains(objectRect)
            return containsObj
        }) {
            // index present
            self.faceDatasetArray.remove(at: index)
            self.faceDatasetArray.insert(obj, at: index)
        } else {
            // index not present
            self.faceDatasetArray.append(obj)
        }
    }
}

extension ViewController: CameraCapturePipelineDelegate {
    func cameraCapture(Pipeline pipeline: CameraCapturePipeline, didDetectFaces faceDataset: [[String : Any?]]) {
        if self.faceDatasetArray.isEmpty {
            self.faceDatasetArray = faceDataset
        } else {
            if faceDataset.count > 0 {
                for i in self.faceDatasetArray.count..<faceDataset.count {
                    let obj = faceDataset[i]
                    self.cofigureFaceDataset(with: obj)
                }
            }
        }
        self.configureMustache()
        // code
    }
    
    func cameraCapture(Pipeline pipeline: CameraCapturePipeline, didUpdateFaces faceDataset: [[String : Any?]]) {
        if faceDataset.count > 0 {
            for i in self.faceDatasetArray.count..<faceDataset.count {
                let obj = faceDataset[i]
                self.cofigureFaceDataset(with: obj)
            }
        }
        // code
    }
    
    func cameraCapture(Pipeline pipeline: CameraCapturePipeline, didFailWith error: NSError) {
        // code
        print("ERROR OCCOURED: \(error.code) : \(error)")
    }
    
    func stoppedDetectingFaces(For pipeline: CameraCapturePipeline) {
        // code
        self.faceDatasetArray = []
        self.mustacheLayerArray = []
        if self.self.overlayLayer.sublayers?.isEmpty == false {
            for sublayer in self.overlayLayer.sublayers! {
                sublayer.removeFromSuperlayer()
            }
        }
    }
}

