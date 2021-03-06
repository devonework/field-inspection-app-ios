//
//  Recorder.swift
//  EAOInspect
//
//  Created by Amir Shayegh on 2018-02-04.
//  Copyright © 2018 Amir Shayegh. All rights reserved.
//

import Foundation
import UIKit

class Recorder {

    lazy var audioRecorderVC: AudioRecorderViewController = {
        return UIStoryboard(name: "AudioRecorder", bundle: Bundle.main).instantiateViewController(withIdentifier: "AudioRecorder") as! AudioRecorderViewController
    }()

    func getVC(inspectionID: String, observationID: String, callBack: @escaping ((_ close: Bool) -> Void )) -> UIViewController {
        audioRecorderVC.inspectionID = inspectionID
        audioRecorderVC.observationID = observationID
        audioRecorderVC.callBack =  callBack
        return audioRecorderVC
    }

    func display(in container: UIView, on viewController: UIViewController) {
        container.alpha = 1
        viewController.addChildViewController(audioRecorderVC)
        container.addSubview(audioRecorderVC.view)
        audioRecorderVC.view.frame = container.bounds
        audioRecorderVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        audioRecorderVC.didMove(toParentViewController: viewController)
    }

    /**
     Note: also hides container by setting alpha to 0
     */
    func remove(from container: UIView, then hide: Bool? = true) {
        audioRecorderVC.willMove(toParentViewController: nil)
        audioRecorderVC.view.removeFromSuperview()
        audioRecorderVC.removeFromParentViewController()
        if hide! {
            container.alpha = 0
        }
    }
}
