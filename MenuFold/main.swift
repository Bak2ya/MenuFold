import AppKit

// MenuFold is a storyboard-free LSUIElement app. Keep startup explicit so the
// NSApplication delegate that creates the NSStatusItem is unambiguous.
NSLog("MenuFold LIFECYCLE: main.swift entered")

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate

NSLog("MenuFold LIFECYCLE: AppDelegate attached; entering NSApplication.run()")
application.run()
