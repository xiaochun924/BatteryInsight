import SwiftUI
import ObjectiveC.runtime
import UniformTypeIdentifiers

/// 基于 UIKit `UIDocumentPickerViewController` 的文件选择器。
///
/// 为什么不直接用 SwiftUI 的 `.fileImporter`：
/// 在**真机 iPhone** 上（Apple 开发者论坛 thread/775056，iOS 17 起多个版本均有报告），
/// `.fileImporter` 弹出的选择器能打开、文件也列得出来，但**点了文件既选不中、
/// 面板也不关闭**，`onCompletion` 永远不回调；同样的代码在模拟器、iPad、
/// Mac Catalyst 上完全正常。表现就是"选什么文件都无法完成"。
/// 换成 UIKit 这套选择器后真机行为正常，因此全项目统一走这里。
///
/// 为什么是「直接 present」而不是「sheet 包一层 representable」：
/// 之前用 `.sheet { DocumentPicker(...) }`，sheet 里装的是一个透明宿主 VC，
/// 在 iPhone 上 sheet 卡片本身是白底 —— 于是点「导入」会先弹一张白卡，
/// 宿主 `viewDidAppear` 后才在其上弹出真正的选择器，看起来就是
/// "先跳白屏、再打开文件选择器"。现在改为**从当前最顶层 VC 直接 present
/// 系统选择器**，没有中间层，白屏随之消失。
enum DocumentPickerLauncher {

    /// 从最顶层 ViewController 直接弹出系统文件选择器。
    /// - `asCopy: true`：拷一份到本 App 临时目录再读，避免直接依赖源位置的访问权限
    @MainActor
    static func present(contentTypes: [UTType],
                        allowsMultipleSelection: Bool,
                        onPick: @escaping @MainActor ([URL]) -> Void,
                        onCancel: (@MainActor () -> Void)? = nil) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            var top = scene.keyWindow?.rootViewController else {
            onCancel?()
            return
        }
        // 顺着 presented 链找最顶层，避免 "whose view is not in the window hierarchy"
        while let presented = top.presentedViewController {
            top = presented
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes,
                                                    asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        let delegate = PickerDelegate(onPick: onPick, onCancel: onCancel)
        picker.delegate = delegate
        // picker.delegate 是弱引用，delegate 对象必须有人持有；
        // 挂在 picker 自身上，随 picker 一起释放
        objc_setAssociatedObject(picker, &PickerDelegate.associatedKey, delegate,
                                 .OBJC_ASSOCIATION_RETAIN)
        top.present(picker, animated: true)
    }
}

/// 选择器回调。选完 / 取消都先收起选择器再回调，
/// 否则回调里立刻弹 alert 会被"present 已在进行中"顶掉。
/// Swift 6：UIKit 委托回调运行在主线程，标记 @MainActor 满足严格并发。
@MainActor
private final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
    static var associatedKey: UInt8 = 0

    let onPick: @MainActor ([URL]) -> Void
    let onCancel: (@MainActor () -> Void)?

    init(onPick: @escaping @MainActor ([URL]) -> Void,
         onCancel: (@MainActor () -> Void)?) {
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        controller.dismiss(animated: true) { [onPick] in
            MainActor.assumeIsolated { onPick(urls) }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true) { [onCancel] in
            MainActor.assumeIsolated { onCancel?() }
        }
    }
}

// MARK: - SwiftUI 接入

/// 用法：`.documentPicker(isPresented: $showing, contentTypes: ...) { urls in ... }`
/// 把 `isPresented` 置 true 即弹出选择器；选完 / 取消都会自动把它置回 false。
struct DocumentPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let contentTypes: [UTType]
    var allowsMultipleSelection = false
    let onPick: @MainActor ([URL]) -> Void
    var onCancel: (@MainActor () -> Void)? = nil

    func body(content: Content) -> some View {
        // iOS 17+ 双参数版 onChange；部署目标已是 iOS 26
        content.onChange(of: isPresented) { _, presented in
            guard presented else { return }
            DocumentPickerLauncher.present(
                contentTypes: contentTypes,
                allowsMultipleSelection: allowsMultipleSelection
            ) { urls in
                isPresented = false
                onPick(urls)
            } onCancel: {
                isPresented = false
                onCancel?()
            }
        }
    }
}

extension View {
    func documentPicker(isPresented: Binding<Bool>,
                        contentTypes: [UTType],
                        allowsMultipleSelection: Bool = false,
                        onPick: @escaping @MainActor ([URL]) -> Void,
                        onCancel: (@MainActor () -> Void)? = nil) -> some View {
        modifier(DocumentPickerModifier(isPresented: isPresented,
                                        contentTypes: contentTypes,
                                        allowsMultipleSelection: allowsMultipleSelection,
                                        onPick: onPick,
                                        onCancel: onCancel))
    }
}
