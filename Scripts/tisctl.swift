#!/usr/bin/env swift
// Petit outil en ligne de commande autour des API TIS (Carbon/HIToolbox), utilisé par
// install.sh / uninstall.sh — ces API n'ont pas d'équivalent shell direct.
import Foundation
import Carbon.HIToolbox

func stringProp(_ src: TISInputSource, _ key: CFString) -> String? {
    guard let p = TISGetInputSourceProperty(src, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

func boolProp(_ src: TISInputSource, _ key: CFString) -> Bool {
    guard let p = TISGetInputSourceProperty(src, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
}

func findSource(id: String) -> TISInputSource? {
    guard let raw = TISCreateInputSourceList(nil, true)?.takeRetainedValue() else { return nil }
    let list = raw as! [TISInputSource]
    return list.first { stringProp($0, kTISPropertyInputSourceID) == id }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fail("usage: tisctl.swift <register|enable|select|deselect|disable|is-enabled|wait-enabled> <path-or-id>")
}

let cmd = args[1]
let arg = args.count > 2 ? args[2] : ""

switch cmd {
case "register":
    let url = URL(fileURLWithPath: arg)
    let status = TISRegisterInputSource(url as CFURL)
    print("TISRegisterInputSource(\(arg)) -> \(status)")
    exit(status == noErr ? 0 : 1)

case "is-enabled":
    // Lecture unique, dans un process neuf. Voir wait-enabled pour le pourquoi.
    guard let src = findSource(id: arg) else { exit(2) }
    exit(boolProp(src, kTISPropertyInputSourceIsEnabled) ? 0 : 1)

case "wait-enabled":
    // Deux pièges cumulés ici, tous deux mesurés au ticket 09 :
    //
    // 1. Le flip enabled=0->1 n'arrive QUE si TISEnableInputSource a été appelé AVANT le
    //    lancement du process de la palette. L'appel renvoie 0 en laissant enabled=false :
    //    c'est une intention en attente, que le daemon valide à la poignée de main IMK.
    //
    // 2. TISCreateInputSourceList sert une liste MISE EN CACHE PAR PROCESS. Une boucle de
    //    poll dans un seul process ne verra donc JAMAIS le flip, même après une minute —
    //    mesuré côte à côte : process neuf à chaque lecture = flip vu à 10 s ; process
    //    unique = enabled=false pendant les 40 s. D'où le fork à chaque tour ci-dessous.
    //    (C'est ce qui faisait échouer install.sh en aval même une fois le piège 1 corrigé.)
    //
    // Délai mesuré entre le lancement et le flip : 5 à 11 s.
    let selfPath = args[0]
    let deadline = Date().addingTimeInterval(40)
    while Date() < deadline {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        probe.arguments = ["swift", selfPath, "is-enabled", arg]
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        try? probe.run()
        probe.waitUntilExit()
        if probe.terminationStatus == 0 {
            print("enabled")
            exit(0)
        }
        Thread.sleep(forTimeInterval: 0.5)
    }
    fail("timeout: \(arg) toujours pas enabled après 40s")

case "enable":
    guard let src = findSource(id: arg) else { fail("source introuvable: \(arg)") }
    let status = TISEnableInputSource(src)
    print("TISEnableInputSource -> \(status)")
    exit(status == noErr ? 0 : 1)

case "select":
    guard let src = findSource(id: arg) else { fail("source introuvable: \(arg)") }
    let status = TISSelectInputSource(src)
    print("TISSelectInputSource -> \(status)")
    exit(status == noErr ? 0 : 1)

case "deselect":
    guard let src = findSource(id: arg) else { print("déjà absent: \(arg)"); exit(0) }
    let status = TISDeselectInputSource(src)
    print("TISDeselectInputSource -> \(status)")
    exit(0)

case "disable":
    guard let src = findSource(id: arg) else { print("déjà absent: \(arg)"); exit(0) }
    let status = TISDisableInputSource(src)
    print("TISDisableInputSource -> \(status)")
    exit(0)

case "list":
    guard let raw = TISCreateInputSourceList(nil, true)?.takeRetainedValue() else { exit(0) }
    for src in (raw as! [TISInputSource]) {
        let id = stringProp(src, kTISPropertyInputSourceID) ?? "?"
        let enabled = boolProp(src, kTISPropertyInputSourceIsEnabled)
        let selected = boolProp(src, kTISPropertyInputSourceIsSelected)
        print("\(id) enabled=\(enabled) selected=\(selected)")
    }
    exit(0)

default:
    fail("commande inconnue: \(cmd)")
}
