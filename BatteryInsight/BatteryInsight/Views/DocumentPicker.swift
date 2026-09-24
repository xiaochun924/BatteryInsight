import SwiftUI
import UniformTypeIdentifiers

/// 基于 UIKit `UIDocumentPickerViewController` 的文件选择器。
///
/// 为什么不直接用 SwiftUI 的 `.fileImporter`：
/// 在**真机 iPhone** 上（Apple 开发者论坛 thread/775056，iOS 17 起多个版本均有报告），
/// `.fileImporter` 弹出的选择器能打开、文件也列得出来，但**点了文件既选不中、
/// 面板也不关闭**，`onCompletion` 永远不回调；同样的代码在模拟器、iPad、
/// Mac Catalyst 上完全正常。表现就是"选什么文件都无法完成"。
/// 换成 UIKit 这套选择器后真机行为正常，因此全项目统一走这里。
struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    var allowsMultipleSelection: Bool = false
    let onPick: ([URL]) -> Void
    var onCancel: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> DocumentPickerHostController {
        let controller = DocumentPickerHostController()
        controller.contentTypes = contentTypes
        controller.allowsMultipleSelection = allowsMultipleSelection
        controller.onPick = onPick
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ controller: DocumentPickerHostController, context: Context) {
        controller.contentTypes = contentTypes
        controller.allowsMultipleSelection = allowsMultipleSelection
        controller.onPick = onPick
        controller.onCancel = onCancel
    }
}

/// 一个空白宿主 VC，只在 `viewDidAppear` 里把真正的选择器弹出来。
///
/// 之所以多包一层：SwiftUI 的 `.sheet` 内容一旦是 `UIDocumentPickerViewController`
/// 本身，present 时机可能早于视图进窗口层级，会报
/// "Attempt to present … whose view is not in the window hierarchy"。
/// 放进 `viewDidAppear` 就没有这个时序问题。
final class DocumentPickerHostController: UIViewController, UIDocumentPickerDelegate {
    var contentTypes: [UTType] = [.data]
    var allowsMultipleSelection = false
    var onPick: (([URL]) -> Void)?
    var onCancel: (() -> Void)?

    /// `viewDidAppear` 在 sheet 尺寸调整等场景会重复触发，只弹一次
    private var didPresent = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // 选择器自己铺满屏幕，宿主保持透明，避免选择器关闭瞬间闪一下白底
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresent else { return }
        didPresent = true

        // asCopy: true —— 拷一份到本 App 临时目录再读，避免直接依赖源位置的访问权限
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes,
                                                   asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        onPick?(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onCancel?()
    }
}
