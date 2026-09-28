//
//  IntroductionWindowController.swift
//  Mos
//  简介界面
//  Created by Caldis on 15/11/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class IntroductionWindowController: NSWindowController, NSWindowDelegate {
    
    @IBOutlet weak var introductionWindow: NSWindow!

    static func present(manually: Bool = false) {
        let id = WINDOW_IDENTIFIER.introductionWindowController
        if WindowManager.shared.refs[id] == nil {
            let controller: NSWindowController = Utils.instantiateControllerFromStoryboard(withIdentifier: id)
            WindowManager.shared.refs[id] = controller
        }
        let controller = WindowManager.shared.refs[id]
        (controller?.contentViewController as? IntroductionViewController)?.setManuallyOpened(manually)
        WindowManager.shared.showWindow(withIdentifier: id, withTitle: "Chuu")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.titleVisibility = .hidden
        window?.styleMask.remove(.resizable)
        window?.setContentSize(NSSize(width: 460, height: 440))
        window?.center()
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.refs.removeValue(forKey: WINDOW_IDENTIFIER.introductionWindowController)
        let otherWindows = NSApp.windows.filter {
            $0 !== window && $0.isVisible && $0.level == .normal && !($0 is NSPanel)
        }
        if otherWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
            Utils.isDockIconVisible = false
        }
    }
    
}
