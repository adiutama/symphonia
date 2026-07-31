import AppKit
import SwiftUI

/// Inline Main-canvas New Project form (locked B2).
///
/// Source toggle first → hairline → URL (Remote only) → name (slug) → location → Create.
struct CreateProjectCanvas: View {
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    @FocusState private var focusedField: Field?
    /// When false, URL→name prefill is allowed; set true once the Operator edits the name.
    @State private var nameTouched = false

    private enum Field {
        case url
        case name
    }

    private var nameValidation: Result<String, WorkspaceSlug.ValidationError> {
        WorkspaceSlug.validate(workspaces.createDraftName)
    }

    private var urlValidation: Result<GitRemoteURL.Parsed, GitRemoteURL.ValidationError> {
        GitRemoteURL.validate(workspaces.createDraftCloneURL)
    }

    private var isRemote: Bool {
        workspaces.createDraftSource == .remote
    }

    private var setupReady: Bool {
        if isRemote {
            if case .success = urlValidation { return true }
            return false
        }
        return true
    }

    private var canCreate: Bool {
        if case .success = nameValidation {
            return setupReady
        }
        return false
    }

    private var showNameError: Bool {
        guard setupReady else { return false }
        let trimmed = workspaces.createDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if case .failure = nameValidation { return true }
        return false
    }

    private var showURLError: Bool {
        guard isRemote else { return false }
        let trimmed = workspaces.createDraftCloneURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if case .failure = urlValidation { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 14) {
                    sourceToggle

                    SoftHairline()
                        .padding(.vertical, 2)

                    if isRemote {
                        urlField
                    }

                    setupFields
                        .opacity(setupReady ? 1 : 0.38)
                        .allowsHitTesting(setupReady)

                    statusPreview
                        .opacity(setupReady ? 1 : 0.38)
                }
                .frame(maxWidth: 420)

                actions
                    .padding(.top, 18)

                if let error = workspaces.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 10)
                        .frame(maxWidth: 420)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ghosttyTheme.background)
        .onAppear {
            nameTouched = false
            focusedField = isRemote ? .url : .name
        }
        .onChange(of: workspaces.createDraftSource) { _, source in
            focusedField = source == .remote ? .url : .name
        }
        .onChange(of: workspaces.createDraftCloneURL) { _, url in
            guard isRemote, !nameTouched else { return }
            // Prefill only from a valid remote URL.
            if case .success = GitRemoteURL.validate(url),
               let suggested = suggestedSlug(from: url), !suggested.isEmpty {
                workspaces.createDraftName = suggested
            } else if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                workspaces.createDraftName = ""
            }
        }
    }
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(ghosttyTheme.accent)
                .symbolRenderingMode(.hierarchical)

            Text("Start a project")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ghosttyTheme.foreground)

            Text("Choose how Main starts, then fill in the rest.")
                .font(.subheadline)
                .foregroundStyle(ghosttyTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var sourceToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOURCE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ghosttyTheme.tertiaryText)
                .tracking(0.4)

            HStack(spacing: 3) {
                sourceButton(
                    title: "Remote",
                    subtitle: "Clone a repo",
                    source: .remote
                )
                sourceButton(
                    title: "Local",
                    subtitle: "Empty git init",
                    source: .local
                )
            }
            .padding(4)
            .background(ghosttyTheme.sidebar.opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(ghosttyTheme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func sourceButton(title: String, subtitle: String, source: CreateProjectSource) -> some View {
        let selected = workspaces.createDraftSource == source
        return Button {
            setSource(source)
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(selected ? ghosttyTheme.secondaryText : ghosttyTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(
                selected
                    ? (source == .remote ? ghosttyTheme.accent : Color(nsColor: NSColor.systemGreen).opacity(0.95))
                    : ghosttyTheme.tertiaryText
            )
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? ghosttyTheme.control : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("REPOSITORY URL")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ghosttyTheme.tertiaryText)
                .tracking(0.4)

            softPlaceholderField(
                text: $workspaces.createDraftCloneURL,
                placeholder: "Paste a git URL",
                focused: .url
            )

            if showURLError, case .failure(let error) = urlValidation {
                Text(error.errorDescription ?? "Invalid repository URL.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("HTTPS, HTTP, SSH, or git@host:path — detected automatically.")
                    .font(.caption)
                    .foregroundStyle(ghosttyTheme.tertiaryText)
            }
        }
    }

    private var setupFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("PROJECT NAME")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ghosttyTheme.tertiaryText)
                    .tracking(0.4)

                softPlaceholderField(
                    text: Binding(
                        get: { workspaces.createDraftName },
                        set: {
                            workspaces.createDraftName = $0
                            nameTouched = true
                        }
                    ),
                    placeholder: "Required slug",
                    focused: .name,
                    monospaced: true
                )

                if showNameError, case .failure(let error) = nameValidation {
                    Text(error.errorDescription ?? "Invalid project name.")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Letters, numbers, hyphens, underscores, or dots.")
                        .font(.caption)
                        .foregroundStyle(ghosttyTheme.tertiaryText)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("PROJECT LOCATION")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ghosttyTheme.tertiaryText)
                    .tracking(0.4)

                HStack(spacing: 8) {
                    softPlaceholderField(
                        text: $workspaces.createDraftPrefix,
                        placeholder: "Optional — Workspaces Root if empty"
                    )

                    Button("Browse…") {
                        browseLocation()
                    }
                }

                Text(workspaces.workspacesRoot)
                    .font(.caption.monospaced())
                    .foregroundStyle(ghosttyTheme.tertiaryText.opacity(0.75))
            }
        }
    }

    /// macOS ignores muted `prompt:` colors on plain fields — paint our own ghost hint.
    @ViewBuilder
    private func softPlaceholderField(
        text: Binding<String>,
        placeholder: String,
        focused: Field? = nil,
        monospaced: Bool = false
    ) -> some View {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(monospaced ? .body.monospaced() : .body)
                    .foregroundStyle(ghosttyTheme.tertiaryText.opacity(0.38))
                    .padding(.horizontal, 8)
                    .allowsHitTesting(false)
            }

            Group {
                if let focused {
                    TextField("", text: text)
                        .font(monospaced ? .body.monospaced() : .body)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .focused($focusedField, equals: focused)
                        .autocorrectionDisabled()
                } else {
                    TextField("", text: text)
                        .font(monospaced ? .body.monospaced() : .body)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .autocorrectionDisabled()
                }
            }
        }
        .background(ghosttyTheme.control)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var statusPreview: some View {
        let folder: String = {
            if case .success(let slug) = nameValidation { return slug }
            let trimmed = workspaces.createDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "…" : trimmed
        }()
        let parent = workspaces.createDraftPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = parent.isEmpty ? workspaces.workspacesRoot : parent
        let parsedURL: GitRemoteURL.Parsed? = {
            guard isRemote, case .success(let parsed) = urlValidation else { return nil }
            return parsed
        }()
        let clone = parsedURL != nil
        let protocolLabel: String = {
            guard let parsedURL else { return isRemote ? "REMOTE" : "LOCAL" }
            switch parsedURL.kind {
            case .https: return "HTTPS"
            case .http: return "HTTP"
            case .ssh: return "SSH"
            case .git: return "GIT"
            }
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(protocolLabel)
                    .font(.caption2.weight(.bold))
                    .tracking(0.4)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .foregroundStyle(clone ? ghosttyTheme.accent : ghosttyTheme.secondaryText)
                    .background(
                        (clone ? ghosttyTheme.accent : ghosttyTheme.secondaryText).opacity(0.18)
                    )
                    .clipShape(Capsule())

                Text(
                    clone
                        ? "Main will be cloned from the remote"
                        : (isRemote ? "Waiting for a valid repository URL…" : "Empty Main via git init")
                )
                .font(.caption)
                .foregroundStyle(ghosttyTheme.secondaryText)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ghosttyTheme.sidebar.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(ghosttyTheme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(root)/\(folder)/")
                    .font(.caption.monospaced())
                    .foregroundStyle(ghosttyTheme.foreground)
                Text(clone ? "Main ← \(parsedURL!.normalized)" : "Main ← git init (empty)")
                    .font(.caption.monospaced())
                    .foregroundStyle(ghosttyTheme.secondaryText)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ghosttyTheme.sidebar.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(ghosttyTheme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if !workspaces.workspaces.isEmpty {
                Button("Cancel") {
                    workspaces.cancelCreateWorkspace()
                }
                .buttonStyle(.bordered)
            }

            Button(isRemote && setupReady ? "Clone project" : "Create project") {
                submit()
            }
            .buttonStyle(.borderedProminent)
            .tint(ghosttyTheme.accent)
            .disabled(!canCreate)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func setSource(_ source: CreateProjectSource) {
        guard workspaces.createDraftSource != source else { return }
        workspaces.createDraftSource = source
        if source == .local {
            workspaces.createDraftCloneURL = ""
            nameTouched = false
        } else {
            nameTouched = false
            workspaces.createDraftName = ""
        }
        workspaces.lastError = nil
    }

    private func submit() {
        guard canCreate else { return }
        if isRemote, case .success(let parsed) = urlValidation {
            workspaces.createDraftCloneURL = parsed.normalized
        }
        workspaces.confirmCreateWorkspace()
    }

    private func browseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a project location"

        let expanded = SymphoniaPaths.expandingTildeInPath(workspaces.createDraftPrefix)
        if !workspaces.createDraftPrefix.isEmpty,
           FileManager.default.fileExists(atPath: expanded.path) {
            panel.directoryURL = expanded
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspaces.createDraftPrefix = DirectoryPathField.displayPath(for: url)
    }

    private func suggestedSlug(from url: String) -> String? {
        var cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.lowercased().hasSuffix(".git") {
            cleaned = String(cleaned.dropLast(4))
        }
        if cleaned.contains("@"), let colon = cleaned.lastIndex(of: ":") {
            let path = cleaned[cleaned.index(after: colon)...]
            return path.split(separator: "/").last.map(String.init)
        }
        return cleaned.split(separator: "/").last.map(String.init)
    }
}

/// Read-only Main-canvas terminal while `git clone` / `git init` runs for a new Project.
struct CreateProjectBootstrapPane: View {
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var worktrees: WorktreeController
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    let session: CreateBootstrapSession

    var body: some View {
        VStack(spacing: 0) {
            header
            SoftHairline(horizontalPadding: 12)
            TerminalSurfaceView(
                workingDirectory: session.workingDirectory,
                command: session.command,
                spawnEnvironment: CLISpawnEnvironment.mergingSecrets([]),
                isActive: session.awaitingContinue,
                isReadOnly: true,
                onChildExited: { exitCode in
                    handleChildExited(exitCode)
                },
                onContinueKey: session.awaitingContinue ? { openMainCLI() } : nil
            )
            .id(session.viewIdentity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SoftHairline(horizontalPadding: 12)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ghosttyTheme.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.failed ? "Setup failed" : session.title)
                    .font(.headline)
                    .foregroundStyle(ghosttyTheme.foreground)
                Text(session.summary.slug)
                    .font(.caption.monospaced())
                    .foregroundStyle(ghosttyTheme.secondaryText)
            }
            Spacer(minLength: 8)
            if session.awaitingContinue {
                Text("Press any key")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ghosttyTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ghosttyTheme.accent.opacity(0.15))
                    .clipShape(Capsule())
            } else if !session.failed {
                Text("Read-only")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ghosttyTheme.sidebar.opacity(0.7))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if session.failed {
                if let code = session.exitCode {
                    Text("git exited with \(code)")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let error = workspaces.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 8)
                Button("Cancel") {
                    workspaces.cancelCreateWorkspace()
                }
                .buttonStyle(.bordered)
                Button("Retry") {
                    workspaces.retryCreateBootstrap()
                }
                .buttonStyle(.borderedProminent)
                .tint(ghosttyTheme.accent)
            } else if session.awaitingContinue {
                Text("Press any key to open Main CLI")
                    .font(.caption)
                    .foregroundStyle(ghosttyTheme.secondaryText)
                Spacer(minLength: 8)
                Button("Open Main CLI") {
                    openMainCLI()
                }
                .buttonStyle(.borderedProminent)
                .tint(ghosttyTheme.accent)
                .keyboardShortcut(.defaultAction)
            } else {
                Text("Running setup…")
                    .font(.caption)
                    .foregroundStyle(ghosttyTheme.secondaryText)
                Spacer(minLength: 8)
                Button("Cancel") {
                    workspaces.cancelCreateWorkspace()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func handleChildExited(_ exitCode: UInt32) {
        if exitCode == 0 {
            workspaces.markCreateBootstrapReady()
        } else {
            workspaces.markCreateBootstrapFailed(exitCode: exitCode)
        }
    }

    private func openMainCLI() {
        workspaces.finishCreateBootstrap()
        if let current = workspaces.current {
            worktrees.focusMain(for: current)
        }
    }
}
