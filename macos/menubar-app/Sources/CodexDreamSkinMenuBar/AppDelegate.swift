import AppKit
import CryptoKit
import DreamSkinCore
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private enum CommunityRollbackRetention {
    case preserved(URL)
    case retainedInOperationRoot(URL)
    case unavailable

    var requiresOperationRoot: Bool {
      if case .retainedInOperationRoot = self { return true }
      return false
    }
  }

  private let fileManager = FileManager.default
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let menu = NSMenu()
  private var snapshot = StatusSnapshot()
  private var statusRefreshRunning = false
  private var operationInFlight = false
  private var engineInstallInFlight = false
  private var themeRecoveryInFlight = false
  private var pairingInFlight = false
  private var pendingCommunityVersionID: String?
  private var pendingNexoSkin: NexoSkinCatalogEntry?
  private var communityBaselineThemeID = ""
  private var communityStageMessage = ""
  private var engineUpdateMessage = ""
  private var refreshTimer: Timer?
  private var automaticUpdateCheckInFlight = false
  private let automaticUpdateLastCheckKey = "automaticUpdateLastCheck"
  private lazy var communityHTTP = BoundedCommunityHTTPClient(
    userAgent: "CodexDreamSkin/\(appVersion)"
  )
  private let nexoDevice = NexoDeviceClient()
  private let requiredEngineRelativePaths = [
    "VERSION",
    "assets/appearance-bridge.mjs",
    "assets/appearance-settings.mjs",
    "assets/signed-nexo-catalog.mjs",
    "assets/dream-skin.css",
    "assets/nexo-skin-catalog.json",
    "assets/portal-hero.png",
    "assets/renderer-inject.js",
    "assets/safe-css-policy.json",
    "assets/safe-css-validator.mjs",
    "assets/selectors.json",
    "assets/theme-package-validator.mjs",
    "assets/theme.json",
    "presets/preset-gothic-void-crusade/background.jpg",
    "presets/preset-gothic-void-crusade/theme.json",
    "scripts/apply-from-menubar-macos.sh",
    "scripts/apply-community-theme-macos.sh",
    "scripts/check-update-macos.sh",
    "scripts/common-macos.sh",
    "scripts/customize-theme-macos.sh",
    "scripts/doctor-macos.sh",
    "scripts/extract-theme-zip-macos.sh",
    "scripts/image-metadata.mjs",
    "scripts/import-theme-zip-macos.sh",
    "scripts/injector.mjs",
    "scripts/install-dream-skin-macos.sh",
    "scripts/install-update-macos.sh",
    "scripts/load-image-theme-macos.sh",
    "scripts/pause-dream-skin-macos.sh",
    "scripts/publish-theme-import.mjs",
    "scripts/recover-theme-imports-macos.sh",
    "scripts/restore-dream-skin-macos.sh",
    "scripts/snapshot-active-theme-macos.sh",
    "scripts/snapshot-theme-zip.mjs",
    "scripts/stage-theme.mjs",
    "scripts/start-dream-skin-macos.sh",
    "scripts/status-dream-skin-macos.sh",
    "scripts/switch-theme-macos.sh",
    "scripts/theme-content-fingerprint.mjs",
    "scripts/theme-switch-lock-macos.sh",
    "scripts/theme-config.mjs",
    "scripts/validate-safe-css-file.mjs",
    "scripts/verify-dream-skin-macos.sh",
    "scripts/write-theme.mjs"
  ]

  private var homeURL: URL {
    fileManager.homeDirectoryForCurrentUser
  }

  private var installedEngineURL: URL {
    homeURL.appendingPathComponent(".codex/codex-dream-skin-studio", isDirectory: true)
  }

  private var stateRootURL: URL {
    homeURL.appendingPathComponent(
      "Library/Application Support/CodexDreamSkinStudio",
      isDirectory: true
    )
  }

  private var themesURL: URL {
    stateRootURL.appendingPathComponent("themes", isDirectory: true)
  }

  private var imagesURL: URL {
    stateRootURL.appendingPathComponent("images", isDirectory: true)
  }

  private var appearanceSettingsURL: URL {
    stateRootURL.appendingPathComponent("appearance.json", isDirectory: false)
  }

  private var bundledEngineURL: URL? {
    Bundle.main.resourceURL?.appendingPathComponent("engine", isDirectory: true)
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    configureStatusItem()
    ensureUserDirectories()
    cleanupStalePrivateOperationDirectories()
    migrateLegacySwiftBarIfNeeded()
    // 全新安装没有状态脚本，必须立即初始化；已有安装则先读取 Codex
    // 运行状态，避免自动更新后在 Codex 尚未关闭时争用 config.toml。
    if installedScript(named: "status-dream-skin-macos.sh") == nil {
      installBundledEngineIfNeeded(force: false)
    }
    refreshStatus()
    refreshSignedNexoCatalog()
    refreshTimer = Timer.scheduledTimer(
      timeInterval: 10,
      target: self,
      selector: #selector(refreshStatusFromTimer),
      userInfo: nil,
      repeats: true
    )
    scheduleAutomaticUpdateCheck()
  }

  func applicationWillTerminate(_ notification: Notification) {
    refreshTimer?.invalidate()
    communityHTTP.invalidate()
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !operationInFlight, !engineInstallInFlight, !themeRecoveryInFlight, !snapshot.busy else {
      showError(
        title: "操作仍在进行",
        message: "请等待当前下载、导入、应用或恢复完成后再退出，以免留下未完成的主题状态。"
      )
      return .terminateCancel
    }
    return .terminateNow
  }

  private func refreshSignedNexoCatalog(completion: (() -> Void)? = nil) {
    let publicKeys = NexoSkinContract.pinnedCatalogPublicKeys
    guard !publicKeys.isEmpty else { completion?(); return }
    let store = SignedNexoCatalogStore(
      cacheURL: stateRootURL
        .appendingPathComponent("catalog", isDirectory: true)
        .appendingPathComponent("signed-nexo-catalog.json"),
      verifier: SignedNexoCatalogVerifier(publicKeys: publicKeys)
    )
    communityHTTP.get(
      SignedNexoCatalogRemote.endpoint,
      accept: "application/json",
      maximumBytes: SignedNexoCatalogRemote.maximumEnvelopeBytes
    ) { result in
      if case let .success(payload) = result, let responseURL = payload.response.url {
        _ = try? store.installRemoteResponse(
          responseURL: responseURL,
          statusCode: payload.response.statusCode,
          body: payload.body
        )
      }
      if let completion { DispatchQueue.main.async(execute: completion) }
    }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    guard urls.count == 1 else {
      showError(
        title: "一键换肤链接无效",
        message: "一次只能处理一个经过验证的主题链接。"
      )
      return
    }
    let url = urls[0]
    if NexoSkinContract.isCanonicalApplyURL(url) {
      // A deep link waits for the fixed signed endpoint before resolving an
      // embedded ID, so first-run revocations cannot race the startup refresh.
      refreshSignedNexoCatalog { [weak self] in self?.handleOpenURL(url) }
      return
    }
    handleOpenURL(url)
  }

  private func handleOpenURL(_ url: URL) {
    if let entry = NexoSkinContract.entry(from: url) {
      beginNexoSkinApply(entry)
    } else if NexoSkinContract.isRestoreURL(url) {
      beginNexoRestore()
    } else if let versionID = CommunityThemeContract.versionID(from: url) {
      beginCommunityThemeApply(versionID: versionID)
    } else if NexoSkinContract.isCanonicalApplyURL(url) {
      performUpdateCheck(showCurrentVersion: false, triggeredByUnknownSkin: true)
    } else {
      showError(
        title: "一键换肤链接无效",
        message: "只接受 NexoToken 平台签发的主题链接；不会打开链接中的任意网址、文件或命令。"
      )
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    rebuildMenu()
    refreshStatus()
  }

  private func configureStatusItem() {
    menu.delegate = self
    menu.autoenablesItems = false
    statusItem.menu = menu
    guard let button = statusItem.button else { return }
    // Nexo 同心环模板图标：只使用黑色与透明度，自动适配深浅菜单栏。
    let mark = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
      NSColor.black.setStroke()
      let outer = NSBezierPath(ovalIn: rect.insetBy(dx: 1.4, dy: 1.4))
      outer.lineWidth = 1.65
      outer.stroke()
      let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 5.1, dy: 5.1))
      inner.lineWidth = 1.45
      inner.stroke()
      NSColor.black.setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 7.25, dy: 7.25)).fill()
      return true
    }
    mark.isTemplate = true
    mark.accessibilityDescription = "Nexo Codex Skin"
    button.image = mark
    button.toolTip = "Nexo Codex Skin"
    rebuildMenu()
  }

  private func ensureUserDirectories() {
    for directory in [stateRootURL, themesURL, imagesURL] {
      do {
        try fileManager.createDirectory(
          at: directory,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      } catch {
        showError(title: "无法准备用户目录", message: error.localizedDescription)
        break
      }
    }
  }

  private func cleanupStalePrivateOperationDirectories() {
    let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
    let allowedPrefixes = [".community-apply-", ".theme-switch.", ".theme-import-work."]
    let rootPath = stateRootURL.standardizedFileURL.path + "/"
    guard let entries = try? fileManager.contentsOfDirectory(
      at: stateRootURL,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
      options: []
    ) else { return }

    for entry in entries {
      let name = entry.lastPathComponent
      guard name != ".theme-switch.lock",
            allowedPrefixes.contains(where: name.hasPrefix),
            entry.standardizedFileURL.path.hasPrefix(rootPath),
            let values = try? entry.resourceValues(
              forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
            ),
            values.isDirectory == true,
            values.isSymbolicLink != true,
            let modified = values.contentModificationDate,
            modified < cutoff else { continue }
      if name.hasPrefix(".community-apply-"),
         (try? CommunityRecovery.validatedRollbackSnapshot(
           operationRoot: entry,
           stateRoot: stateRootURL,
           fileManager: fileManager
         )) != nil {
        continue
      }
      do {
        try fileManager.removeItem(at: entry)
      } catch {
        NSLog("[DreamSkin] stale private operation cleanup failed for %@: %@", name, error.localizedDescription)
      }
    }
  }

  private func rebuildMenu() {
    menu.removeAllItems()
    let compactStatus: String
    switch snapshot.session {
    case "active": compactStatus = "Nexo Skin · 已开启"
    case "applying": compactStatus = "Nexo Skin · 正在应用"
    case "stale", "unknown": compactStatus = "Nexo Skin · 需要修复"
    default: compactStatus = "Nexo Skin · 已暂停"
    }
    addDisabledItem(compactStatus)
    if !snapshot.appliedThemeName.isEmpty && snapshot.session == "active" {
      addDisabledItem("已应用：\(cleanMenuText(snapshot.appliedThemeName))")
    }
    if !snapshot.themeName.isEmpty && snapshot.themeName != snapshot.appliedThemeName {
      addDisabledItem("已选主题：\(cleanMenuText(snapshot.themeName))（待应用）")
    } else if snapshot.appliedThemeName.isEmpty && !snapshot.themeName.isEmpty {
      addDisabledItem("已选主题：\(cleanMenuText(snapshot.themeName))")
    }
    if !snapshot.operationMessage.isEmpty {
      addDisabledItem(cleanMenuText(snapshot.operationMessage))
    }
    if !communityStageMessage.isEmpty {
      addDisabledItem(cleanMenuText(communityStageMessage))
    }
    if !engineUpdateMessage.isEmpty {
      addDisabledItem(cleanMenuText(engineUpdateMessage))
    }
    addDisabledItem("版本：v\(appVersion)")

    menu.addItem(.separator())
    let busy = operationInFlight || engineInstallInFlight || themeRecoveryInFlight || snapshot.busy
    let applyTitle: String
    switch snapshot.session {
    case "active": applyTitle = "重新应用皮肤"
    case "stale", "unknown": applyTitle = "修复并应用"
    default: applyTitle = "应用皮肤"
    }
    addActionItem(applyTitle, action: #selector(applySkin), enabled: !busy)
    if snapshot.session == "active" || snapshot.session == "applying" {
      addActionItem("暂停皮肤", action: #selector(pauseSkin), enabled: !busy)
    }
    addActionItem("打开 ChatGPT", action: #selector(openCodex), enabled: !busy)
    addActionItem(
      pairingInFlight ? "正在连接 NexoToken…" : "连接 NexoToken 账号…",
      action: #selector(beginNexoPairing),
      enabled: !busy && !pairingInFlight
    )
    addActionItem("检查更新…", action: #selector(checkForUpdates), enabled: !operationInFlight)

    let advancedRoot = NSMenuItem(title: "高级工具", action: nil, keyEquivalent: "")
    let advancedMenu = NSMenu(title: "高级工具")
    advancedMenu.autoenablesItems = false
    addActionItem("外观设置…", action: #selector(configureAppearanceSettings), enabled: !busy, to: advancedMenu)
    addActionItem("更换背景图…", action: #selector(chooseBackgroundImage), enabled: !busy, to: advancedMenu)
    addActionItem("导入主题 ZIP…", action: #selector(chooseThemeArchive), enabled: !busy, to: advancedMenu)
    addSavedThemesMenu(enabled: !busy, to: advancedMenu)
    addActionItem("打开主题文件夹", action: #selector(openThemesFolder), to: advancedMenu)
    addActionItem("打开图片文件夹", action: #selector(openImagesFolder), to: advancedMenu)
    advancedMenu.addItem(.separator())
    let needsEngineInstall = engineNeedsInstall()
    if engineInstallInFlight {
      addDisabledItem("正在安装引擎…", to: advancedMenu)
    } else {
      addActionItem(
        needsEngineInstall ? "安装 / 升级组件…" : "修复 / 重新安装组件…",
        action: #selector(reinstallEngine),
        enabled: !busy,
        to: advancedMenu
      )
    }
    let loginItem = addActionItem("登录时启动", action: #selector(toggleLoginItem), to: advancedMenu)
    loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    if !legacyPluginURLs().isEmpty {
      addActionItem("停用旧菜单组件…", action: #selector(disableLegacySwiftBarFromMenu), to: advancedMenu)
    }
    advancedRoot.submenu = advancedMenu
    menu.addItem(advancedRoot)

    menu.addItem(.separator())
    addActionItem(
      "恢复原状并卸载…",
      action: #selector(restoreAndUninstall),
      enabled: !busy
    )
    addActionItem("退出", action: #selector(quit), enabled: !busy)
  }

  @discardableResult
  private func addActionItem(
    _ title: String,
    action: Selector,
    enabled: Bool = true,
    to destination: NSMenu? = nil
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = enabled
    (destination ?? menu).addItem(item)
    return item
  }

  private func addDisabledItem(_ title: String, to destination: NSMenu? = nil) {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    (destination ?? menu).addItem(item)
  }

  private func addSavedThemesMenu(enabled: Bool, to destination: NSMenu? = nil) {
    let root = NSMenuItem(title: "已保存的主题", action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: "已保存的主题")
    submenu.autoenablesItems = false
    let themes = savedThemes()
    if themes.isEmpty {
      addDisabledItem("还没有保存的主题", to: submenu)
    } else {
      for theme in themes {
        let item = addActionItem(
          theme.name,
          action: #selector(switchSavedTheme(_:)),
          enabled: enabled,
          to: submenu
        )
        item.representedObject = theme.id
        if theme.id == snapshot.themeID {
          item.state = .on
        }
      }
    }
    root.submenu = submenu
    (destination ?? menu).addItem(root)
  }

  private func savedThemes() -> [SavedThemeOption] {
    let entries: [URL]
    do {
      entries = try fileManager.contentsOfDirectory(
        at: themesURL,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      )
    } catch {
      NSLog(
        "[DreamSkin] savedThemes: list %@ failed: %@",
        themesURL.path, String(describing: error)
      )
      return []
    }
    // 包含性判断必须用 canonicalPath：用户记录的 home 大小写可能与磁盘目录
    // 不一致（如 NFSHomeDirectory=/Users/Fei、磁盘实际为 /Users/fei），
    // 字符串前缀比较会把全部主题误拒成 rejected["root"]。
    let canonicalRoot =
      (((try? themesURL.resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath)
        ?? themesURL.standardizedFileURL.path) + "/"
    var rejected: [String: Int] = [:]
    let options: [SavedThemeOption] = entries.compactMap { directory in
      let id = directory.lastPathComponent
      guard id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$"#, options: .regularExpression) != nil else {
        rejected["name", default: 0] += 1
        return nil
      }
      guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
            values.isDirectory == true,
            values.isSymbolicLink != true else {
        rejected["kind", default: 0] += 1
        return nil
      }
      let entryPath =
        ((try? directory.resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath)
          ?? directory.standardizedFileURL.path
      guard entryPath.hasPrefix(canonicalRoot) else {
        rejected["root", default: 0] += 1
        return nil
      }
      let configURL = directory.appendingPathComponent("theme.json")
      guard let data = try? Data(contentsOf: configURL, options: [.mappedIfSafe]),
            data.count <= 1_048_576 else {
        rejected["read", default: 0] += 1
        return nil
      }
      guard let object = try? JSONSerialization.jsonObject(with: data),
            let value = object as? [String: Any] else {
        rejected["json", default: 0] += 1
        return nil
      }
      let rawName = value["name"] as? String ?? id
      return SavedThemeOption(id: id, name: cleanMenuText(rawName))
    }
    let deduplicated = deduplicatedSavedThemes(options, currentThemeID: snapshot.themeID).sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    // 空列表或有拒收时落一条统一日志：`log show --predicate 'process ==
    // "CodexDreamSkinMenuBar"'` 可直接定位是哪一层过滤把主题吃掉了。
    if options.isEmpty || !rejected.isEmpty {
      NSLog(
        "[DreamSkin] savedThemes: %d entries -> %d themes at %@ rejected=%@",
        entries.count, options.count, themesURL.path, String(describing: rejected)
      )
    }
    return deduplicated
  }

  private func cleanMenuText(_ source: String) -> String {
    let filtered = source.unicodeScalars.map { scalar -> Character in
      CharacterSet.controlCharacters.contains(scalar) || scalar == "|" ? " " : Character(scalar)
    }
    let value = String(filtered).trimmingCharacters(in: .whitespacesAndNewlines)
    return String(value.prefix(120))
  }

  @objc private func refreshStatusFromTimer() {
    refreshStatus()
  }

  private func refreshStatus() {
    guard !statusRefreshRunning,
          let script = installedScript(named: "status-dream-skin-macos.sh") else {
      return
    }
    statusRefreshRunning = true
    ScriptRunner.run(script: script, arguments: ["--json", "--current-version", appVersion]) { [weak self] result in
      guard let self else { return }
      self.statusRefreshRunning = false
      if result.succeeded,
         let parsed = StatusSnapshot(jsonData: Data(result.output.utf8)) {
        self.snapshot = parsed
        self.completeDeferredEngineUpdateIfPossible()
        self.statusItem.button?.toolTip = "Nexo Codex Skin · \(parsed.title)"
        self.statusItem.button?.appearsDisabled = parsed.session == "unknown" || parsed.session == "stale"
        self.rebuildMenu()
      }
    }
  }

  @objc private func applySkin() {
    runInstalledScript(named: "apply-from-menubar-macos.sh", operation: "应用皮肤")
  }

  @objc private func pauseSkin() {
    runInstalledScript(named: "pause-dream-skin-macos.sh", operation: "暂停皮肤")
  }

  @objc private func reinstallEngine() {
    guard !operationInFlight, !snapshot.busy else { return }
    installBundledEngineIfNeeded(force: true)
  }

  private func completeDeferredEngineUpdateIfPossible() {
    guard engineNeedsInstall() else {
      engineUpdateMessage = ""
      return
    }
    guard !engineInstallInFlight, !operationInFlight, !themeRecoveryInFlight else { return }
    if snapshot.codexRunning {
      engineUpdateMessage = "更新已就绪，关闭 ChatGPT 后自动完成"
      return
    }
    engineUpdateMessage = ""
    installBundledEngineIfNeeded(force: false)
  }

  @objc private func chooseBackgroundImage() {
    let panel = NSOpenPanel()
    panel.title = "选择 Nexo 皮肤背景图"
    panel.prompt = "选择"
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.png, .jpeg, .webP, .heic, .tiff]
    activateForUserInteraction()
    guard panel.runModal() == .OK, let imageURL = panel.url else { return }
    runInstalledScript(
      named: "load-image-theme-macos.sh",
      arguments: ["--file", imageURL.path],
      operation: "更换背景图"
    )
  }

  @objc private func configureAppearanceSettings() {
    let defaults: [String: Any] = [
      "backgroundVisibility": 1.0, "sidebarOpacity": 0.82, "contentOpacity": 0.82,
      "font": "system", "fontSize": 1.0, "contrast": 1.0,
    ]
    let existing = ((try? Data(contentsOf: appearanceSettingsURL)).flatMap {
      try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
    }) ?? [:]
    let form = NSStackView()
    form.orientation = .vertical
    form.alignment = .leading
    form.spacing = 8
    var fields: [String: NSTextField] = [:]
    for (key, title) in [
      ("backgroundVisibility", "背景显示度 (0.15–1)"),
      ("sidebarOpacity", "侧边栏透明度 (0.2–1)"),
      ("contentOpacity", "内容层透明度 (0.2–1)"),
      ("fontSize", "字体大小 (0.85–1.2)"),
      ("contrast", "文字对比度 (0.7–1)"),
    ] {
      let row = NSStackView(); row.orientation = .horizontal; row.spacing = 10
      row.addArrangedSubview(NSTextField(labelWithString: title))
      let field = NSTextField(string: "\(existing[key] ?? defaults[key]!)")
      field.frame.size.width = 90
      row.addArrangedSubview(field); fields[key] = field; form.addArrangedSubview(row)
    }
    let fontRow = NSStackView(); fontRow.orientation = .horizontal; fontRow.spacing = 10
    fontRow.addArrangedSubview(NSTextField(labelWithString: "字体"))
    let font = NSPopUpButton(); font.addItems(withTitles: ["system", "serif", "rounded", "mono"])
    font.selectItem(withTitle: (existing["font"] as? String) ?? "system")
    fontRow.addArrangedSubview(font); form.addArrangedSubview(fontRow)
    let alert = NSAlert(); alert.messageText = "外观设置"; alert.informativeText = "设置只保存到本机助手，不会写进皮肤链接。"
    alert.accessoryView = form; alert.addButton(withTitle: "保存并应用"); alert.addButton(withTitle: "取消")
    activateForUserInteraction()
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    func number(_ key: String, _ lower: Double, _ upper: Double) -> Double? {
      guard let value = Double(fields[key]?.stringValue ?? ""), value >= lower, value <= upper else { return nil }
      return (value * 100).rounded() / 100
    }
    guard let background = number("backgroundVisibility", 0.15, 1),
          let sidebar = number("sidebarOpacity", 0.2, 1),
          let content = number("contentOpacity", 0.2, 1),
          let size = number("fontSize", 0.85, 1.2),
          let contrast = number("contrast", 0.7, 1),
          let fontName = font.selectedItem?.title else {
      showError(title: "外观设置无效", message: "请填写允许范围内的数值。")
      return
    }
    let value: [String: Any] = ["backgroundVisibility": background, "sidebarOpacity": sidebar,
      "contentOpacity": content, "font": fontName, "fontSize": size, "contrast": contrast]
    do {
      let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
      try data.write(to: appearanceSettingsURL, options: [.atomic])
      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: appearanceSettingsURL.path)
      runInstalledScript(named: "apply-from-menubar-macos.sh", operation: "应用外观设置")
    } catch {
      showError(title: "无法保存外观设置", message: error.localizedDescription)
    }
  }

  @objc private func chooseThemeArchive() {
    let panel = NSOpenPanel()
    panel.title = "选择 Nexo 皮肤主题 ZIP"
    panel.prompt = "导入"
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.zip]
    activateForUserInteraction()
    guard panel.runModal() == .OK, let archiveURL = panel.url else { return }
    importThemeArchive(archiveURL)
  }

  @objc private func beginNexoPairing() {
    guard !pairingInFlight else { return }
    pairingInFlight = true
    rebuildMenu()
    nexoDevice.currentPairingStatus { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        switch result {
        case let .success(status) where status == "active":
          self.pairingInFlight = false
          self.rebuildMenu()
          self.showInfo(title: "账号已连接", message: "此设备已经连接 NexoToken，无需重新连接。")
        case .success:
          self.startNexoPairingChallenge()
        case let .failure(error):
          self.pairingInFlight = false
          self.rebuildMenu()
          self.showError(title: "无法检查连接状态", message: error.localizedDescription)
        }
      }
    }
  }

  private func startNexoPairingChallenge() {
    nexoDevice.startPairing { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        switch result {
        case let .failure(error):
          self.pairingInFlight = false
          self.rebuildMenu()
          self.showError(title: "无法连接账号", message: error.localizedDescription)
        case let .success(challenge):
          let alert = NSAlert()
          alert.messageText = "连接码：\(challenge.code)"
          alert.informativeText = "将在 NexoToken 的 Codex 皮肤页面确认此连接。连接码十分钟后失效；助手不会读取或保存你的登录令牌。"
          alert.addButton(withTitle: "打开 NexoToken")
          alert.addButton(withTitle: "取消")
          self.activateForUserInteraction()
          guard alert.runModal() == .alertFirstButtonReturn else {
            self.pairingInFlight = false
            self.rebuildMenu()
            return
          }
          if let url = URL(string: "https://nexotoken.net/?view=codex-skins") {
            NSWorkspace.shared.open(url)
          }
          self.nexoDevice.waitUntilPaired { [weak self] status in
            DispatchQueue.main.async {
              guard let self else { return }
              self.pairingInFlight = false
              self.rebuildMenu()
              switch status {
              case .success:
                self.showInfo(title: "账号已连接", message: "现在可以从 NexoToken 一键应用已解锁的皮肤。")
              case let .failure(error):
                self.showError(title: "连接未完成", message: error.localizedDescription)
              }
            }
          }
        }
      }
    }
  }

  private func beginNexoSkinApply(_ entry: NexoSkinCatalogEntry) {
    guard !operationInFlight, !snapshot.busy else {
      showError(title: "暂时无法换肤", message: "Dream Skin 正在执行其他操作，请稍后再点一次。")
      return
    }
    if engineInstallInFlight {
      pendingNexoSkin = entry
      return
    }
    if engineNeedsInstall() {
      pendingNexoSkin = entry
      installBundledEngineIfNeeded(force: false)
      return
    }
    guard let loadScript = installedScript(named: "load-image-theme-macos.sh") else {
      showError(title: "引擎尚未安装", message: "请先选择“安装 / 升级引擎”，再使用一键换肤。")
      return
    }

    let alert = NSAlert()
    alert.messageText = "应用“\(entry.name)”？"
    alert.informativeText = "助手会从 Nexo 固定主题目录下载并校验图片。若当前 Codex 没有安全调试连接，继续操作会关闭并重新打开一次 Codex；请先保存未发送的输入。"
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: "应用并允许必要时重启")
    activateForUserInteraction()
    guard alert.runModal() == .alertSecondButtonReturn else { return }

    operationInFlight = true
    updateCommunityStage("正在验证账号与皮肤资格…")
    nexoDevice.verifyEntitlement(skinID: entry.id) { [weak self] entitlement in
      guard let self else { return }
      switch entitlement {
      case let .failure(error):
        DispatchQueue.main.async {
          self.finishThemeOperation()
          self.showError(title: "无法应用此皮肤", message: error.localizedDescription)
        }
      case let .success(authorization):
        DispatchQueue.main.async { self.updateCommunityStage("正在下载并校验“\(entry.name)”…") }
        self.communityHTTP.get(
          entry.imageURL,
          accept: "image/webp,image/*",
          maximumBytes: 10 * 1024 * 1024
        ) { [weak self] result in
          guard let self else { return }
          do {
            guard case let .success(payload) = result,
                  payload.body.count > 0,
                  self.mediaType(of: payload.response).hasPrefix("image/") else {
              throw CommunityThemeContractError.invalidPackageIdentity
            }
            if let expectedHash = entry.backgroundSha256 {
              let actualHash = SHA256.hash(data: payload.body).map { String(format: "%02x", $0) }.joined()
              guard actualHash == expectedHash else {
                throw CommunityThemeContractError.invalidPackageIdentity
              }
            }
            let root = self.stateRootURL.appendingPathComponent(
              ".nexo-apply-\(UUID().uuidString)",
              isDirectory: true
            )
            try self.fileManager.createDirectory(
              at: root,
              withIntermediateDirectories: false,
              attributes: [.posixPermissions: 0o700]
            )
            let imageURL = root.appendingPathComponent("background.webp")
            try payload.body.write(to: imageURL, options: [.atomic])
            try self.fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: imageURL.path)
            DispatchQueue.main.async {
              self.updateCommunityStage("主题已下载，正在应用并验证…")
              ScriptRunner.run(
                script: loadScript,
                arguments: [
                  "--file", imageURL.path,
                  "--name", entry.name,
                  "--theme-id", entry.id,
                  "--appearance", entry.appearance,
                  "--task-mode", entry.taskMode,
                  "--accent-rgb", entry.visual.accentRGB,
                  "--secondary-rgb", entry.visual.secondaryRGB,
                  "--panel-rgb", entry.visual.panelRGB,
                  "--glow-strength", String(entry.visual.glowStrength),
                  "--signature", entry.visual.signature,
                  "--focus-x", String(entry.visual.focusX),
                  "--focus-y", String(entry.visual.focusY),
                  "--layout-variant", entry.visual.layoutVariant,
                  "--surface-style", entry.visual.surfaceStyle,
                  "--corner-style", entry.visual.cornerStyle,
                  "--motion-preset", entry.visual.motionPreset,
                  "--sidebar-style", entry.visual.sidebarStyle,
                  "--composer-style", entry.visual.composerStyle,
                  "--texture-style", entry.visual.textureStyle,
                ]
              ) { [weak self] scriptResult in
                guard let self else { return }
                try? self.fileManager.removeItem(at: root)
                self.finishThemeOperation()
                if scriptResult.succeeded {
                  self.nexoDevice.reportOutcome(
                    requestID: authorization.requestID,
                    status: .succeeded
                  ) { _ in }
                  self.showInfo(title: "主题已应用", message: "“\(entry.name)”已通过下载、主题生成和可见渲染验证。")
                } else {
                  self.nexoDevice.reportOutcome(
                    requestID: authorization.requestID,
                    status: .failed,
                    failureCode: "RENDER_VERIFICATION_FAILED"
                  ) { _ in }
                  self.showError(
                    title: "主题应用失败",
                    message: self.conciseOutput(scriptResult.output, fallback: "目标主题没有通过可见渲染验证，未报告成功。")
                  )
                }
              }
            }
          } catch {
            self.nexoDevice.reportOutcome(
              requestID: authorization.requestID,
              status: .failed,
              failureCode: "SKIN_ASSET_UNAVAILABLE"
            ) { _ in }
            DispatchQueue.main.async {
              self.finishThemeOperation()
              self.showError(title: "主题下载失败", message: "固定主题图片未通过来源、大小或格式校验。")
            }
          }
        }
      }
    }
  }

  private func beginNexoRestore() {
    guard !operationInFlight, !snapshot.busy else {
      showError(title: "暂时无法恢复", message: "Dream Skin 正在执行其他操作，请稍后再点一次。")
      return
    }
    guard let script = installedScript(named: "restore-dream-skin-macos.sh") else {
      showError(title: "引擎尚未安装", message: "本机还没有可用的 Dream Skin 引擎。")
      return
    }
    let alert = NSAlert()
    alert.messageText = "恢复 Codex 官方外观？"
    alert.informativeText = "将移除当前皮肤并恢复官方外观。必要时 Codex 只会重启一次。"
    alert.addButton(withTitle: "恢复官方外观")
    alert.addButton(withTitle: "取消")
    activateForUserInteraction()
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    operationInFlight = true
    rebuildMenu()
    ScriptRunner.run(
      script: script,
      arguments: ["--restore-base-theme", "--restart-codex"]
    ) { [weak self] result in
      guard let self else { return }
      self.operationInFlight = false
      self.refreshStatus()
      self.rebuildMenu()
      if result.succeeded {
        self.showInfo(title: "已恢复官方外观", message: "当前皮肤已移除。")
      } else {
        self.showError(
          title: "恢复未完成",
          message: self.conciseOutput(result.output, fallback: "官方外观未通过恢复验证，请稍后重试。")
        )
      }
    }
  }

  private func beginCommunityThemeApply(versionID: String) {
    guard !operationInFlight, !snapshot.busy else {
      showError(title: "暂时无法换肤", message: "Dream Skin 正在执行其他操作，请稍后再点一次。")
      return
    }
    if engineInstallInFlight {
      pendingCommunityVersionID = versionID
      return
    }
    if engineNeedsInstall() {
      pendingCommunityVersionID = versionID
      installBundledEngineIfNeeded(force: false)
      return
    }
    guard let metadataURL = CommunityThemeContract.metadataURL(for: versionID) else {
      showError(title: "一键换肤链接无效", message: "主题版本标识不符合安全规则。")
      return
    }
    guard let statusScript = installedScript(named: "status-dream-skin-macos.sh") else {
      showError(title: "引擎尚未安装", message: "请先选择“安装 / 升级引擎”，再使用一键换肤。")
      return
    }

    operationInFlight = true
    updateCommunityStage("正在确认当前皮肤可安全回滚…")
    ScriptRunner.run(script: statusScript, arguments: ["--json", "--deep"]) { [weak self] result in
      guard let self else { return }
      guard result.succeeded,
            let current = StatusSnapshot(jsonData: Data(result.output.utf8)),
            current.isReadyForCommunityApply else {
        self.finishThemeOperation()
        self.showError(
          title: "当前皮肤还不能安全换肤",
          message: "请先从菜单栏应用当前皮肤，确认状态为 Skin ON 且没有“待应用”主题，再回到网页重试。这样失败时才能恢复并验证点击前真正显示的主题。"
        )
        return
      }
      self.communityBaselineThemeID = current.themeID
      self.fetchCommunityThemeMetadata(versionID: versionID, metadataURL: metadataURL)
    }
  }

  private func fetchCommunityThemeMetadata(versionID: String, metadataURL: URL) {
    updateCommunityStage("正在读取已审核主题信息…")
    communityHTTP.get(
      metadataURL,
      accept: "application/json",
      maximumBytes: 65_536
    ) { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        guard case let .success(payload) = result,
              self.mediaType(of: payload.response) == "application/json",
              !payload.body.isEmpty else {
          self.finishThemeOperation()
          self.showError(
            title: "无法读取主题信息",
            message: "主题服务没有返回可验证的授权主题，请稍后重试。"
          )
          return
        }
        do {
          let decoded = try JSONDecoder().decode(CommunityThemeMetadata.self, from: payload.body)
          let metadata = try decoded.validated(expectedVersionID: versionID)
          self.confirmCommunityThemeApply(metadata)
        } catch {
          self.finishThemeOperation()
          self.showError(
            title: "主题信息未通过校验",
            message: error.localizedDescription
          )
        }
      }
    }
  }

  private func confirmCommunityThemeApply(_ metadata: CommunityThemeMetadata) {
    updateCommunityStage("等待确认：\(cleanMenuText(metadata.name))")
    let size = ByteCountFormatter.string(fromByteCount: metadata.packageBytes, countStyle: .file)
    let alert = NSAlert()
    alert.messageText = "从 NexoToken 应用“\(cleanMenuText(metadata.name))”？"
    alert.informativeText = """
    作者：\(cleanMenuText(metadata.authorDisplayName))
    版本：\(metadata.version) · \(size)
    SHA-256：\(metadata.packageSha256)

    客户端会从固定官方 API 下载，核对完整哈希，并重新执行 ZIP、清单与 Safe CSS 校验。导入和应用前不会运行主题中的任意命令。

    如果 ChatGPT 当前没有安全调试连接，应用时会重启 ChatGPT；请先保存未发送的输入。
    """
    alert.addButton(withTitle: "下载并应用")
    alert.addButton(withTitle: "取消")
    activateForUserInteraction()
    guard alert.runModal() == .alertFirstButtonReturn else {
      finishThemeOperation()
      return
    }
    downloadCommunityTheme(metadata)
  }

  private func downloadCommunityTheme(_ metadata: CommunityThemeMetadata) {
    guard let downloadURL = CommunityThemeContract.downloadURL(for: metadata.id) else {
      finishThemeOperation()
      showError(title: "无法下载主题", message: "主题下载地址无法由版本标识安全构造。")
      return
    }
    updateCommunityStage("正在下载主题包…")
    communityHTTP.get(
      downloadURL,
      accept: "application/zip",
      maximumBytes: Int(metadata.packageBytes)
    ) { [weak self] result in
      guard let self else { return }
      var downloadRoot: URL?
      do {
        guard case let .success(payload) = result,
              self.mediaType(of: payload.response) == "application/zip",
              payload.response.expectedContentLength < 0
                || payload.response.expectedContentLength == metadata.packageBytes,
              payload.body.count == Int(metadata.packageBytes) else {
          throw CommunityThemeContractError.invalidPackageIdentity
        }

        let root = self.stateRootURL.appendingPathComponent(
          ".community-apply-\(UUID().uuidString)",
          isDirectory: true
        )
        downloadRoot = root
        try self.fileManager.createDirectory(
          at: root,
          withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o700]
        )
        let archiveURL = root.appendingPathComponent("theme.zip")
        guard self.fileManager.createFile(
          atPath: archiveURL.path,
          contents: payload.body,
          attributes: [.posixPermissions: 0o600]
        ) else {
          throw CommunityThemeContractError.invalidPackageIdentity
        }
        try self.fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archiveURL.path)
        let actualHash = try self.sha256(of: archiveURL)
        guard actualHash == metadata.packageSha256 else {
          throw CommunityThemeContractError.invalidPackageIdentity
        }
        DispatchQueue.main.async {
          self.updateCommunityStage("下载完成，正在执行严格导入校验…")
          self.performThemeImport(
            archiveURL,
            cleanupRoot: root,
            applyAfterImport: true,
            communityMetadata: metadata
          )
        }
      } catch {
        if let downloadRoot {
          try? self.fileManager.removeItem(at: downloadRoot)
        }
        DispatchQueue.main.async {
          self.finishThemeOperation()
          self.showError(
            title: "主题包未通过下载校验",
            message: "下载已丢弃，没有导入或应用任何内容。\n\n\(error.localizedDescription)"
          )
        }
      }
    }
  }

  private func mediaType(of response: HTTPURLResponse) -> String {
    guard let value = response.value(forHTTPHeaderField: "Content-Type") else { return "" }
    return value.split(separator: ";", maxSplits: 1)[0]
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  private func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while true {
      let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
      if data.isEmpty { break }
      digest.update(data: data)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func importThemeArchive(_ archiveURL: URL) {
    guard !operationInFlight, !snapshot.busy else { return }
    operationInFlight = true
    rebuildMenu()
    performThemeImport(archiveURL)
  }

  private func performThemeImport(
    _ archiveURL: URL,
    cleanupRoot: URL? = nil,
    applyAfterImport: Bool = false,
    communityMetadata: CommunityThemeMetadata? = nil
  ) {
    guard let script = installedScript(named: "import-theme-zip-macos.sh") else {
      finishThemeOperation(cleanupRoot: cleanupRoot)
      showError(title: "引擎尚未安装", message: "请先选择“安装 / 升级引擎”，再导入主题。")
      return
    }
    var importArguments = ["--file", archiveURL.path]
    if let communityMetadata {
      importArguments += [
        "--expected-sha256", communityMetadata.packageSha256,
        "--expected-bytes", String(communityMetadata.packageBytes)
      ]
    }
    ScriptRunner.run(script: script, arguments: importArguments) { [weak self] result in
      guard let self else { return }
      guard result.succeeded,
            let data = result.output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let value = object as? [String: Any],
            let status = value["status"] as? String,
            let rawName = value["name"] as? String,
            let rawID = value["id"] as? String else {
        self.finishThemeOperation(cleanupRoot: cleanupRoot)
        self.showError(
          title: "导入主题失败",
          message: self.conciseOutput(result.output, fallback: "主题 ZIP 未通过安全或内容校验。")
        )
        return
      }
      let name = self.cleanMenuText(rawName)
      let id = self.cleanMenuText(rawID)
      let safeCssStatus = value["safeCssStatus"] as? String ?? "none"
      let signatureIgnored = value["signatureIgnored"] as? Bool ?? false
      let cleanupWarning = !(value["cleanupWarning"] as? String ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      if applyAfterImport {
        guard (status == "imported" || status == "duplicate"),
              safeCssStatus == "validated",
              let contentFingerprint = value["contentFingerprint"] as? String,
              contentFingerprint.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
              ) != nil else {
          self.finishThemeOperation(cleanupRoot: cleanupRoot)
          self.showError(
            title: "主题已下载，但没有应用",
            message: "主题包没有完成严格 ZIP 与 Safe CSS 导入校验。"
          )
          return
        }
        self.captureActiveThemeThenApplyImported(
          id: id,
          name: name,
          expectedContentFingerprint: contentFingerprint,
          cleanupRoot: cleanupRoot,
          metadata: communityMetadata,
          cleanupWarning: cleanupWarning
        )
        return
      }
      if status == "duplicate" {
        var details = "“\(name)”与已保存主题完全相同，没有重复写入。"
        if safeCssStatus == "validated" {
          details += "\n包内 theme.css 已通过本机 Safe CSS 校验，切换到该主题时会一并生效。"
        }
        if signatureIgnored {
          details += "\n包内 manifest.sig 是预留文件，当前版本已忽略。"
        }
        self.finishThemeOperation(cleanupRoot: cleanupRoot)
        self.showInfo(
          title: "主题已经存在",
          message: details
        )
        return
      }
      let renamed = value["renamed"] as? Bool ?? false
      let replaced = value["replaced"] as? Bool ?? false
      let nameCollision = value["nameCollision"] as? Bool ?? false
      var details = replaced
        ? "已更新“\(name)”的已保存版本，当前正在使用的主题没有改变。"
        : "已把“\(name)”加入“已保存的主题”，当前正在使用的主题没有改变。"
      if renamed {
        details += "\n为避免覆盖同 ID 主题，已使用新标识：\(id)。"
      }
      if nameCollision {
        details += "\n主题库中已有同名主题，可在菜单中按需要选择。"
      }
      if safeCssStatus == "validated" {
        details += "\ntheme.css 已通过本机 Safe CSS 校验，切换到该主题时会一并生效。"
      }
      if signatureIgnored {
        details += "\n包内 manifest.sig 是预留文件，当前版本已忽略。"
      }
      if cleanupWarning {
        details += "\n主题已成功保存，但旧备份目录未能自动清理；新主题不会因此回滚。请稍后重启客户端并查看日志。"
      }
      self.finishThemeOperation(cleanupRoot: cleanupRoot)
      self.showInfo(title: "主题导入完成", message: details)
    }
  }

  private func captureActiveThemeThenApplyImported(
    id: String,
    name: String,
    expectedContentFingerprint: String,
    cleanupRoot: URL?,
    metadata: CommunityThemeMetadata?,
    cleanupWarning: Bool
  ) {
    guard CommunityThemeContract.isVersionID(metadata?.id ?? ""),
          id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$"#, options: .regularExpression) != nil,
          expectedContentFingerprint.range(
            of: #"^[0-9a-f]{64}$"#,
            options: .regularExpression
          ) != nil,
          let cleanupRoot,
          !communityBaselineThemeID.isEmpty,
          let transactionScript = installedScript(named: "apply-community-theme-macos.sh") else {
      finishThemeOperation(cleanupRoot: cleanupRoot)
      showError(
        title: "主题已导入，但没有应用",
        message: "客户端无法启动带回滚保护的一键换肤事务。当前主题没有改变。"
      )
      return
    }
    reactivateCodexBeforeTransaction()
    updateCommunityStage("正在保存当前主题、应用新主题并验证渲染…")
    ScriptRunner.run(
      script: transactionScript,
      arguments: [
        "--id", id,
        "--expect-fingerprint", expectedContentFingerprint,
        "--expect-active-id", communityBaselineThemeID,
        "--transaction-root", cleanupRoot.path
      ]
    ) { [weak self] result in
      guard let self else { return }
      let rollbackRetention = !result.succeeded && result.exitCode != 20
        ? self.preserveCommunityRollbackSnapshot(from: cleanupRoot)
        : .unavailable
      self.finishThemeOperation(
        cleanupRoot: rollbackRetention.requiresOperationRoot ? nil : cleanupRoot
      )
      if result.succeeded {
        var details = "“\(name)”已通过下载、SHA-256、主题包、Safe CSS 和可见渲染校验，并已切换到客户端。"
        if cleanupWarning {
          details += "\n\n主题已成功应用，但旧备份目录未能自动清理；新主题不会因此回滚。请稍后重启客户端并查看日志。"
        }
        self.showInfo(
          title: "主题已应用",
          message: details
        )
      } else if result.exitCode == 20 {
        self.showError(
          title: "新主题应用失败，原主题已恢复",
          message: "换肤前的精确主题快照已重新应用，并通过可见渲染验证。\n\n\(self.conciseOutput(result.output, fallback: "新主题仍保存在主题库中。"))"
        )
      } else {
        var details = self.conciseOutput(
          result.output,
          fallback: "请从已保存主题中重新选择一个主题。"
        )
        let title: String
        switch rollbackRetention {
        case let .preserved(recoveryURL):
          title = "自动恢复未完成，原主题快照已保留"
          details += "\n\n换肤前的精确主题快照已移入私有恢复目录：\n\(recoveryURL.path)\n该快照尚未通过恢复验证，请不要把“已保留”理解为已经恢复。"
        case let .retainedInOperationRoot(snapshotURL):
          title = "自动恢复未完成，快照仍在事务目录"
          details += "\n\n客户端无法把快照提升到 recovery 目录，但已停止清理原事务目录，并检测到快照仍位于：\n\(snapshotURL.path)\n该快照尚未通过恢复验证，请不要继续切换主题。"
        case .unavailable:
          title = "主题已导入，但应用状态未确认"
          details += "\n\n客户端没有确认到可保留的换肤前快照，不能承诺可自动恢复。请不要继续切换主题，并查看 Dream Skin 日志。"
        }
        self.showError(
          title: title,
          message: "当前可见主题状态未能确认。\n\n\(details)"
        )
      }
    }
  }

  private func preserveCommunityRollbackSnapshot(from operationRoot: URL) -> CommunityRollbackRetention {
    do {
      return .preserved(
        try CommunityRecovery.preserveRollbackSnapshot(
          operationRoot: operationRoot,
          stateRoot: stateRootURL,
          fileManager: fileManager
        )
      )
    } catch {
      NSLog("[DreamSkin] rollback snapshot retention failed: %@", error.localizedDescription)
      if let snapshot = try? CommunityRecovery.validatedRollbackSnapshot(
        operationRoot: operationRoot,
        stateRoot: stateRootURL,
        fileManager: fileManager
      ) {
        return .retainedInOperationRoot(snapshot)
      }
      return .unavailable
    }
  }

  private func finishThemeOperation(cleanupRoot: URL? = nil) {
    if let cleanupRoot { try? fileManager.removeItem(at: cleanupRoot) }
    communityBaselineThemeID = ""
    communityStageMessage = ""
    operationInFlight = false
    refreshStatus()
    rebuildMenu()
  }

  private func updateCommunityStage(_ message: String) {
    communityStageMessage = message
    rebuildMenu()
  }

  @objc private func switchSavedTheme(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String,
          id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$"#, options: .regularExpression) != nil else {
      showError(title: "主题无效", message: "主题标识不符合安全规则。")
      return
    }
    runInstalledScript(
      named: "switch-theme-macos.sh",
      arguments: ["--id", id],
      operation: "切换主题"
    )
  }

  @objc private func openImagesFolder() {
    ensureUserDirectories()
    NSWorkspace.shared.open(imagesURL)
  }

  @objc private func openThemesFolder() {
    ensureUserDirectories()
    NSWorkspace.shared.open(themesURL)
  }

  @objc private func openCodex() {
    // A normal NSWorkspace launch drops the loopback CDP arguments, so the
    // fresh Codex process cannot receive the saved skin. Use the same audited
    // launch path as “应用皮肤”; it asks before any necessary restart.
    runInstalledScript(named: "apply-from-menubar-macos.sh", operation: "打开并应用皮肤")
  }

  @objc private func checkForUpdates() {
    performUpdateCheck(showCurrentVersion: true, triggeredByUnknownSkin: false)
  }

  private func scheduleAutomaticUpdateCheck() {
    let defaults = UserDefaults.standard
    if let lastCheck = defaults.object(forKey: automaticUpdateLastCheckKey) as? Date,
       Date().timeIntervalSince(lastCheck) < 24 * 60 * 60 {
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      self?.performUpdateCheck(showCurrentVersion: false, triggeredByUnknownSkin: false)
    }
  }

  private func performUpdateCheck(showCurrentVersion: Bool, triggeredByUnknownSkin: Bool) {
    guard !operationInFlight, !automaticUpdateCheckInFlight,
          let script = installedScript(named: "check-update-macos.sh")
            ?? bundledScript(named: "check-update-macos.sh") else {
      if showCurrentVersion || triggeredByUnknownSkin {
        showError(title: "无法检查更新", message: "更新检查脚本缺失，请重新安装应用。")
      }
      return
    }
    automaticUpdateCheckInFlight = true
    rebuildMenu()
    ScriptRunner.run(script: script, arguments: ["--json"]) { [weak self] result in
      guard let self else { return }
      self.automaticUpdateCheckInFlight = false
      self.rebuildMenu()
      guard result.succeeded,
            let data = result.output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let value = object as? [String: Any],
            let current = value["currentVersion"] as? String,
            let latest = value["latestVersion"] as? String,
            let latestNumber = value["latestVersionNumber"] as? String,
            let available = value["updateAvailable"] as? Bool else {
        if showCurrentVersion || triggeredByUnknownSkin {
          self.showError(
            title: "检查更新失败",
            message: self.conciseOutput(result.output, fallback: "无法连接更新服务，请稍后重试。")
          )
        }
        return
      }
      UserDefaults.standard.set(Date(), forKey: self.automaticUpdateLastCheckKey)
      if available {
        var releaseNotes = ""
        if let encoded = value["releaseNotesBase64"] as? String,
           let decoded = Data(base64Encoded: encoded),
           let text = String(data: decoded, encoding: .utf8) {
          releaseNotes = text.unicodeScalars
            .filter { $0.value == 9 || $0.value == 10 || $0.value >= 32 }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let alert = NSAlert()
        alert.messageText = "发现新版本 \(latest)"
        let updateContext = triggeredByUnknownSkin
          ? "当前助手版本过旧，无法识别这个新皮肤。更新完成后请再次点击一键应用。"
          : "当前版本为 \(current)。助手会立即更新；换肤组件会在你自然关闭 Codex 后自动升级，不会强制关闭或重启 Codex。"
        alert.informativeText = releaseNotes.isEmpty
          ? updateContext
          : "\(updateContext)\n\n更新说明\n\(String(releaseNotes.prefix(1200)))"
        alert.addButton(withTitle: "立即更新")
        alert.addButton(withTitle: "稍后")
        self.activateForUserInteraction()
        if alert.runModal() == .alertFirstButtonReturn {
          self.launchVerifiedUpdate(version: latestNumber)
        }
      } else if triggeredByUnknownSkin {
        self.showError(title: "暂不支持这个皮肤", message: "客户端已是最新版本，但该皮肤不在已审核目录中。")
      } else if showCurrentVersion {
        self.showInfo(title: "已是最新版本", message: "当前安装的是 \(current)。")
      }
    }
  }

  private func launchVerifiedUpdate(version: String) {
    guard let script = bundledScript(named: "install-update-macos.sh")
            ?? installedScript(named: "install-update-macos.sh") else {
      showError(title: "无法安装更新", message: "自动更新组件缺失，请重新安装应用。")
      return
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [
      script.path,
      "--version", version,
      "--target-app", Bundle.main.bundleURL.path,
      "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      operationInFlight = false
      automaticUpdateCheckInFlight = false
      NSApp.terminate(nil)
    } catch {
      showError(title: "无法启动更新", message: error.localizedDescription)
    }
  }

  @objc private func toggleLoginItem() {
    do {
      if SMAppService.mainApp.status == .enabled {
        try SMAppService.mainApp.unregister()
      } else {
        try SMAppService.mainApp.register()
      }
      rebuildMenu()
      if SMAppService.mainApp.status == .requiresApproval {
        showInfo(
          title: "需要系统确认",
          message: "请在“系统设置 → 通用 → 登录项”中允许 Nexo Codex Skin。"
        )
      }
    } catch {
      showError(
        title: "无法修改登录启动",
        message: "请先把 App 拖到“应用程序”文件夹，再重试。\n\n\(error.localizedDescription)"
      )
    }
  }

  @objc private func disableLegacySwiftBarFromMenu() {
    disableLegacySwiftBarPlugins(confirmFirst: true)
  }

  @objc private func restoreAndUninstall() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "恢复原状并卸载 Dream Skin？"
    alert.informativeText = "将停止皮肤、恢复 ChatGPT 外观、删除本地引擎并关闭本应用。你的图片和已保存主题会保留。"
    alert.addButton(withTitle: "恢复并卸载")
    alert.addButton(withTitle: "取消")
    activateForUserInteraction()
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    let script = installedScript(named: "restore-dream-skin-macos.sh")
      ?? bundledScript(named: "restore-dream-skin-macos.sh")
    guard let script else {
      showError(title: "无法恢复", message: "恢复脚本缺失；没有删除任何文件。")
      return
    }
    operationInFlight = true
    rebuildMenu()
    ScriptRunner.run(
      script: script,
      arguments: ["--restore-base-theme", "--restart-codex", "--uninstall"]
    ) { [weak self] result in
      guard let self else { return }
      self.operationInFlight = false
      guard result.succeeded else {
        self.rebuildMenu()
        self.showError(
          title: "恢复未完成",
          message: self.conciseOutput(result.output, fallback: "引擎和设置均已保留，请处理错误后重试。")
        )
        return
      }
      do {
        if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
          try SMAppService.mainApp.unregister()
        }
        if self.fileManager.fileExists(atPath: self.installedEngineURL.path) {
          try self.fileManager.removeItem(at: self.installedEngineURL)
        }
      } catch {
        self.rebuildMenu()
        self.showError(
          title: "恢复完成，但清理失败",
          message: "ChatGPT 已恢复，部分安装文件未能删除：\n\n\(error.localizedDescription)"
        )
        return
      }
      self.showInfo(
        title: "恢复完成",
        message: "本地组件和登录启动已移除。最后请把当前助手 App 移到废纸篓。"
      )
      NSApp.terminate(nil)
    }
  }

  @objc private func quit() {
    guard !operationInFlight, !engineInstallInFlight, !snapshot.busy else {
      showError(title: "操作仍在进行", message: "请等待当前操作完成后再退出。")
      return
    }
    NSApp.terminate(nil)
  }

  private func runInstalledScript(
    named name: String,
    arguments: [String] = [],
    operation: String
  ) {
    guard !operationInFlight else { return }
    guard let script = installedScript(named: name) else {
      showError(title: "引擎尚未安装", message: "请先选择“安装 / 升级引擎”，再重试。")
      return
    }
    operationInFlight = true
    rebuildMenu()
    ScriptRunner.run(script: script, arguments: arguments) { [weak self] result in
      guard let self else { return }
      self.operationInFlight = false
      self.refreshStatus()
      self.rebuildMenu()
      if !result.succeeded {
        self.showError(
          title: "\(operation)失败",
          message: self.conciseOutput(result.output, fallback: "请检查 ChatGPT 是否已安装，并重试。")
        )
      }
    }
  }

  private func installBundledEngineIfNeeded(force: Bool) {
    guard !engineInstallInFlight, !operationInFlight, !themeRecoveryInFlight, !snapshot.busy else { return }
    if !force && !engineNeedsInstall() {
      recoverInterruptedThemeImports { [weak self] recovered in
        guard let self else { return }
      if recovered {
        self.resumePendingCommunityApply()
      } else {
        self.pendingCommunityVersionID = nil
        self.pendingNexoSkin = nil
      }
      }
      return
    }
    guard let bundledVersion = version(at: bundledEngineURL?.appendingPathComponent("VERSION")) else {
      pendingCommunityVersionID = nil
      pendingNexoSkin = nil
      showError(title: "安装资源损坏", message: "App 内的版本信息无效，请重新下载。")
      return
    }
    if let installedVersion = version(at: installedEngineURL.appendingPathComponent("VERSION")),
       installedVersion > bundledVersion {
      pendingCommunityVersionID = nil
      pendingNexoSkin = nil
      showError(
        title: "已安装更新版本",
        message: "本机引擎 v\(installedVersion) 比当前 App 的 v\(bundledVersion) 更新。请下载相同或更新版本的 DMG，不会执行降级。"
      )
      return
    }
    guard let script = bundledScript(named: "install-dream-skin-macos.sh") else {
      pendingCommunityVersionID = nil
      pendingNexoSkin = nil
      showError(title: "安装资源损坏", message: "App 内没有找到 Dream Skin 引擎。请重新下载。")
      return
    }
    engineInstallInFlight = true
    rebuildMenu()
    ScriptRunner.run(
      script: script,
      arguments: ["--no-launchers", "--no-launch"]
    ) { [weak self] result in
      guard let self else { return }
      self.engineInstallInFlight = false
      self.rebuildMenu()
      if result.succeeded {
        self.refreshStatus()
        self.recoverInterruptedThemeImports { [weak self] recovered in
          guard let self else { return }
          if recovered {
            self.resumePendingCommunityApply()
          } else {
            self.pendingCommunityVersionID = nil
            self.pendingNexoSkin = nil
          }
        }
      } else {
        self.pendingCommunityVersionID = nil
        self.pendingNexoSkin = nil
        self.showError(
          title: "引擎安装未完成",
          message: self.conciseOutput(
            result.output,
            fallback: "安装脚本返回了错误，请重试；如果问题持续，请查看 Dream Skin 日志。"
          )
        )
      }
    }
  }

  private func recoverInterruptedThemeImports(completion: ((Bool) -> Void)? = nil) {
    guard !themeRecoveryInFlight else {
      completion?(false)
      return
    }
    guard let script = installedScript(named: "recover-theme-imports-macos.sh") else {
      showError(
        title: "主题恢复组件缺失",
        message: "本地引擎不完整，未继续待执行的换肤操作。请先选择“修复 / 重新安装引擎…”。"
      )
      completion?(false)
      return
    }
    themeRecoveryInFlight = true
    rebuildMenu()
    ScriptRunner.run(script: script) { [weak self] result in
      guard let self else { return }
      self.themeRecoveryInFlight = false
      if !result.succeeded {
        NSLog(
          "[DreamSkin] interrupted theme import recovery failed: %@",
          self.conciseOutput(result.output, fallback: "unknown recovery failure")
        )
        self.showError(
          title: "主题恢复未完成",
          message: "已保留恢复记录，未继续待执行的换肤操作。请先选择“修复 / 重新安装引擎…”；如果仍失败，请附上日志反馈。"
        )
      }
      self.rebuildMenu()
      completion?(result.succeeded)
    }
  }

  private func resumePendingCommunityApply() {
    if let entry = pendingNexoSkin {
      pendingNexoSkin = nil
      DispatchQueue.main.async { [weak self] in
        self?.beginNexoSkinApply(entry)
      }
      return
    }
    guard let versionID = pendingCommunityVersionID else { return }
    pendingCommunityVersionID = nil
    DispatchQueue.main.async { [weak self] in
      self?.beginCommunityThemeApply(versionID: versionID)
    }
  }

  private func engineNeedsInstall() -> Bool {
    guard let bundled = version(at: bundledEngineURL?.appendingPathComponent("VERSION")) else {
      return true
    }
    guard let installed = version(at: installedEngineURL.appendingPathComponent("VERSION")),
          installed >= bundled else {
      return true
    }
    for relativePath in requiredEngineRelativePaths {
      let url = installedEngineURL.appendingPathComponent(relativePath)
      guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
            values.isRegularFile == true,
            values.isSymbolicLink != true else {
        return true
      }
      if relativePath.hasSuffix(".sh") && !fileManager.isExecutableFile(atPath: url.path) {
        return true
      }
    }
    return false
  }

  private func version(at url: URL?) -> SemanticVersion? {
    guard let url,
          let text = try? String(contentsOf: url, encoding: .utf8) else {
      return nil
    }
    return SemanticVersion(text)
  }

  private func installedScript(named name: String) -> URL? {
    let url = installedEngineURL.appendingPathComponent("scripts/\(name)")
    return fileManager.isExecutableFile(atPath: url.path) ? url : nil
  }

  private func bundledScript(named name: String) -> URL? {
    guard let root = bundledEngineURL else { return nil }
    let url = root.appendingPathComponent("scripts/\(name)")
    return fileManager.fileExists(atPath: url.path) ? url : nil
  }

  private func migrateLegacySwiftBarIfNeeded() {
    let defaults = UserDefaults.standard
    let promptKey = "legacySwiftBarMigrationPrompted"
    guard !defaults.bool(forKey: promptKey), !legacyPluginURLs().isEmpty else { return }
    defaults.set(true, forKey: promptKey)
    disableLegacySwiftBarPlugins(confirmFirst: true)
  }

  private func legacyPluginURLs() -> [URL] {
    var candidates = [
      stateRootURL.appendingPathComponent("menubar/codex_dream_skin.10s.sh")
    ]
    if let pluginDirectory = UserDefaults(suiteName: "com.ameba.SwiftBar")?
      .string(forKey: "PluginDirectory"), !pluginDirectory.isEmpty {
      candidates.append(
        URL(fileURLWithPath: pluginDirectory, isDirectory: true)
          .appendingPathComponent("codex_dream_skin.10s.sh")
      )
    }
    var seen = Set<String>()
    return candidates.filter {
      let path = $0.standardizedFileURL.path
      guard seen.insert(path).inserted else { return false }
      return fileManager.fileExists(atPath: path)
    }
  }

  private func disableLegacySwiftBarPlugins(confirmFirst: Bool) {
    let plugins = legacyPluginURLs()
    guard !plugins.isEmpty else { return }
    if confirmFirst {
      let alert = NSAlert()
      alert.messageText = "停用旧 SwiftBar 菜单？"
      alert.informativeText = "已检测到旧版 Dream Skin SwiftBar 插件。停用后可避免菜单栏出现两个图标；插件会改名保留，不会直接删除。"
      alert.addButton(withTitle: "停用旧插件")
      alert.addButton(withTitle: "稍后")
      activateForUserInteraction()
      guard alert.runModal() == .alertFirstButtonReturn else { return }
    }
    var failures: [String] = []
    for plugin in plugins {
      var destination = plugin.appendingPathExtension("disabled")
      if fileManager.fileExists(atPath: destination.path) {
        destination = plugin.appendingPathExtension("disabled-\(Int(Date().timeIntervalSince1970))")
      }
      do {
        try fileManager.moveItem(at: plugin, to: destination)
      } catch {
        failures.append("\(plugin.path): \(error.localizedDescription)")
      }
    }
    if let refreshURL = URL(string: "swiftbar://refreshall") {
      NSWorkspace.shared.open(refreshURL)
    }
    if failures.isEmpty {
      showInfo(title: "旧菜单已停用", message: "SwiftBar 插件已安全改名保留。")
    } else {
      showError(title: "部分旧插件未能停用", message: failures.joined(separator: "\n"))
    }
  }

  private func conciseOutput(_ output: String, fallback: String) -> String {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return fallback }
    let lines = trimmed.split(whereSeparator: \.isNewline).suffix(8)
    return String(lines.joined(separator: "\n")).prefix(1_200).description
  }

  private func activateForUserInteraction() {
    NSApp.activate(ignoringOtherApps: true)
  }

  /// DreamSkin is an LSUIElement with no Dock icon or regular window, so
  /// macOS does not automatically return focus to Codex once this app's own
  /// alert closes. Without this, `document.visibilityState` in the Codex
  /// renderer stays "hidden" for the confirm dialog's caller, so the
  /// rollback-snapshot verification in captureActiveThemeThenApplyImported
  /// spuriously fails and cancels every community apply even though the
  /// visible theme content is correct.
  private func reactivateCodexBeforeTransaction() {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
      .first?.activate(options: [.activateIgnoringOtherApps])
  }

  private func showInfo(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "好")
    activateForUserInteraction()
    alert.runModal()
  }

  private func showError(title: String, message: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "好")
    activateForUserInteraction()
    alert.runModal()
  }
}
