import AVFoundation
import SwiftUI
import VisionKit
import WarrantKit

/// Scans an evidence bundle from a QR code on a laptop screen.
///
/// Everything here stays on the device: the camera feed is not recorded and nothing is
/// uploaded, which is what makes "scan this and check it yourself" a real offer.
struct BundleScannerView: View {
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var unavailable: String?

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerRepresentable(onScan: onScan)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    VStack(spacing: 12) {
                        Text("This device can't scan codes.")
                            .warrantType(.title)
                        Text("Import the bundle from a file or paste it from the clipboard instead.")
                            .warrantType(.body)
                            .foregroundStyle(Ink.soft)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Metric.gutter)
                }
            }
            .background(Ink.surface)
            .navigationTitle("Scan a bundle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        try? controller.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !hasScanned else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    hasScanned = true
                    dataScanner.stopScanning()
                    onScan(payload)
                    return
                }
            }
        }
    }
}
