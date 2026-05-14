import SwiftUI
import UIKit
import Vision
import VisionKit

enum QRCodeImageDecoder {
    enum DecodeError: Error {
        case noImage
        case notFound
    }

    static func firstQRPayload(in image: UIImage) throws -> String {
        guard let cgImage = image.cgImage else {
            throw DecodeError.noImage
        }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        for observation in observations {
            if let payload = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !payload.isEmpty {
                return payload
            }
        }
        throw DecodeError.notFound
    }
}

struct DataScannerViewRepresentable: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onScan: (String) -> Void
    var onStartFailed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        context.coordinator.sync(
            isPresented: $isPresented,
            onScan: onScan,
            onStartFailed: onStartFailed,
            controller: uiViewController
        )
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        coordinator.reset()
        Task { @MainActor in
            uiViewController.stopScanning()
        }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private weak var controller: DataScannerViewController?
        private var didScheduleStart = false
        private var onScanHandler: ((String) -> Void)?
        private var onStartFailedHandler: (() -> Void)?
        private var dismissHandler: (() -> Void)?

        func sync(
            isPresented: Binding<Bool>,
            onScan: @escaping (String) -> Void,
            onStartFailed: @escaping () -> Void,
            controller: DataScannerViewController
        ) {
            self.controller = controller
            onScanHandler = onScan
            onStartFailedHandler = onStartFailed
            dismissHandler = { isPresented.wrappedValue = false }

            guard isPresented.wrappedValue else { return }
            guard !didScheduleStart else { return }
            didScheduleStart = true
            Task { @MainActor in
                do {
                    try controller.startScanning()
                } catch {
                    onStartFailedHandler?()
                    isPresented.wrappedValue = false
                    didScheduleStart = false
                }
            }
        }

        func reset() {
            didScheduleStart = false
            controller = nil
            onScanHandler = nil
            onStartFailedHandler = nil
            dismissHandler = nil
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle(item: item, dataScanner: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                handle(item: item, dataScanner: dataScanner)
            }
        }

        private func handle(item: RecognizedItem, dataScanner: DataScannerViewController) {
            guard case let .barcode(barcode) = item else { return }
            guard let payload = barcode.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !payload.isEmpty else {
                return
            }
            onScanHandler?(payload)
            Task { @MainActor in
                dataScanner.stopScanning()
                dismissHandler?()
                reset()
            }
        }
    }
}

struct DataScannerShellView: View {
    @Binding var isPresented: Bool
    var onScan: (String) -> Void
    var onStartFailed: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            DataScannerViewRepresentable(isPresented: $isPresented, onScan: onScan, onStartFailed: onStartFailed)
                .ignoresSafeArea()

            Button("关闭") {
                isPresented = false
            }
            .font(.headline.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.45), in: Capsule())
            .padding(.leading, AppTheme.pageHorizontalPadding)
            .padding(.top, 16)
            .accessibilityIdentifier("ScanBindingScannerClose")
        }
    }
}
