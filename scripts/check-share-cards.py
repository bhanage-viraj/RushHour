#!/usr/bin/env python3
"""Render production cards on an already booted iOS 27 simulator and check overflow.

Usage: python3 scripts/check-share-cards.py SIMULATOR_UUID EVIDENCE_DIRECTORY [COMPOSER_SOURCE]
Uses an isolated harness app; does not change Rush Hour data.
"""
from pathlib import Path
import subprocess
import sys
import tempfile
import shutil
root = Path(__file__).resolve().parents[1]
simulator = sys.argv[1]
evidence = Path(sys.argv[2]).resolve()
evidence.mkdir(parents=True, exist_ok=True)
temporary = tempfile.TemporaryDirectory(prefix='rushhour-share-card-check-')
out = Path(temporary.name)
composer = Path(sys.argv[3]) if len(sys.argv) > 3 else root/'lucky7/Views/SessionEnd/WrapShareComposer.swift'
text= composer.read_text()
card=text[text.index('private struct WrapTemplateCard:'):text.index('#Preview("Portrait wrap templates")')]
sizing = text[text.index('    private func fittedCardSize('):text.index('    private func adjustTemplate(')]
sizing = sizing.replace('private func fittedCardSize', 'func fittedCardSize')
constants = '\n'.join(line for line in text.splitlines()
                      if 'private static let cardSize =' in line or 'private static let cardTopPadding:' in line)
sizer = 'struct PosterModel { let posterImage: UIImage? }\nstruct CardSizer {\n' + constants + '\nlet viewModel: PosterModel\n' + sizing + '}\n'
source='import SwiftUI\nimport UIKit\n' + (root/'lucky7/Models/WrapTemplate.swift').read_text() + (root/'lucky7/Utilities/WrapTextLayout.swift').read_text() + card + sizer + r'''
@main
struct ShareCardCheck: App {
    var body: some Scene {
        WindowGroup { Text("Share-card checks").task { runChecks() } }
    }
    @MainActor func runChecks() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var failures = 0
        let background = UIColor(red: 1, green: 0, blue: 1, alpha: 1)
        for (name, dimensions) in [("landscape", CGSize(width: 1600, height: 900)),
                                   ("portrait", CGSize(width: 900, height: 1600))] {
            let poster = UIGraphicsImageRenderer(size: dimensions).image { context in
                UIColor.cyan.setFill(); context.fill(CGRect(origin: .zero, size: dimensions))
            }
            let sizer = CardSizer(viewModel: PosterModel(posterImage: poster))
            for available in [CGSize(width: 320, height: 350), CGSize(width: 402, height: 500),
                              CGSize(width: 1024, height: 600)] {
                let fitted = sizer.fittedCardSize(in: available)
                let correctRatio = abs(fitted.width / fitted.height - dimensions.width / dimensions.height) < 0.01
                let fits = fitted.width <= available.width - 32 && fitted.height <= available.height - 22
                let passed = correctRatio && fits && fitted.width > 0 && fitted.height > 0
                if !passed { failures += 1 }
                print("\(passed ? "PASS" : "FAIL"): \(name) share-page card in \(Int(available.width))pt container: \(fitted.width) × \(fitted.height)")
            }
            for template in WrapTemplate.allCases {
                for size in [CGSize(width: 256, height: 459), CGSize(width: 360, height: 203)] {
                    let content = ZStack(alignment: .topLeading) {
                        Color(uiColor: background)
                        WrapTemplateCard(image: poster, template: template,
                            metadata: WrapShareMetadata(title: "Morning Session", duration: "3h 20m", date: "3 Oct 2026"))
                            .frame(width: size.width, height: size.height)
                            .offset(x: 100, y: 40)
                    }.frame(width: 660, height: 550)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 1
                    guard let image = renderer.uiImage, let cg = image.cgImage else { fatalError("No render") }
                    let file = "\(name)-\(template.rawValue)-\(Int(size.width)).png"
                    try! image.pngData()!.write(to: directory.appendingPathComponent(file))
                    let width = cg.width, height = cg.height
                    var pixels = [UInt8](repeating: 0, count: width * height * 4)
                    let overflow = pixels.withUnsafeMutableBytes { bytes -> Int in
                        let ctx = CGContext(data: bytes.baseAddress, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
                        var count = 0
                        let buffer = bytes.bindMemory(to: UInt8.self)
                        for y in 0..<height {
                            for x in 0..<width {
                                if x >= 98 && x <= Int(100 + size.width) + 2 && y >= 38 && y <= Int(40 + size.height) + 2 { continue }
                                let i = (y * width + x) * 4
                                if buffer[i] < 250 || buffer[i+1] > 5 || buffer[i+2] < 250 { count += 1 }
                            }
                        }
                        return count
                    }
                    if overflow > 0 { failures += 1 }
                    print("\(overflow == 0 ? "PASS" : "FAIL"): \(file) overflow pixels=\(overflow)")
                }
            }
        }
        try! "failures=\(failures)\n".write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        exit(0)
    }
}
'''
(out/'Check.swift').write_text(source)
app=out/'ShareCardCheck.app'
app.mkdir(exist_ok=True)
(app/'Info.plist').write_text('''<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.rushhour.sharecardcheck</string><key>CFBundleName</key><string>ShareCardCheck</string><key>CFBundleExecutable</key><string>ShareCardCheck</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1</string><key>UILaunchScreen</key><dict/></dict></plist>''')
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
subprocess.run(['xcrun','swiftc','-sdk',sdk,'-target','arm64-apple-ios27.0-simulator','-parse-as-library','-module-cache-path',str(out/'cache'),str(out/'Check.swift'),'-o',str(app/'ShareCardCheck')],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)

subprocess.run(['xcrun', 'simctl', 'install', simulator, str(app)], check=True)
subprocess.run(['xcrun', 'simctl', 'launch', '--terminate-running-process', '--console',
                simulator, 'com.rushhour.sharecardcheck'], check=True, timeout=60)
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', simulator,
    'com.rushhour.sharecardcheck', 'data'], text=True).strip()) / 'Documents'
for image in container.glob('*.png'):
    shutil.copy2(image, evidence / image.name)
result = (container / 'result.txt').read_text()
(evidence / 'result.txt').write_text(result)
print(result.strip())
if result.strip() != 'failures=0':
    raise SystemExit(1)
