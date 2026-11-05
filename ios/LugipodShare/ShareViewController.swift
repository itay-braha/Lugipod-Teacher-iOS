import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Share Extension behind "Share → לוגיפוד" (Notability's quick share, Files, Photos...). It
/// receives the PDF or photo, shows the teacher's lessons (the last finished one preselected) and
/// uploads the file as that lesson's summary file. See Shared/ShareView.swift for the screen.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Theme.page)
        Task { await start() }
    }

    private func start() async {
        let providers = ((extensionContext?.inputItems as? [NSExtensionItem]) ?? []).flatMap { $0.attachments ?? [] }
        guard let file = await Self.firstFile(in: providers) else {
            let alert = UIAlertController(title: "אי אפשר לשתף את זה", message: "אפשר לשתף ללוגיפוד קובץ PDF או תמונה.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "סגירה", style: .default) { [weak self] _ in self?.close() })
            present(alert, animated: true)
            return
        }

        let model = ShareModel(file: file)
        let host = UIHostingController(rootView: ShareView(
            model: model,
            onClose: { [weak self] in self?.close() },
            onDone: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        ))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        await model.load()
    }

    private func close() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    // MARK: Reading the shared item

    /// A PDF if there is one, else the first image.
    private static func firstFile(in providers: [NSItemProvider]) async -> SharedFile? {
        for type in [UTType.pdf, UTType.image] {
            if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) }),
               let file = await copyOut(provider, type: type) {
                return file
            }
        }
        return nil
    }

    /// The system hands over a temporary file that disappears when the callback returns, so copy it.
    private static func copyOut(_ provider: NSItemProvider, type: UTType) async -> SharedFile? {
        await withCheckedContinuation { (cont: CheckedContinuation<SharedFile?, Never>) in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { cont.resume(returning: nil); return }
                do {
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let ext = url.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "pdf") : url.pathExtension
                    var name = (provider.suggestedName ?? url.deletingPathExtension().lastPathComponent)
                        .replacingOccurrences(of: "/", with: "_")
                    if !name.lowercased().hasSuffix("." + ext.lowercased()) { name += "." + ext }
                    let dest = dir.appendingPathComponent(name)
                    try FileManager.default.copyItem(at: url, to: dest)
                    let size = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    cont.resume(returning: SharedFile(url: dest, name: name, mime: SharedFile.mimeType(for: dest), size: size))
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
