import Foundation
import AppKit

extension Notification.Name {
    static let menuFoldSettingsDidChange = Notification.Name("MenuFold.settingsDidChange")
}

enum AppLanguage: String, CaseIterable {
    case system
    case ko
    case en
    case ja
    case es

    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("ko") { return .ko }
        if preferred.hasPrefix("ja") { return .ja }
        if preferred.hasPrefix("es") { return .es }
        return .en
    }
}

enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark
}

enum MenuBarContentMode: String, CaseIterable {
    case network
    case appIcon
}

enum MenuBarFoldMode: String, CaseIterable {
    case keepExpanded
    case automatic
}

enum QuickLaunchIconSize: String, CaseIterable {
    case small
    case normal
    case large

    var points: CGFloat {
        switch self {
        case .small: return 24
        case .normal: return 28
        case .large: return 32
        }
    }
}

enum MenuBarDisplayStyle: String, CaseIterable {
    case twoLineCompact
    case oneLineCompact
}

enum TrafficDisplay: String, CaseIterable {
    case both
    case downloadOnly
    case uploadOnly
}

enum NetworkOrder: String, CaseIterable {
    case downloadUpload
    case uploadDownload
}

enum ArrowDisplay: String, CaseIterable {
    case hidden
    case shown
}

enum SpeedUnitMode: String, CaseIterable {
    case simple
    case unit
    case bits
}

enum MenuBarFontSize: String, CaseIterable {
    case small
    case normal
    case large
    case extraLarge

    var scale: CGFloat {
        switch self {
        case .small: return 0.90
        case .normal: return 1.0
        case .large: return 1.12
        case .extraLarge: return 1.28
        }
    }
}

enum AwakeOption: String, CaseIterable, Codable {
    case minutes15
    case minutes30
    case minutes60
    case minutes120
    case minutes180
    case until22
    case until23
    case until00

    var minutes: Int? {
        switch self {
        case .minutes15: return 15
        case .minutes30: return 30
        case .minutes60: return 60
        case .minutes120: return 120
        case .minutes180: return 180
        default: return nil
        }
    }

    var untilHour: Int? {
        switch self {
        case .until22: return 22
        case .until23: return 23
        case .until00: return 0
        default: return nil
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .minutes15: return L10n.text("awake.15m", language: language)
        case .minutes30: return L10n.text("awake.30m", language: language)
        case .minutes60: return L10n.text("awake.1h", language: language)
        case .minutes120: return L10n.text("awake.2h", language: language)
        case .minutes180: return L10n.text("awake.3h", language: language)
        case .until22: return L10n.text("awake.until22", language: language)
        case .until23: return L10n.text("awake.until23", language: language)
        case .until00: return L10n.text("awake.until00", language: language)
        }
    }
}

enum AwakePresetMode: String, CaseIterable, Codable {
    case duration
    case untilDate
}

enum AwakeDurationUnit: String, CaseIterable, Codable {
    case hours
    case minutes

    var secondsPerUnit: TimeInterval {
        switch self {
        case .hours: return 3600
        case .minutes: return 60
        }
    }
}

struct AwakePreset: Codable, Equatable {
    var mode: AwakePresetMode
    var durationValue: Int
    var durationUnit: AwakeDurationUnit
    var endDate: Date

    static func duration(_ value: Int, unit: AwakeDurationUnit) -> AwakePreset {
        AwakePreset(mode: .duration, durationValue: max(1, value), durationUnit: unit, endDate: Date())
    }

    static func until(_ date: Date) -> AwakePreset {
        AwakePreset(mode: .untilDate, durationValue: 1, durationUnit: .hours, endDate: date)
    }

    func tooltip(language: AppLanguage) -> String {
        switch mode {
        case .duration:
            let unitKey = durationUnit == .hours ? "awake.unit.hours" : "awake.unit.minutes"
            return "\(durationValue)\(L10n.text(unitKey, language: language)) \(L10n.text("awake.durationSuffix", language: language))"
        case .untilDate:
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.calendar = Calendar.current
            formatter.timeZone = TimeZone.current
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "\(formatter.string(from: endDate)) \(L10n.text("awake.untilSuffix", language: language))"
        }
    }
}

enum L10n {
    static func text(_ key: String, language: AppLanguage) -> String {
        let lang = language.resolved
        return strings[key]?[lang] ?? strings[key]?[.en] ?? key
    }

    private static let strings: [String: [AppLanguage: String]] = [
        "menu.organize": [.ko: "메뉴바 정리", .en: "Organize Menu Bar", .ja: "メニューバー整理", .es: "Organizar barra de menús"],
        "menu.settings": [.ko: "설정…", .en: "Settings…", .ja: "設定…", .es: "Ajustes…"],
        "menu.quit": [.ko: "MenuFold 종료", .en: "Quit MenuFold", .ja: "MenuFoldを終了", .es: "Salir de MenuFold"],
        "menu.finishOrganize": [.ko: "정리 완료", .en: "Finish Organizing", .ja: "整理を完了", .es: "Finalizar organización"],
        "menu.organizeHelp": [.ko: "Command 키를 누른 채 숨길 메뉴바 아이콘을 두 Fold 마커 사이로 옮긴 뒤 MenuFold 우클릭으로 접으세요.", .en: "Hold Command, move the menu bar items you want to hide between the two Fold markers, then right-click MenuFold to fold them.", .ja: "Commandキーを押しながら隠したい項目を > とMenuFoldの間へ移動し、> をクリックします。", .es: "Mantén pulsado Command, mueve los iconos que quieras ocultar entre > y MenuFold y pulsa >."],
        "menu.foldHelp": [.ko: "숨김 영역을 다시 접습니다.", .en: "Fold the hidden area again.", .ja: "非表示領域をもう一度折りたたみます。", .es: "Vuelve a plegar el área oculta."],
        "menu.foldZoneStart": [.ko: "숨김 영역 시작", .en: "Hidden area start", .ja: "非表示領域の開始", .es: "Inicio del área oculta"],
        "menu.foldToggle": [.ko: "숨김 영역 접기/펼치기", .en: "Fold or expand hidden area", .ja: "非表示領域を折りたたむ／展開", .es: "Plegar o desplegar el área oculta"],
        "menu.foldHide": [.ko: "숨김 영역 접기", .en: "Fold hidden area", .ja: "非表示領域を折りたたむ", .es: "Plegar el área oculta"],
        "menu.foldShow": [.ko: "숨김 영역 펼치기", .en: "Expand hidden area", .ja: "非表示領域を展開", .es: "Desplegar el área oculta"],
        "menu.keepExpanded": [.ko: "메뉴바 확장 유지", .en: "Keep Expanded", .ja: "展開を維持", .es: "Mantener abierto"],
        "menu.foldNow": [.ko: "메뉴바 접기", .en: "Fold Menu Bar", .ja: "メニューバーを折りたたむ", .es: "Plegar barra"],
        "menu.keepExpandedHelp": [.ko: "숨김 영역을 펼친 상태로 유지합니다.", .en: "Keep the hidden area expanded.", .ja: "非表示領域を展開したままにします。", .es: "Mantiene expandida el área oculta."],
        "menu.foldNowHelp": [.ko: "숨김 영역을 다시 접습니다.", .en: "Fold the hidden area again.", .ja: "非表示領域を再び折りたたみます。", .es: "Vuelve a plegar el área oculta."],
        "action.settings": [.ko: "설정", .en: "Settings", .ja: "設定", .es: "Ajustes"],
        "action.quit": [.ko: "종료", .en: "Quit", .ja: "終了", .es: "Salir"],
        "awake.title": [.ko: "잠자기 방지", .en: "Keep Awake", .ja: "スリープ防止", .es: "Mantener activo"],
        "awake.off": [.ko: "끔", .en: "Off", .ja: "オフ", .es: "No"],
        "awake.forever": [.ko: "계속", .en: "Always", .ja: "継続", .es: "Siempre"],
        "awake.15m": [.ko: "15분", .en: "15 min", .ja: "15分", .es: "15 min"],
        "awake.30m": [.ko: "30분", .en: "30 min", .ja: "30分", .es: "30 min"],
        "awake.1h": [.ko: "1시간", .en: "1 hour", .ja: "1時間", .es: "1 h"],
        "awake.2h": [.ko: "2시간", .en: "2 hours", .ja: "2時間", .es: "2 h"],
        "awake.3h": [.ko: "3시간", .en: "3 hours", .ja: "3時間", .es: "3 h"],
        "awake.until22": [.ko: "22시까지", .en: "Until 22:00", .ja: "22時まで", .es: "Hasta 22:00"],
        "awake.until23": [.ko: "23시까지", .en: "Until 23:00", .ja: "23時まで", .es: "Hasta 23:00"],
        "awake.until00": [.ko: "00시까지", .en: "Until 00:00", .ja: "0時まで", .es: "Hasta 00:00"],
        "settings.title": [.ko: "MenuFold 설정", .en: "MenuFold Settings", .ja: "MenuFold 設定", .es: "Ajustes de MenuFold"],
        "settings.general": [.ko: "일반", .en: "General", .ja: "一般", .es: "General"],
        "settings.language": [.ko: "언어 (Language)", .en: "Language", .ja: "言語 (Language)", .es: "Idioma (Language)"],
        "settings.appearance": [.ko: "화면 모드", .en: "Appearance", .ja: "外観", .es: "Apariencia"],
        "language.system": [.ko: "시스템 설정 따름", .en: "Follow System", .ja: "システム設定に従う", .es: "Seguir sistema"],
        "language.ko": [.ko: "한국어", .en: "Korean", .ja: "韓国語", .es: "Coreano"],
        "language.en": [.ko: "영어", .en: "English", .ja: "英語", .es: "Inglés"],
        "language.ja": [.ko: "일본어", .en: "Japanese", .ja: "日本語", .es: "Japonés"],
        "language.es": [.ko: "스페인어", .en: "Spanish", .ja: "スペイン語", .es: "Español"],
        "appearance.system": [.ko: "시스템 설정 따름", .en: "Follow System", .ja: "システム設定に従う", .es: "Seguir sistema"],
        "appearance.light": [.ko: "라이트", .en: "Light", .ja: "ライト", .es: "Claro"],
        "appearance.dark": [.ko: "다크", .en: "Dark", .ja: "ダーク", .es: "Oscuro"],
        "settings.menuBarDisplay": [.ko: "메뉴바 설정", .en: "Menu Bar Settings", .ja: "メニューバー設定", .es: "Ajustes de barra de menús"],
        "settings.menuBarContent": [.ko: "메뉴바 표시", .en: "Menu Bar Display", .ja: "メニューバー表示", .es: "Visualización de barra"],
        "menuBarContent.network": [.ko: "네트워크 정보", .en: "Network Information", .ja: "ネットワーク情報", .es: "Información de red"],
        "menuBarContent.appIcon": [.ko: "MenuFold 아이콘", .en: "MenuFold Icon", .ja: "MenuFold アイコン", .es: "Icono de MenuFold"],
        "settings.networkPausedHelp": [.ko: "MenuFold 아이콘 모드에서는 네트워크 측정을 중지해 CPU와 배터리 사용을 줄입니다.", .en: "MenuFold Icon mode stops network monitoring to reduce CPU and battery use.", .ja: "MenuFoldアイコンモードではネットワーク計測を停止し、CPUとバッテリー消費を抑えます。", .es: "El modo Icono de MenuFold detiene la monitorización de red para reducir el uso de CPU y batería."],
        "settings.menuBarFoldMode": [.ko: "메뉴바 접기", .en: "Menu Bar Folding", .ja: "メニューバー折りたたみ", .es: "Plegado de la barra"],
        "foldMode.keepExpanded": [.ko: "계속 확장", .en: "Keep Expanded", .ja: "常に展開", .es: "Mantener abierto"],
        "foldMode.automatic": [.ko: "자동", .en: "Automatic", .ja: "自動", .es: "Automático"],
        "settings.autoFoldDelay": [.ko: "자동 접기", .en: "Auto Fold", .ja: "自動折りたたみ", .es: "Plegado automático"],
        "settings.autoFoldSecondsSuffix": [.ko: "초 후", .en: "sec", .ja: "秒後", .es: "s después"],
        "settings.autoFoldPointer": [.ko: "메뉴바에 마우스가 있으면", .en: "While pointer is in menu bar", .ja: "ポインタがメニューバーにある間", .es: "Mientras el puntero esté en la barra"],
        "settings.autoFoldWait": [.ko: "기다리기", .en: "Wait", .ja: "待機", .es: "Esperar"],
        "menu.foldPin": [.ko: "우클릭하여 메뉴바 확장 유지", .en: "Right-click to keep the menu bar expanded", .ja: "右クリックで展開を維持", .es: "Clic derecho para mantener expandido"],
        "menu.foldPinned": [.ko: "메뉴바 확장 유지 중", .en: "Menu bar expansion is locked", .ja: "メニューバー展開を維持中", .es: "Expansión de barra bloqueada"],
        "settings.menuBarGuideTitle": [.ko: "메뉴바 관리 안내", .en: "Menu Bar Management", .ja: "メニューバー管理ガイド", .es: "Guía de gestión de la barra"],
        "settings.menuBarGuideBody": [.ko: "Fold 아이콘 왼쪽의 모든 항목이 숨김 영역입니다. Command 키를 누른 채 항목을 Fold 아이콘의 왼쪽 또는 오른쪽으로 옮겨 숨김 여부를 정하세요. MenuFold는 보이는 영역 어디에 두어도 되며, MenuFold를 우클릭하면 접기/펼치기를 전환합니다.", .en: "Everything left of the Fold icon belongs to the hidden area. Hold Command and move items to either side of the Fold icon to choose whether they fold. MenuFold can sit anywhere in the visible area; right-click MenuFold to fold or expand.", .ja: "Foldアイコンの左側にあるすべての項目が非表示領域です。Commandキーを押しながら項目をFoldアイコンの左右へ移動して、隠すかどうかを決めます。MenuFoldは表示領域のどこに置いてもよく、MenuFoldを右クリックすると折りたたみ／展開を切り替えます。", .es: "Todo lo que quede a la izquierda del icono Fold pertenece al área oculta. Mantén Command y mueve los elementos a uno u otro lado del icono Fold para decidir si se pliegan. MenuFold puede estar en cualquier parte del área visible; haz clic derecho en MenuFold para plegar o desplegar."],
        "settings.menuBarGuideHidden": [.ko: "숨김영역", .en: "Hidden area", .ja: "非表示領域", .es: "Área oculta"],
        "settings.menuBarGuideVisible": [.ko: "보이는영역", .en: "Visible area", .ja: "表示領域", .es: "Área visible"],
        "settings.menuBarGuideMain": [.ko: "네트워크 정보 / MenuFold 아이콘", .en: "Network / MenuFold Icon", .ja: "ネットワーク / MenuFoldアイコン", .es: "Red / Icono MenuFold"],
        "menu.foldWarningTitle": [.ko: "메뉴바 관리 안내", .en: "Menu Bar Management", .ja: "メニューバー管理ガイド", .es: "Gestión de la barra de menús"],
        "menu.foldWarningBody": [.ko: "이 아이콘 왼쪽의 모든 항목이 가려집니다.", .en: "All items to the left of this icon will be hidden.", .ja: "このアイコンの左側にあるすべての項目が非表示になります。", .es: "Todos los elementos a la izquierda de este icono se ocultarán."],
        "menu.foldWarningSuppress": [.ko: "다시 표시하지 않기", .en: "Do not show again", .ja: "今後表示しない", .es: "No volver a mostrar"],
        "action.confirm": [.ko: "확인", .en: "OK", .ja: "確認", .es: "Aceptar"],
        "settings.info": [.ko: "정보", .en: "Information", .ja: "情報", .es: "Información"],
        "info.description": [.ko: "네트워크 정보 확인, 잠자기 방지, 빠른 실행, 메뉴바 정리를\n한 곳에 모은 앱입니다.", .en: "An app that brings network information, keep-awake, Quick Launch, and menu bar organization together in one place.", .ja: "ネットワーク情報、スリープ防止、クイック起動、メニューバー整理を\nひとつにまとめたアプリです。", .es: "Una app que reúne en un solo lugar la información de red, la prevención de reposo, el inicio rápido y la organización de la barra de menús."],
        "info.credit": [.ko: "이 앱은 Bak2YA가 ChatGPT와 함께 만들었습니다.", .en: "This app was made by Bak2YA together with ChatGPT.", .ja: "このアプリはBak2YAがChatGPTと一緒に作りました。", .es: "Esta app fue creada por Bak2YA junto con ChatGPT."],
        "info.github": [.ko: "GitHub에서 보기", .en: "View on GitHub", .ja: "GitHubで見る", .es: "Ver en GitHub"],
        "info.appStore": [.ko: "App Store에서 보기 (업데이트 확인)", .en: "View on the App Store (Check for Updates)", .ja: "App Storeで見る（アップデート確認）", .es: "Ver en App Store (Buscar actualizaciones)"],
        "info.snack": [.ko: "마님이에게 간식주기", .en: "Buy Maneem a Snack", .ja: "マニムにおやつをあげる", .es: "Invitar a Maneem a un snack"],
        "info.snackIntro": [.ko: "MenuFold가 마음에 들었다면 개발자의 고양이 마님이🐈‍⬛에게 작은 간식을 선물해주세요.\n간식을 안 주셔도 당연히 앱의 모든 기능은 영원히 무료예요!🫰", .en: "If you like MenuFold, you can send a small snack to the developer's cat, Maneem🐈‍⬛.\nEven if you don't, every feature in the app will always be free!🫰", .ja: "MenuFoldを気に入っていただけたら、開発者の猫マニム🐈‍⬛に小さなおやつを贈ってください。\nおやつを贈らなくても、もちろんアプリのすべての機能はずっと無料です！🫰", .es: "Si te gusta MenuFold, puedes regalarle un pequeño snack a Maneem🐈‍⬛, el gato del desarrollador.\nAunque no lo hagas, todas las funciones de la app serán gratis para siempre.🫰"],
        "snack.easterEgg": [.ko: "이스터에그처럼 만들고 싶어서 사진을 많이 넣었어요!\n더 많은 마님이를 보고 싶으시면 닫기 후 다시 눌러주세요 😁", .en: "I added lots of photos to make this a little easter egg!\nIf you want to see more Maneem, close this and open it again 😁", .ja: "イースターエッグみたいにしたくて、写真をたくさん入れました！\nもっとマニムを見たいときは、閉じてもう一度開いてください 😁", .es: "¡Puse muchas fotos para convertir esto en un pequeño easter egg!\nSi quieres ver más de Maneem, cierra esta ventana y ábrela otra vez 😁"],
        "snack.noPhotoUnlock": [.ko: "(간식 주신다고 사진이 더 나오진 않아요 ㅎㅎ)", .en: "(Sending a snack doesn't unlock more photos ㅎㅎ)", .ja: "（おやつを贈っても写真が増えるわけではありません ㅎㅎ）", .es: "(Dar un snack no desbloquea más fotos ㅎㅎ)"],
        "snack.close": [.ko: "닫기", .en: "Close", .ja: "閉じる", .es: "Cerrar"],
        "snack.loadingPrice": [.ko: "간식주기 · 가격 확인 중…", .en: "Buy a Snack · Loading Price…", .ja: "おやつをあげる · 価格確認中…", .es: "Dar un snack · Cargando precio…"],
        "snack.priceUnavailable": [.ko: "가격을 불러오지 못했어요", .en: "Price Unavailable", .ja: "価格を取得できません", .es: "Precio no disponible"],
        "snack.buyFormat": [.ko: "간식주기 · %@", .en: "Buy a Snack · %@", .ja: "おやつをあげる · %@", .es: "Dar un snack · %@"],
        "snack.thanks": [.ko: "감사해요! 이걸로 정말 마님이 간식 사줄게요!", .en: "Thank you! I'll really use this to buy Maneem a snack!", .ja: "ありがとうございます！これで本当にマニムのおやつを買います！", .es: "¡Gracias! De verdad usaré esto para comprarle un snack a Maneem."],
        "snack.pendingButton": [.ko: "승인 대기 중…", .en: "Awaiting Approval…", .ja: "承認待ち…", .es: "Esperando aprobación…"],
        "snack.pendingTitle": [.ko: "결제 승인 대기 중", .en: "Purchase Pending", .ja: "購入の承認待ち", .es: "Compra pendiente"],
        "snack.pendingMessage": [.ko: "App Store에서 결제 승인을 기다리고 있어요.", .en: "The App Store is waiting for purchase approval.", .ja: "App Storeで購入の承認を待っています。", .es: "App Store está esperando la aprobación de la compra."],
        "snack.errorTitle": [.ko: "간식주기를 완료하지 못했어요", .en: "Couldn't Complete Purchase", .ja: "購入を完了できませんでした", .es: "No se pudo completar la compra"],
        "snack.errorMessage": [.ko: "잠시 후 다시 시도해주세요.", .en: "Please try again in a moment.", .ja: "しばらくしてからもう一度お試しください。", .es: "Inténtalo de nuevo dentro de un momento."],
        "snack.ok": [.ko: "확인", .en: "OK", .ja: "確認", .es: "Aceptar"],
        "snack.comingLaterButton": [.ko: "나중에 추가할게요!", .en: "I’ll add this later!", .ja: "あとで追加します！", .es: "¡Lo añadiré más adelante!"],
        "snack.businessPending": [.ko: "아직 사업자가 없어요!\n간식 주시려고 했던 마음만 받을게요! 감사합니다!ㅎㅎ", .en: "I don’t have a registered business yet!\nFor now, I’ll just gratefully accept the thought. Thank you! ㅎㅎ", .ja: "まだ事業者登録がないんです！\n今はおやつを贈ろうとしてくれたお気持ちだけ、ありがたく受け取ります！ありがとうございます！ㅎㅎ", .es: "¡Todavía no tengo un negocio registrado!\nPor ahora, me quedo agradecido con la intención. ¡Muchas gracias! ㅎㅎ"],
        "info.linkPending": [.ko: "링크 준비 중", .en: "Link coming soon", .ja: "リンク準備中", .es: "Enlace próximamente"],
        "settings.displayStyle": [.ko: "표시 형태", .en: "Layout", .ja: "表示形式", .es: "Diseño"],
        "style.twoLineCompact": [.ko: "두 줄", .en: "Two lines", .ja: "2行", .es: "Dos líneas"],
        "style.oneLineCompact": [.ko: "한 줄", .en: "One line", .ja: "1行", .es: "Una línea"],
        "settings.traffic": [.ko: "표시 항목", .en: "Traffic", .ja: "表示項目", .es: "Tráfico"],
        "traffic.both": [.ko: "다운로드 + 업로드", .en: "Download + Upload", .ja: "ダウンロード + アップロード", .es: "Descarga + Subida"],
        "traffic.download": [.ko: "다운로드만", .en: "Download only", .ja: "ダウンロードのみ", .es: "Solo descarga"],
        "traffic.upload": [.ko: "업로드만", .en: "Upload only", .ja: "アップロードのみ", .es: "Solo subida"],
        "settings.order": [.ko: "순서", .en: "Order", .ja: "順序", .es: "Orden"],
        "order.downloadFirst": [.ko: "다운로드 먼저", .en: "Download first", .ja: "ダウンロードを先に", .es: "Descarga primero"],
        "order.uploadFirst": [.ko: "업로드 먼저", .en: "Upload first", .ja: "アップロードを先に", .es: "Subida primero"],
        "settings.arrows": [.ko: "화살표", .en: "Arrows", .ja: "矢印", .es: "Flechas"],
        "arrows.hidden": [.ko: "표시 안 함", .en: "Hide", .ja: "表示しない", .es: "Ocultar"],
        "arrows.shown": [.ko: "표시", .en: "Show", .ja: "表示", .es: "Mostrar"],
        "settings.units": [.ko: "단위 표시", .en: "Units", .ja: "単位表示", .es: "Unidades"],
        "unit.simple": [.ko: "간단 (1.2M)", .en: "Simple (1.2M)", .ja: "簡単 (1.2M)", .es: "Simple (1.2M)"],
        "unit.unit": [.ko: "단위 (1.2 MB/s)", .en: "Units (1.2 MB/s)", .ja: "単位 (1.2 MB/s)", .es: "Unidades (1.2 MB/s)"],
        "unit.bits": [.ko: "비트 (9.6 Mbps)", .en: "Bits (9.6 Mbps)", .ja: "ビット (9.6 Mbps)", .es: "Bits (9.6 Mbps)"],
        "settings.fontSize": [.ko: "글자 크기", .en: "Text Size", .ja: "文字サイズ", .es: "Tamaño de texto"],
        "font.small": [.ko: "작게", .en: "Small", .ja: "小", .es: "Pequeño"],
        "font.normal": [.ko: "보통", .en: "Default", .ja: "標準", .es: "Normal"],
        "font.large": [.ko: "크게", .en: "Large", .ja: "大", .es: "Grande"],
        "font.extraLarge": [.ko: "아주 크게", .en: "Extra Large", .ja: "特大", .es: "Muy grande"],
        "settings.refresh": [.ko: "갱신 간격", .en: "Refresh", .ja: "更新間隔", .es: "Actualización"],
        "settings.secondsSuffix": [.ko: "초", .en: "sec", .ja: "秒", .es: "s"],
        "settings.awake": [.ko: "잠자기 방지", .en: "Keep Awake", .ja: "スリープ防止", .es: "Mantener activo"],
        "settings.awakeTimeTitle": [.ko: "잠자기 방지 시간 설정", .en: "Keep Awake Time Settings", .ja: "スリープ防止時間設定", .es: "Ajustes de tiempo activo"],
        "settings.awakeButton": [.ko: "버튼", .en: "Button", .ja: "ボタン", .es: "Botón"],
        "settings.awakeMode.duration": [.ko: "기간 설정", .en: "Duration", .ja: "期間設定", .es: "Duración"],
        "settings.awakeMode.until": [.ko: "종료시간 입력", .en: "End Time", .ja: "終了時刻入力", .es: "Hora de finalización"],
        "awake.unit.hours": [.ko: "시간", .en: " hr", .ja: "時間", .es: " h"],
        "awake.unit.minutes": [.ko: "분", .en: " min", .ja: "分", .es: " min"],
        "awake.durationSuffix": [.ko: "동안", .en: "", .ja: "の間", .es: ""],
        "awake.untilSuffix": [.ko: "까지", .en: "until", .ja: "まで", .es: "hasta"],
        "settings.awakeAdd": [.ko: "버튼 추가", .en: "Add Button", .ja: "ボタンを追加", .es: "Añadir botón"],
        "settings.awakeMaximum": [.ko: "최대 4개의 잠자기 방지 버튼을 만들 수 있습니다.", .en: "You can create up to 4 keep-awake buttons.", .ja: "スリープ防止ボタンは最大4個まで作成できます。", .es: "Puedes crear hasta 4 botones para mantener activo."],
        "settings.awakeRemove": [.ko: "버튼 삭제", .en: "Remove Button", .ja: "ボタンを削除", .es: "Eliminar botón"],
        "settings.quickLaunch": [.ko: "빠른 실행", .en: "Quick Launch", .ja: "クイック起動", .es: "Inicio rápido"],
        "settings.quickIconSize": [.ko: "빠른 실행 아이콘 크기", .en: "Quick Launch Icon Size", .ja: "クイック起動アイコンサイズ", .es: "Tamaño de iconos de inicio rápido"],
        "quickIcon.small": [.ko: "작게", .en: "Small", .ja: "小", .es: "Pequeño"],
        "quickIcon.normal": [.ko: "보통", .en: "Default", .ja: "標準", .es: "Normal"],
        "quickIcon.large": [.ko: "크게", .en: "Large", .ja: "大", .es: "Grande"],
        "quick.addApp": [.ko: "앱 추가…", .en: "Add App…", .ja: "アプリを追加…", .es: "Añadir app…"],
        "quick.addFile": [.ko: "파일 또는 폴더 추가…", .en: "Add File or Folder…", .ja: "ファイルまたはフォルダを追加…", .es: "Añadir archivo o carpeta…"],
        "quick.addWeb": [.ko: "웹 주소 추가…", .en: "Add Web Address…", .ja: "Webアドレスを追加…", .es: "Añadir dirección web…"],
        "quick.addSetting": [.ko: "시스템 설정 추가", .en: "Add System Setting", .ja: "システム設定を追加", .es: "Añadir ajuste del sistema"],
        "quick.moveUp": [.ko: "위로", .en: "Move Up", .ja: "上へ", .es: "Subir"],
        "quick.moveDown": [.ko: "아래로", .en: "Move Down", .ja: "下へ", .es: "Bajar"],
        "quick.remove": [.ko: "삭제", .en: "Remove", .ja: "削除", .es: "Eliminar"],
        "quick.webName": [.ko: "이름", .en: "Name", .ja: "名前", .es: "Nombre"],
        "quick.webAddress": [.ko: "주소", .en: "Address", .ja: "アドレス", .es: "Dirección"],
        "quick.webTitle": [.ko: "웹 주소 추가", .en: "Add Web Address", .ja: "Webアドレスを追加", .es: "Añadir dirección web"],
        "action.add": [.ko: "추가", .en: "Add", .ja: "追加", .es: "Añadir"],
        "action.cancel": [.ko: "취소", .en: "Cancel", .ja: "キャンセル", .es: "Cancelar"],
        "quick.type.app": [.ko: "앱", .en: "App", .ja: "アプリ", .es: "App"],
        "quick.type.file": [.ko: "파일/폴더", .en: "File/Folder", .ja: "ファイル/フォルダ", .es: "Archivo/Carpeta"],
        "quick.type.web": [.ko: "웹", .en: "Web", .ja: "Web", .es: "Web"],
        "quick.type.setting": [.ko: "시스템 설정", .en: "System Setting", .ja: "システム設定", .es: "Ajuste del sistema"],
        "quick.iconColor": [.ko: "아이콘 색상", .en: "Icon Color", .ja: "アイコン色", .es: "Color del icono"],
        "quick.color.default": [.ko: "기본", .en: "Default", .ja: "標準", .es: "Predeterminado"],
        "quick.color.red": [.ko: "빨강", .en: "Red", .ja: "赤", .es: "Rojo"],
        "quick.color.orange": [.ko: "주황", .en: "Orange", .ja: "オレンジ", .es: "Naranja"],
        "quick.color.yellow": [.ko: "노랑", .en: "Yellow", .ja: "黄", .es: "Amarillo"],
        "quick.color.green": [.ko: "초록", .en: "Green", .ja: "緑", .es: "Verde"],
        "quick.color.blue": [.ko: "파랑", .en: "Blue", .ja: "青", .es: "Azul"],
        "quick.color.sky": [.ko: "하늘", .en: "Sky", .ja: "空色", .es: "Celeste"],
        "quick.color.purple": [.ko: "보라", .en: "Purple", .ja: "紫", .es: "Morado"],
        "quick.color.pink": [.ko: "핑크", .en: "Pink", .ja: "ピンク", .es: "Rosa"],
        "quick.color.burgundy": [.ko: "버건디", .en: "Burgundy", .ja: "バーガンディ", .es: "Borgoña"],
        "quick.color.gray": [.ko: "회색", .en: "Gray", .ja: "グレー", .es: "Gris"],
        "setting.wifi": [.ko: "Wi-Fi", .en: "Wi-Fi", .ja: "Wi-Fi", .es: "Wi-Fi"],
        "setting.bluetooth": [.ko: "Bluetooth", .en: "Bluetooth", .ja: "Bluetooth", .es: "Bluetooth"],
        "setting.display": [.ko: "디스플레이", .en: "Displays", .ja: "ディスプレイ", .es: "Pantallas"],
        "setting.battery": [.ko: "배터리", .en: "Battery", .ja: "バッテリー", .es: "Batería"],
        "setting.keyboard": [.ko: "키보드", .en: "Keyboard", .ja: "キーボード", .es: "Teclado"],
        "setting.mouse": [.ko: "마우스", .en: "Mouse", .ja: "マウス", .es: "Ratón"],
        "setting.trackpad": [.ko: "트랙패드", .en: "Trackpad", .ja: "トラックパッド", .es: "Trackpad"],
        "setting.privacy": [.ko: "개인정보 보호 및 보안", .en: "Privacy & Security", .ja: "プライバシーとセキュリティ", .es: "Privacidad y seguridad"],
        "setting.accessibility": [.ko: "손쉬운 사용", .en: "Accessibility", .ja: "アクセシビリティ", .es: "Accesibilidad"]
    ]
}

enum MenuBarOrganizerSchema {
    /// MenuFold itself stays permanently compact. The native manifold helper
    /// owns only the fold spacer/placement; Build 28 renders the visible
    /// manifold as a non-draggable overlay at the same boundary.
    static let version = 10
    static let mainStatusAutosaveName = "MenuFold.OrganizerLayout6.MainStatus"
    static let foldControlAutosaveName = "MenuFold.OrganizerLayout10.ManifoldControl"
}

final class AppSettings {
    private enum Key {
        static let menuBarContentMode = "menuBarContentMode"
        static let displayStyle = "menuBarDisplayStyle"
        static let trafficDisplay = "trafficDisplay"
        static let networkOrder = "networkOrder"
        static let arrowDisplay = "arrowDisplay"
        static let unitMode = "speedUnitMode"
        static let fontSize = "menuBarFontSize"
        static let refreshInterval = "refreshInterval"
        static let language = "language"
        static let appearance = "appearance"
        static let awakePresets = "awakePresetsV2"
        static let awakeSlot1 = "awakeSlot1" // legacy migration
        static let awakeSlot2 = "awakeSlot2" // legacy migration
        static let hasConfiguredMenuBar = "hasConfiguredMenuBar"
        static let organizerLayoutVersion = "organizerLayoutVersion"
        static let suppressFoldWarning = "suppressFoldWarning"
        static let menuBarFoldMode = "menuBarFoldMode"
        static let autoFoldDelay = "autoFoldDelay"
        static let waitWhilePointerInMenuBar = "waitWhilePointerInMenuBar"
        static let quickLaunchIconSize = "quickLaunchIconSize"
    }

    private let defaults = UserDefaults.standard

    var menuBarContentMode: MenuBarContentMode {
        didSet { store(menuBarContentMode.rawValue, key: Key.menuBarContentMode) }
    }

    var displayStyle: MenuBarDisplayStyle {
        didSet { store(displayStyle.rawValue, key: Key.displayStyle) }
    }

    var trafficDisplay: TrafficDisplay {
        didSet { store(trafficDisplay.rawValue, key: Key.trafficDisplay) }
    }

    var networkOrder: NetworkOrder {
        didSet { store(networkOrder.rawValue, key: Key.networkOrder) }
    }

    var arrowDisplay: ArrowDisplay {
        didSet { store(arrowDisplay.rawValue, key: Key.arrowDisplay) }
    }

    var unitMode: SpeedUnitMode {
        didSet { store(unitMode.rawValue, key: Key.unitMode) }
    }

    var fontSize: MenuBarFontSize {
        didSet { store(fontSize.rawValue, key: Key.fontSize) }
    }

    var refreshInterval: Double {
        didSet {
            let normalized = Self.normalizedRefreshInterval(refreshInterval)
            if abs(normalized - refreshInterval) > 0.0001 {
                refreshInterval = normalized
                return
            }
            store(refreshInterval, key: Key.refreshInterval)
        }
    }

    var language: AppLanguage {
        didSet { store(language.rawValue, key: Key.language) }
    }

    var appearance: AppAppearance {
        didSet { store(appearance.rawValue, key: Key.appearance) }
    }

    var menuBarFoldMode: MenuBarFoldMode {
        didSet { store(menuBarFoldMode.rawValue, key: Key.menuBarFoldMode) }
    }

    var autoFoldDelay: Double {
        didSet { store(min(max(autoFoldDelay, 1), 300), key: Key.autoFoldDelay) }
    }

    var waitWhilePointerInMenuBar: Bool {
        didSet { store(waitWhilePointerInMenuBar, key: Key.waitWhilePointerInMenuBar) }
    }

    var quickLaunchIconSize: QuickLaunchIconSize {
        didSet { store(quickLaunchIconSize.rawValue, key: Key.quickLaunchIconSize) }
    }

    static let maxAwakePresets = 4

    var awakePresets: [AwakePreset] {
        didSet {
            let normalized = Array(awakePresets.prefix(Self.maxAwakePresets))
            if normalized != awakePresets {
                awakePresets = normalized
                return
            }
            if let data = try? JSONEncoder().encode(awakePresets) {
                store(data, key: Key.awakePresets)
            }
        }
    }

    var hasConfiguredMenuBar: Bool {
        didSet { store(hasConfiguredMenuBar, key: Key.hasConfiguredMenuBar) }
    }

    var suppressFoldWarning: Bool {
        didSet { store(suppressFoldWarning, key: Key.suppressFoldWarning) }
    }

    init() {
        menuBarContentMode = MenuBarContentMode(rawValue: defaults.string(forKey: Key.menuBarContentMode) ?? "") ?? .network
        let rawDisplayStyle = defaults.string(forKey: Key.displayStyle) ?? ""
        displayStyle = rawDisplayStyle == "oneLineLarge"
            ? .oneLineCompact
            : (MenuBarDisplayStyle(rawValue: rawDisplayStyle) ?? .twoLineCompact)
        trafficDisplay = TrafficDisplay(rawValue: defaults.string(forKey: Key.trafficDisplay) ?? "") ?? .both
        networkOrder = NetworkOrder(rawValue: defaults.string(forKey: Key.networkOrder) ?? "") ?? .downloadUpload

        if let raw = defaults.string(forKey: Key.arrowDisplay), let value = ArrowDisplay(rawValue: raw) {
            arrowDisplay = value
        } else {
            let old = defaults.object(forKey: "showArrows") as? Bool ?? false
            arrowDisplay = old ? .shown : .hidden
        }

        if let raw = defaults.string(forKey: Key.unitMode), let value = SpeedUnitMode(rawValue: raw) {
            unitMode = value
        } else {
            let old = defaults.object(forKey: "showFullUnits") as? Bool ?? false
            unitMode = old ? .unit : .simple
        }

        let legacyDisplayStyleRaw = defaults.string(forKey: Key.displayStyle) ?? ""
        let savedFontSize = MenuBarFontSize(rawValue: defaults.string(forKey: Key.fontSize) ?? "") ?? .normal
        // Build 36 separates layout from text size. Preserve the old
        // oneLineLarge intent by migrating it to one-line + extra-large.
        fontSize = legacyDisplayStyleRaw == "oneLineLarge" ? .extraLarge : savedFontSize

        if let saved = defaults.object(forKey: Key.refreshInterval) as? NSNumber {
            refreshInterval = Self.normalizedRefreshInterval(saved.doubleValue)
        } else {
            refreshInterval = 3.0
        }
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .system
        appearance = AppAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        menuBarFoldMode = MenuBarFoldMode(rawValue: defaults.string(forKey: Key.menuBarFoldMode) ?? "") ?? .automatic
        let savedAutoFoldDelay = defaults.double(forKey: Key.autoFoldDelay)
        autoFoldDelay = savedAutoFoldDelay >= 1 ? min(savedAutoFoldDelay, 300) : 5
        if defaults.object(forKey: Key.waitWhilePointerInMenuBar) == nil {
            waitWhilePointerInMenuBar = true
        } else {
            waitWhilePointerInMenuBar = defaults.bool(forKey: Key.waitWhilePointerInMenuBar)
        }
        quickLaunchIconSize = QuickLaunchIconSize(rawValue: defaults.string(forKey: Key.quickLaunchIconSize) ?? "") ?? .normal
        if let data = defaults.data(forKey: Key.awakePresets),
           let saved = try? JSONDecoder().decode([AwakePreset].self, from: data),
           !saved.isEmpty {
            var normalized = Array(saved.prefix(Self.maxAwakePresets))
            while normalized.count < 2 { normalized.append(.duration(1, unit: .hours)) }
            awakePresets = normalized
        } else {
            let legacy1 = AwakeOption(rawValue: defaults.string(forKey: Key.awakeSlot1) ?? "") ?? .minutes60
            let legacy2 = AwakeOption(rawValue: defaults.string(forKey: Key.awakeSlot2) ?? "") ?? .until00
            awakePresets = [
                Self.preset(from: legacy1),
                Self.preset(from: legacy2)
            ]
        }
        suppressFoldWarning = defaults.bool(forKey: Key.suppressFoldWarning)
        let organizerVersion = defaults.integer(forKey: Key.organizerLayoutVersion)
        hasConfiguredMenuBar = organizerVersion == MenuBarOrganizerSchema.version && defaults.bool(forKey: Key.hasConfiguredMenuBar)
    }

    func markOrganizerLayoutCurrent() {
        defaults.set(MenuBarOrganizerSchema.version, forKey: Key.organizerLayoutVersion)
    }

    func updateAwakePreset(at index: Int, _ mutate: (inout AwakePreset) -> Void) {
        guard awakePresets.indices.contains(index) else { return }
        var copy = awakePresets
        mutate(&copy[index])
        awakePresets = copy
    }

    func addAwakePreset() {
        guard awakePresets.count < Self.maxAwakePresets else { return }
        awakePresets.append(.duration(1, unit: .hours))
    }

    func removeAwakePreset(at index: Int) {
        guard awakePresets.count > 2, awakePresets.indices.contains(index) else { return }
        awakePresets.remove(at: index)
    }

    private static func preset(from option: AwakeOption) -> AwakePreset {
        if let minutes = option.minutes {
            if minutes % 60 == 0 {
                return .duration(max(1, minutes / 60), unit: .hours)
            }
            return .duration(minutes, unit: .minutes)
        }

        let hour = option.untilHour ?? 0
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = 0
        components.second = 0
        var date = calendar.date(from: components) ?? now.addingTimeInterval(3600)
        if date <= now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? now.addingTimeInterval(86400) }
        return .until(date)
    }

    func localized(_ key: String) -> String {
        L10n.text(key, language: language)
    }

    func applyAppearance() {
        switch appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private static func normalizedRefreshInterval(_ value: Double) -> Double {
        guard value.isFinite else { return 3.0 }
        return max(0.1, (value * 10).rounded() / 10)
    }

    private func store(_ value: Any, key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .menuFoldSettingsDidChange, object: self)
    }
}
