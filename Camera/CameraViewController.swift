//
//  CameraViewController.swift
//  VuforiaSample
//
//  Created by Anton Poltoratskyi on 12/18/17.
//  Copyright © 2017 Anton Poltoratskyi. All rights reserved.
//

import UIKit
import SafariServices

final class CameraViewController: UIViewController, StoryboardInitializable {
    static let storyboardName: String = "Main"

    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var bottomContainerView: UIView!
    @IBOutlet weak var cameraButton: CameraButton!
    
    
    // MARK: - State
    
    private enum State {
        case undefined
        case unavailable
        case preparing
        case active
        case inactive
        
        var isActive: Bool {
            return self == .active
        }
        var isAvailable: Bool {
            return self == .active || self == .inactive
        }
    }
    
    private var state: State = .undefined {
        didSet {
            switch state {
            case .active:
                self.stopLoading()
            case .undefined, .preparing:
                self.startLoading()
            case .unavailable:
                self.stopLoading()
            case .inactive:
                break
            }
            cameraButton.isUserInteractionEnabled = state.isAvailable
        }
    }
    
    private var shouldRecognizeObjects: Bool = false
    private var isAppeared: Bool = false
    
    
    // MARK: - Dependencies
    
    /// Referenced from: https://github.com/yshrkt/VuforiaSampleSwift
    private lazy var vuforiaManager: VuforiaManager = {
        guard let vuforia = VuforiaManager(licenseKey: Constants.Vuforia.licenseKey, dataSetFile: Constants.Vuforia.dataSetFile) else {
            fatalError("Unable to init VuforiaManager")
        }
        vuforia.delegate = self
        return vuforia
    }()


    // MARK: - Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        state = .undefined
        prepareForRecognition()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(false, animated: true)
        if isAppeared, !state.isActive {
            resumeRecognition()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        guard let navigationController = self.navigationController else { return }

        // check if dissapear on pop, not on push
        let currentIndex = navigationController.viewControllers.index(where: { $0 === self })
        if currentIndex == nil {
            self.navigationController?.setNavigationBarHidden(true, animated: true)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isAppeared = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pauseRecognition()
        cameraButton.disable()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopRecognition()
    }


    // MARK: - UI Setup

    private func setupUI() {
        guard let eaglView = vuforiaManager.eaglView else {
            return
        }
        eaglView.translatesAutoresizingMaskIntoConstraints = false
        self.view.insertSubview(eaglView, at: 0)

        NSLayoutConstraint.activate([
            eaglView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            eaglView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            eaglView.topAnchor.constraint(equalTo: self.view.topAnchor),
            eaglView.bottomAnchor.constraint(equalTo: self.bottomContainerView.topAnchor)
            ]
        )
    }
    
    
    // MARK: - Animations
    
    private func startLoading() {
        activityIndicator.startAnimating()
    }
    
    private func stopLoading() {
        activityIndicator.stopAnimating()
    }


    // MARK: - Vuforia

    private func prepareForRecognition() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(didRecieveWillResignActiveNotification(_:)),
                           name: .UIApplicationWillResignActive, object: nil)

        center.addObserver(self, selector: #selector(didRecieveDidBecomeActiveNotification(_:)),
                           name: .UIApplicationDidBecomeActive, object: nil)

        vuforiaManager.prepare(with: .portrait)
        
        state = .preparing
    }

    private func startRecognition() {
        do {
            try vuforiaManager.start()
            vuforiaManager.setContinuousAutofocusEnabled(true)
            state = .active
        } catch { }
    }

    private func stopRecognition() {
        do {
            try vuforiaManager.stop()
            state = .inactive
        } catch { }
    }

    private func resumeRecognition() {
        do {
            try vuforiaManager.resume()
            state = .active
        } catch { }
    }
    
    private func pauseRecognition() {
        do {
            try vuforiaManager.pause()
            state = .inactive
        } catch { }
    }
    
    
    // MARK: - Actions

    @IBAction func actionToggleCameraFlash(_ sender: Any) {
        vuforiaManager.setFlashEnabled(!vuforiaManager.flashEnabled)
    }
    
    @IBAction func actionToggleCamera(_ sender: CameraButton) {
        guard state.isAvailable else { return }
        
        switch state {
        case .undefined, .preparing, .unavailable:
            // currently unavailable state
            break
        case .active, .inactive:
            sender.toggle()
            shouldRecognizeObjects = !shouldRecognizeObjects
        }
    }
    
    @IBAction func actionShowInfo(_ sender: Any) {
        presentInfo()
    }
    
    
    // MARK: - Navigation
    
    private func canPresentTrackable(_ object: TrackableObject) -> Bool {
        return URL(from: object) != nil
    }

    private func presentTrackable(_ object: TrackableObject) {
        self.shouldRecognizeObjects = false
        guard let url = URL(from: object) else {
            return
        }
        let safari = SFSafariViewController(url: url)
        self.present(safari, animated: true, completion: nil)
    }
    
    private func presentInfo() {
        self.shouldRecognizeObjects = false
        let infoViewController = InfoViewController.instantiateFromStoryboard()
        self.present(infoViewController, animated: true, completion: nil)
    }
}

// MARK: - Application Life Cycle Events

extension CameraViewController {
    @objc func didRecieveWillResignActiveNotification(_ notification: Notification) {
        pauseRecognition()
    }

    @objc func didRecieveDidBecomeActiveNotification(_ notification: Notification) {
        resumeRecognition()
    }
}


// MARK: - VuforiaManagerDelegate

extension CameraViewController: VuforiaManagerDelegate {

    func vuforiaManagerDidFinishPreparing(_ manager: VuforiaManager!) {
        DispatchQueue.main.async {
            self.startRecognition()
        }
    }

    func vuforiaManager(_ manager: VuforiaManager!, didFailToPreparingWithError error: Error!) {
        DispatchQueue.main.async {
            self.state = .unavailable
        }
    }

    func vuforiaManager(_ manager: VuforiaManager!, didUpdateWith state: VuforiaState!) {
        guard manager != nil, let state = state else { return }

        let trackableObjects = (0..<state.numberOfTrackableResults).flatMap { index -> TrackableObject? in
            guard let result = state.trackableResult(at: index) else {
                return nil
            }
            guard let trackableObject = result.trackable else {
                return nil
            }
            return TrackableObject(identifier: trackableObject.identifier, name: trackableObject.name)
        }
        guard let object = trackableObjects.first, canPresentTrackable(object) else {
            return
        }
        DispatchQueue.main.async {
            guard self.shouldRecognizeObjects else { return }
            self.presentTrackable(object)
        }
    }
}
