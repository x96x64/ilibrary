// The only file of the probe that touches the macOS accessibility interface. It reads and never acts: it
// copies allow-listed attributes and counts, and it performs no action, sets no attribute, and observes no
// notification. The messaging timeout set on an element is a client-side limit on how long this process waits
// for a reply; it is stored in this process's own element reference and changes nothing in Music.
#if canImport(ApplicationServices) && canImport(AppKit)
    import AppKit
    import ApplicationServices

    /// The result of reading one attribute: a value, a definite absence, or an error code.
    enum Fetch<Value> {
        case value(Value)
        case absent
        case failure(Int32)
    }

    struct MusicProcessSnapshot {
        var state: MusicProcessState
        var processIdentifier: pid_t?
        var musicVersion: String?
        /// The launch date of the process, compared with the identifier so that a replacement process that reuses
        /// the identifier is detected. Nil when the system does not report it, which never confirms identity.
        var launchDate: Date? = nil
    }

    enum AccessibilityReader {
        static let musicBundleIdentifier = "com.apple.Music"
        private static let tableRoles: Set<String> = ["AXTable", "AXOutline"]
        private static let scrollableRoles: Set<String> = [
            "AXScrollArea", "AXTable", "AXOutline", "AXList", "AXBrowser",
        ]
        private static let maximumChildrenPerNode = 2_000

        /// Reads the trust state without prompting: the prompt option is set to false.
        static func isTrustedWithoutPrompting() -> Bool {
            let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }

        /// Looks up the running Music process and reads its identifier and version string only.
        static func musicProcess() -> MusicProcessSnapshot {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleIdentifier)
            guard let application = running.first else {
                return MusicProcessSnapshot(state: .none, processIdentifier: nil, musicVersion: nil)
            }
            let version =
                application.bundleURL.flatMap { Bundle(url: $0) }?
                .infoDictionary?["CFBundleShortVersionString"] as? String
            if running.count > 1 {
                return MusicProcessSnapshot(state: .multiple, processIdentifier: nil, musicVersion: version)
            }
            if application.isTerminated || application.bundleIdentifier != musicBundleIdentifier {
                return MusicProcessSnapshot(state: .terminated, processIdentifier: nil, musicVersion: version)
            }
            return MusicProcessSnapshot(
                state: .exactlyOne, processIdentifier: application.processIdentifier, musicVersion: version,
                launchDate: application.launchDate)
        }

        static func applicationElement(processIdentifier: pid_t) -> AXUIElement {
            AXUIElementCreateApplication(processIdentifier)
        }

        /// Walks the application element and its windows without a profile and returns the raw snapshot.
        static func walk(application: AXUIElement, limits: WalkLimits) -> TreeSnapshot<AXUIElement> {
            let source = MusicTreeSource(timeout: Float(limits.timeoutSeconds))
            return TreeWalker.walk(roots: [application], source: source, limits: limits)
        }

        struct MusicTreeSource: TreeSource {
            var timeout: Float

            private func fetch(_ element: AXUIElement, _ attribute: String) -> Fetch<CFTypeRef> {
                var value: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
                switch error {
                case .success:
                    if let value { return .value(value) }
                    return .absent
                case .noValue, .attributeUnsupported: return .absent
                default: return .failure(error.rawValue)
                }
            }

            private func text(_ element: AXUIElement, _ attribute: String, into facts: inout NodeFacts)
                -> (String?, Bool)
            {
                switch fetch(element, attribute) {
                case .value(let value): return ((value as? String), true)
                case .absent: return (nil, false)
                case .failure(let code):
                    facts.errors.append(AttributeError(attribute: attribute, code: code))
                    return (nil, false)
                }
            }

            private func flag(_ element: AXUIElement, _ attribute: String, into facts: inout NodeFacts) -> Bool? {
                switch fetch(element, attribute) {
                case .value(let value):
                    guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
                    return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
                case .absent: return nil
                case .failure(let code):
                    facts.errors.append(AttributeError(attribute: attribute, code: code))
                    return nil
                }
            }

            private func count(_ element: AXUIElement, _ attribute: String, into facts: inout NodeFacts) -> Int? {
                var total: CFIndex = 0
                let error = AXUIElementGetAttributeValueCount(element, attribute as CFString, &total)
                switch error {
                case .success: return total
                case .noValue, .attributeUnsupported: return nil
                default:
                    facts.errors.append(AttributeError(attribute: attribute, code: error.rawValue))
                    return nil
                }
            }

            /// Whether a scroll bar element is present: true if present, false only when the element supports the
            /// attribute and reports no value, and nil when the attribute is unsupported or unreadable.
            private func scrollBar(
                _ element: AXUIElement, _ attribute: String, into facts: inout NodeFacts
            ) -> (present: Bool?, value: Double?) {
                var raw: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
                let outcome: Fetch<CFTypeRef>
                switch error {
                case .success:
                    guard let raw else { return (nil, nil) }
                    outcome = .value(raw)
                case .noValue: outcome = .absent
                case .attributeUnsupported: return (nil, nil)
                default: outcome = .failure(error.rawValue)
                }
                switch outcome {
                case .absent: return (false, nil)
                case .failure(let code):
                    facts.errors.append(AttributeError(attribute: attribute, code: code))
                    return (nil, nil)
                case .value(let bar):
                    guard CFGetTypeID(bar) == AXUIElementGetTypeID() else { return (true, nil) }
                    let barElement = unsafeDowncast(bar, to: AXUIElement.self)
                    _ = AXUIElementSetMessagingTimeout(barElement, timeout)
                    var scratch = NodeFacts()
                    guard let role = text(barElement, "AXRole", into: &scratch).0, role == "AXScrollBar" else {
                        return (true, nil)
                    }
                    if case .value(let number) = fetch(barElement, "AXValue"),
                        CFGetTypeID(number) == CFNumberGetTypeID()
                    {
                        return (true, (number as? NSNumber)?.doubleValue)
                    }
                    return (true, nil)
                }
            }

            func facts(of element: AXUIElement) -> NodeFacts {
                _ = AXUIElementSetMessagingTimeout(element, timeout)
                var facts = NodeFacts()
                facts.role = text(element, "AXRole", into: &facts).0
                facts.subrole = text(element, "AXSubrole", into: &facts).0
                (facts.identifier, facts.hasIdentifier) = text(element, "AXIdentifier", into: &facts)
                (facts.title, facts.hasTitle) = text(element, "AXTitle", into: &facts)
                (facts.description, facts.hasDescription) = text(element, "AXDescription", into: &facts)
                facts.childCount = count(element, "AXChildren", into: &facts)
                facts.busy = flag(element, "AXBusy", into: &facts)
                let role = facts.role ?? ""
                if AccessibilityReader.tableRoles.contains(role) {
                    facts.rowCount = count(element, "AXRows", into: &facts)
                    facts.visibleRowCount = count(element, "AXVisibleRows", into: &facts)
                }
                if AccessibilityReader.scrollableRoles.contains(role) {
                    facts.hasHorizontalScrollBar = scrollBar(element, "AXHorizontalScrollBar", into: &facts).present
                    let vertical = scrollBar(element, "AXVerticalScrollBar", into: &facts)
                    facts.hasVerticalScrollBar = vertical.present
                    facts.scrollValue = vertical.value
                }
                return facts
            }

            private func elements(_ element: AXUIElement, _ attribute: String) -> Children<AXUIElement> {
                var total: CFIndex = 0
                let countError = AXUIElementGetAttributeValueCount(element, attribute as CFString, &total)
                switch countError {
                case .success: break
                case .noValue, .attributeUnsupported: return Children(nodes: [], error: nil)
                default: return Children(nodes: [], error: countError.rawValue)
                }
                let wanted = min(total, AccessibilityReader.maximumChildrenPerNode)
                guard wanted > 0 else { return Children(nodes: [], error: nil) }
                var values: CFArray?
                let error = AXUIElementCopyAttributeValues(element, attribute as CFString, 0, wanted, &values)
                guard error == .success, let values else {
                    return Children(nodes: [], error: error == .success ? nil : error.rawValue)
                }
                let nodes = (values as [AnyObject]).compactMap { item -> AXUIElement? in
                    CFGetTypeID(item) == AXUIElementGetTypeID() ? unsafeDowncast(item, to: AXUIElement.self) : nil
                }
                return Children(nodes: nodes, error: nil)
            }

            /// The children of an element; for the application element, also its windows without duplicates.
            func children(of element: AXUIElement) -> Children<AXUIElement> {
                _ = AXUIElementSetMessagingTimeout(element, timeout)
                var result = elements(element, "AXChildren")
                var scratch = NodeFacts()
                if text(element, "AXRole", into: &scratch).0 == "AXApplication" {
                    let windows = elements(element, "AXWindows")
                    for window in windows.nodes where !result.nodes.contains(where: { CFEqual($0, window) }) {
                        result.nodes.append(window)
                    }
                    if result.error == nil { result.error = windows.error }
                }
                return result
            }
        }
    }
#endif
