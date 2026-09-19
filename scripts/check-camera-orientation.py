#!/usr/bin/env python3
"""Run geometry and real AVFoundation segment-export checks on macOS."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
helper = (root / 'lucky7/Utilities/VideoOrientationHelper.swift').read_text().replace('import UIKit', 'import Foundation')
engine = (root / 'lucky7/Utilities/ExportEngine.swift').read_text()
start = engine.index('    func concatenateRawSegments(')
end = engine.index('    // MARK: - Period recaps', start)
source = helper + '\nimport AppKit\n' + '''
enum AppConstants { static let wrappedOutputFPS: Double = 60 }
enum RecordingDiagnostics { static func log(_ message: String) { print(message) } }
final class ExportEngine {
''' + engine[start:end] + '}\n' + (root / 'scripts/CameraOrientationChecks.swift').read_text()
with tempfile.TemporaryDirectory(prefix='rushhour-orientation-') as directory:
    path = Path(directory)
    (path / 'checks.swift').write_text(source)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(path / 'checks.swift'), '-o', str(path / 'checks')], check=True)
    subprocess.run([str(path / 'checks'), directory], check=True)
