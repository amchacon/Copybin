import SwiftUI
import AppKit
import Foundation

// MARK: - Theme
struct CopybinTheme {
    static let headerGradient: AnyShapeStyle = AnyShapeStyle(
        LinearGradient(
            stops: [
                .init(color: Color(hue: 0.95, saturation: 0.15, brightness: 0.9), location: 0.0),
                .init(color: Color(hue: 0.78, saturation: 0.20, brightness: 0.9), location: 0.4),
                .init(color: Color(hue: 0.60, saturation: 0.35, brightness: 0.9), location: 1.0)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    )
    static let cardBG: AnyShapeStyle = AnyShapeStyle(
        Color(.sRGB, red: 0.92, green: 0.94, blue: 0.96, opacity: 0.9)
    )
    static let cardStroke = Color.black.opacity(0.25)
    static let radius: CGFloat = 10
    static let shadow = Color.black.opacity(0.1)
}

extension ClipboardItem.ClipboardType {
    var label: String {
        switch self {
        case .text: return "Text"
        case .url: return "URL"
        case .email: return "Email"
        case .image: return "Image"
        }
    }
}

extension Date {
    var timeAgoString: String {
        let sec = Int(Date().timeIntervalSince(self))
        if sec < 60 { return "now" }
        let min = sec / 60
        if min < 60 { return "\(min)m" }
        let h = min / 60
        if h < 24 { return "\(h)h" }
        let d = h / 24
        return "\(d)d"
    }
}


// MARK: - Modelo de dados para itens do clipboard
struct ClipboardItem: Identifiable, Codable {
    var id = UUID()
    let content: String
    let imageData: Data?
    let timestamp: Date
    let type: ClipboardType
    
    enum ClipboardType: String, Codable, CaseIterable {
        case text = "text"
        case url = "url"
        case email = "email"
        case image = "image"
        
        var icon: String {
            switch self {
            case .text: return "doc.text"
            case .url: return "link"
            case .email: return "envelope"
            case .image: return "photo"
            }
        }
    }
    
    init(content: String) {
        self.content = content
        self.imageData = nil
        self.timestamp = Date()
        
        // Detecta o tipo baseado no conteúdo
        if content.contains("@") && content.contains(".") && !content.contains(" ") {
            self.type = .email
        } else if content.hasPrefix("http") || content.hasPrefix("www.") {
            self.type = .url
        } else {
            self.type = .text
        }
    }
    
    init(imageData: Data) {
        self.content = "Imagem copiada"
        self.imageData = imageData
        self.timestamp = Date()
        self.type = .image
    }
}

// MARK: - Image utils (thumbnail + JPEG)
extension NSImage {
    func resized(maxDimension: CGFloat) -> NSImage? {
        let longer = max(size.width, size.height)
        guard longer > 0 else { return nil }
        let scale = min(1, maxDimension / longer)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let img = NSImage(size: newSize)
        img.lockFocus()
        defer { img.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy, fraction: 1.0)
        return img
    }

    func jpegData(quality: CGFloat = 0.65) -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}

/// Converte Data (tiff/png/etc) -> thumbnail JPEG leve
func thumbnailJPEG(from data: Data,
                   maxDimension: CGFloat = 360,
                   quality: CGFloat = 0.65) -> Data? {
    guard let img = NSImage(data: data),
          let resized = img.resized(maxDimension: maxDimension),
          let jpeg = resized.jpegData(quality: quality) else { return nil }
    return jpeg
}

// MARK: - Gerenciador do Clipboard
class ClipboardManager: ObservableObject {
    @Published var items: [ClipboardItem] = []
    private var lastClipboardContent: Any?
    private var timer: Timer?
    private let maxItems = 100
    
    // Debounce
    private var saveWorkItem: DispatchWorkItem?
    private let saveDelay: TimeInterval = 0.5
    
    init() {
        loadItems()
        startMonitoring()
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.checkClipboard()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        
        // Verifica se há uma imagem
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            if !isDataEqual(imageData, lastClipboardContent as? Data) {
                addImageItem(imageData: imageData)
                return
            }
        }
        
        // Verifica texto
        guard let content = pasteboard.string(forType: .string),
              content != lastClipboardContent as? String,
              !content.isEmpty else { return }
        
        lastClipboardContent = content
        addItem(content: content)
    }
    
    private func isDataEqual(_ data1: Data, _ data2: Data?) -> Bool {
        guard let data2 = data2 else { return false }
        return data1 == data2
    }
    
    func addImageItem(imageData: Data) {
        // Gera thumbnail JPEG leve (descarta o blob grande)
        guard let thumb = thumbnailJPEG(from: imageData) else {
            // fallback: se não conseguir gerar thumb, usa o dado original
            let newItem = ClipboardItem(imageData: imageData)
            items.insert(newItem, at: 0)
            if items.count > maxItems { items = Array(items.prefix(maxItems)) }
            lastClipboardContent = imageData
            scheduleSave()
            return
        }

        let newItem = ClipboardItem(imageData: thumb)

        // Evita duplicatas de imagem muito próximas no tempo
        if let lastItem = items.first,
           lastItem.type == .image,
           Date().timeIntervalSince(lastItem.timestamp) < 1.0 {
            return
        }

        items.insert(newItem, at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }

        lastClipboardContent = imageData // guardamos o último clipboard “original” só para comparação
        scheduleSave()
    }

    
    func addItem(content: String) {
        let newItem = ClipboardItem(content: content)
        
        // Remove duplicatas
        items.removeAll { $0.content == content }
        
        // Adiciona no início
        items.insert(newItem, at: 0)
        
        // Limita o número de itens
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        
        scheduleSave()
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if item.type == .image, let imageData = item.imageData {
            pasteboard.setData(imageData, forType: .tiff)
            lastClipboardContent = imageData
        } else {
            pasteboard.setString(item.content, forType: .string)
            lastClipboardContent = item.content
        }
    }
    
    func deleteItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        scheduleSave()
    }
    
    func clearAll() {
        items.removeAll()
        scheduleSave()
    }
    
    private var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Copybin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clipboard.json")
    }
    
    private func saveItemsNow() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("Fail to save history:", error)
        }
    }

    private func scheduleSave() {
        // cancela tentativa anterior e agenda outra
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveItemsNow()
        }
        saveWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + saveDelay, execute: work)
    }
    
    private func loadItems() {
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            self.items = decoded
            return
        }
    }
}

// MARK: - Card de item
struct ClipboardCard: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Preview: imagem ou ícone
            if item.type == .image, let data = item.imageData, let nsImg = NSImage(data: data) {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.05))
                    Image(systemName: item.type.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                .frame(width: 52, height: 52)
            }

            // Texto + meta
            VStack(alignment: .leading, spacing: 6) {
                if item.type == .image, let data = item.imageData {
                    HStack(spacing: 6) {
                        TypePill(type: item.type)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(item.content)
                        .lineLimit(2)
                        .font(.system(size: 13))
                }

                Text(item.timestamp.timeAgoString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // Ações
            HStack(spacing: 6) {
                Button(action: onCopy) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(CopybinTheme.cardBG, in: RoundedRectangle(cornerRadius: CopybinTheme.radius))
        .overlay(
            RoundedRectangle(cornerRadius: CopybinTheme.radius)
                .stroke(CopybinTheme.cardStroke, lineWidth: 1)
        )
        .shadow(color: CopybinTheme.shadow, radius: 8, x: 0, y: 4)
        .contentShape(Rectangle())
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { inside in isHovering = inside }
    }
}

struct TypePill: View {
    let type: ClipboardItem.ClipboardType
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: type.icon).font(.caption2.bold())
            Text(type.label).font(.caption.bold())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .foregroundStyle(.primary.opacity(0.8))
    }
}


// MARK: - View principal
struct ContentView: View {
    @StateObject private var clipboardManager = ClipboardManager()
    @State private var searchText = ""
    @State private var selectedType: ClipboardItem.ClipboardType? = nil
    @State private var autoMinimize = true
    
    var filteredItems: [ClipboardItem] {
        var items = clipboardManager.items
        
        // Filtro por tipo
        if let selectedType = selectedType {
            items = items.filter { $0.type == selectedType }
        }
        
        // Filtro por busca
        if !searchText.isEmpty {
            items = items.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
        
        return items
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // HEADER
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(CopybinTheme.headerGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 16, weight: .bold))
                            .padding(8)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                        Text("Clipboard History")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                        Spacer(minLength: 8)
                        
                        Toggle("Auto-hide", isOn: $autoMinimize)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .help("Minimize window to tray")
                            .padding(.trailing, 2)
                        
                        Button("Clear All") { clipboardManager.clearAll() }
                            .buttonStyle(.borderedProminent)
                            .tint(.white.opacity(0.25))
                            .foregroundStyle(.white)
                            .controlSize(.small)
                    }
                    HStack(spacing: 8) {
                        
                        // Filtros por tipo
                        HStack {
                            Button(action: { selectedType = nil }) {
                                Text("All")
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 4)
                                    .background(selectedType == nil ? Color.blue : Color.clear)
                                    .foregroundColor(selectedType == nil ? .white : .primary)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            ForEach(ClipboardItem.ClipboardType.allCases, id: \.self) { type in
                                Button(action: { selectedType = type }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: type.icon)
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 4)
                                    .background(selectedType == type ? Color.blue : Color.clear)
                                    .foregroundColor(selectedType == type ? .white : .primary)
                                    .cornerRadius(4)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            // Busca
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.white.opacity(0.8))
                                TextField("Search…", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(.white)
                                    .tint(.white)
                            }
                            .padding(.horizontal, 4).padding(.vertical, 4)
                            .background(.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))

                            
                            Spacer()
                        }
                    }
                }
                .padding(16)
            }
            .frame(height: 100)
            .padding(.horizontal, 4)
            .padding(.top, 4)

            // LISTA / EMPTY STATE
            if filteredItems.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 46))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "No Items" : "No items found")
                        .font(.headline).foregroundStyle(.secondary)
                    if searchText.isEmpty {
                        Text("Copy something with Cmd+C to start!")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 4)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredItems) { item in
                            ClipboardCard(
                                item: item,
                                onCopy: { clipboardManager.copyToClipboard(item) },
                                onDelete: { clipboardManager.deleteItem(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 540)
    }
}

// MARK: - Configuração da janela (adicionar no AppDelegate se necessário)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configurações adicionais se necessário
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
