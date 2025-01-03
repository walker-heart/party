import SwiftUI

struct AttendeeListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var partyManager: PartyManager
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingAddAttendee = false
    @State private var showingSettings = false
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var searchText = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showingDeleteConfirmation = false
    @State private var attendeeToDelete: Attendee?
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background(colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Party Info Header
                    PartyHeaderView(party: partyManager.currentParty)
                    
                    // Search Bar
                    SearchBarView(searchText: $searchText)
                    
                    // Attendee List
                    AttendeeListContentView(
                        attendees: partyManager.searchAttendees(query: searchText),
                        isAdmin: authManager.currentUser?.isAdmin == true,
                        creatorId: partyManager.currentParty?.creatorId,
                        userId: authManager.currentUser?.id,
                        editors: partyManager.currentParty?.editors ?? [],
                        onDelete: { attendee in
                            attendeeToDelete = attendee
                            showingDeleteConfirmation = true
                        },
                        onTogglePresence: { attendee in
                            Task {
                                do {
                                    try await partyManager.updateAttendanceStatus(
                                        for: attendee.id,
                                        isPresent: !attendee.isPresent
                                    )
                                } catch {
                                    print("Error updating attendance: \(error.localizedDescription)")
                                }
                            }
                        }
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: Theme.Spacing.medium) {
                        if let party = partyManager.currentParty,
                           let userId = authManager.currentUser?.id {
                            // URL Button - only for creators and admins
                            if party.creatorId == userId || authManager.currentUser?.isAdmin == true {
                                Button(action: {
                                    let shortId = String(party.creatorId.prefix(6))
                                    let formattedName = party.name.lowercased().replacingOccurrences(of: " ", with: "%20")
                                    let urlString = "https://wplister.replit.app/\(shortId)/\(formattedName)"
                                    if let url = URL(string: urlString) {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Image(systemName: "tray.and.arrow.down")
                                        .foregroundColor(Theme.Colors.primary)
                                }
                            }
                            
                            // Settings and Add buttons - for creators, admins, and editors
                            if party.creatorId == userId || authManager.currentUser?.isAdmin == true || party.editors.contains(userId) {
                                Button(action: { showingSettings = true }) {
                                    Image(systemName: "gear")
                                        .foregroundColor(Theme.Colors.primary)
                                }
                                
                                Button(action: { showingAddAttendee = true }) {
                                    Image(systemName: "person.badge.plus")
                                        .foregroundColor(Theme.Colors.primary)
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddAttendee) {
                AddAttendeeView(
                    isShowing: $showingAddAttendee,
                    firstName: $firstName,
                    lastName: $lastName,
                    showError: $showError,
                    errorMessage: $errorMessage,
                    isLoading: $isLoading,
                    onAdd: addAttendee
                )
            }
            .sheet(isPresented: $showingSettings) {
                PartySettingsView()
            }
            .alert("Delete Attendee", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let attendee = attendeeToDelete {
                        Task {
                            try? await partyManager.removeAttendee(attendee.id)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let attendee = attendeeToDelete {
                    Text("Are you sure you want to remove \(attendee.firstName) \(attendee.lastName) from the party?")
                }
            }
        }
    }
    
    private func addAttendee() {
        guard !firstName.isEmpty else {
            showError = true
            errorMessage = "Please enter a first name"
            return
        }
        
        guard !lastName.isEmpty else {
            showError = true
            errorMessage = "Please enter a last name"
            return
        }
        
        isLoading = true
        showError = false
        
        Task {
            do {
                try await partyManager.addAttendee(firstName: firstName, lastName: lastName)
                showingAddAttendee = false
                firstName = ""
                lastName = ""
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Subviews

private struct PartyHeaderView: View {
    let party: Party?
    @State private var showingPresentList = false
    @State private var showingAbsentList = false
    @EnvironmentObject private var partyManager: PartyManager
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        if let party = party {
            VStack(spacing: Theme.Spacing.small) {
                Text(party.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                
                Text("Passcode: \(party.passcode)")
                    .font(.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                
                HStack(spacing: Theme.Spacing.large) {
                    Button {
                        showingPresentList = true
                    } label: {
                        VStack {
                            Text("\(party.attendees.filter(\.isPresent).count)")
                                .font(.headline)
                                .foregroundColor(Theme.Colors.success)
                            Text("Present")
                                .font(.caption)
                                .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                        }
                    }
                    
                    Button {
                        showingAbsentList = true
                    } label: {
                        VStack {
                            Text("\(party.attendees.filter { !$0.isPresent }.count)")
                                .font(.headline)
                                .foregroundColor(Theme.Colors.error)
                            Text("Absent")
                                .font(.caption)
                                .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                        }
                    }
                }
                .padding(.top, Theme.Spacing.small)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.Colors.surfaceLight(colorScheme))
            .cornerRadius(Theme.CornerRadius.medium)
            .sheet(isPresented: $showingPresentList) {
                FilteredAttendeeListView(
                    attendees: party.attendees.filter(\.isPresent),
                    isPresent: true,
                    isAdmin: authManager.currentUser?.isAdmin == true,
                    creatorId: party.creatorId,
                    userId: authManager.currentUser?.id,
                    editors: party.editors,
                    onDelete: { attendee in
                        Task {
                            try? await partyManager.removeAttendee(attendee.id)
                        }
                    },
                    onTogglePresence: { attendee in
                        Task {
                            try? await partyManager.updateAttendanceStatus(
                                for: attendee.id,
                                isPresent: !attendee.isPresent
                            )
                        }
                    }
                )
            }
            .sheet(isPresented: $showingAbsentList) {
                FilteredAttendeeListView(
                    attendees: party.attendees.filter { !$0.isPresent },
                    isPresent: false,
                    isAdmin: authManager.currentUser?.isAdmin == true,
                    creatorId: party.creatorId,
                    userId: authManager.currentUser?.id,
                    editors: party.editors,
                    onDelete: { attendee in
                        Task {
                            try? await partyManager.removeAttendee(attendee.id)
                        }
                    },
                    onTogglePresence: { attendee in
                        Task {
                            try? await partyManager.updateAttendanceStatus(
                                for: attendee.id,
                                isPresent: !attendee.isPresent
                            )
                        }
                    }
                )
            }
        }
    }
}

private struct SearchBarView: View {
    @Binding var searchText: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.Colors.textSecondary(colorScheme))
            
            TextField("", text: $searchText)
                .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                .accentColor(Theme.Colors.primary)
                .textFieldStyle(.plain)
                .placeholder(when: searchText.isEmpty) {
                    Text("Search attendees")
                        .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                }
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                }
            }
        }
        .padding()
        .background(Theme.Colors.surfaceLight(colorScheme))
        .cornerRadius(Theme.CornerRadius.medium)
    }
}

private struct AttendeeListContentView: View {
    let attendees: [Attendee]
    let isAdmin: Bool
    let creatorId: String?
    let userId: String?
    let editors: [String]
    let onDelete: (Attendee) -> Void
    let onTogglePresence: (Attendee) -> Void
    
    var canDeleteAttendees: Bool {
        isAdmin || creatorId == userId || (userId != nil && editors.contains(userId!))
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.small) {
                ForEach(attendees) { attendee in
                    AttendeeRowView(
                        attendee: attendee,
                        canDelete: canDeleteAttendees,
                        onDelete: { onDelete(attendee) },
                        onTogglePresence: { onTogglePresence(attendee) }
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

private struct AttendeeDetailsView: View {
    let attendee: Attendee
    let canEdit: Bool
    @Binding var isShowing: Bool
    @EnvironmentObject private var partyManager: PartyManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var isEditing = false
    @State private var firstName: String
    @State private var lastName: String
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    init(attendee: Attendee, canEdit: Bool, isShowing: Binding<Bool>) {
        self.attendee = attendee
        self.canEdit = canEdit
        self._isShowing = isShowing
        self._firstName = State(initialValue: attendee.firstName)
        self._lastName = State(initialValue: attendee.lastName)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background(colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: Theme.Spacing.large) {
                    VStack(alignment: .center, spacing: Theme.Spacing.medium) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(Theme.Colors.primary)
                        
                        if isEditing {
                            VStack(spacing: Theme.Spacing.medium) {
                                AppTextField(placeholder: "First Name", text: $firstName)
                                AppTextField(placeholder: "Last Name", text: $lastName)
                            }
                            .padding(.horizontal)
                        } else {
                            Text("\(attendee.firstName) \(attendee.lastName)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                        }
                    }
                    .padding(.bottom, Theme.Spacing.large)
                    
                    if showError {
                        Text(errorMessage)
                            .foregroundColor(Theme.Colors.error)
                            .font(.caption)
                    }
                    
                    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                        DetailRow(title: "Status", value: attendee.isPresent ? "Present" : "Absent")
                        DetailRow(title: "Added", value: attendee.createdAt.formatted(date: .long, time: .shortened))
                        DetailRow(title: "Last Updated", value: attendee.updatedAt.formatted(date: .long, time: .shortened))
                        DetailRow(title: "Add Method", value: attendee.addMethod)
                    }
                    .padding()
                    .background(Theme.Colors.surfaceLight(colorScheme))
                    .cornerRadius(Theme.CornerRadius.medium)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Attendee Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isEditing ? "Cancel" : "Done") {
                        if isEditing {
                            // Reset fields and exit edit mode
                            firstName = attendee.firstName
                            lastName = attendee.lastName
                            isEditing = false
                        } else {
                            isShowing = false
                        }
                    }
                    .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                }
                
                if canEdit {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isEditing {
                            Button(action: saveChanges) {
                                if isLoading {
                                    ProgressView()
                                        .tint(Theme.Colors.primary)
                                } else {
                                    Text("Save")
                                        .foregroundColor(Theme.Colors.primary)
                                }
                            }
                            .disabled(isLoading)
                        } else {
                            Button("Edit") {
                                isEditing = true
                            }
                            .foregroundColor(Theme.Colors.primary)
                        }
                    }
                }
            }
        }
    }
    
    private func saveChanges() {
        guard !firstName.isEmpty else {
            showError = true
            errorMessage = "Please enter a first name"
            return
        }
        
        guard !lastName.isEmpty else {
            showError = true
            errorMessage = "Please enter a last name"
            return
        }
        
        isLoading = true
        showError = false
        
        Task {
            do {
                try await partyManager.updateAttendeeName(
                    attendeeId: attendee.id,
                    firstName: firstName,
                    lastName: lastName
                )
                isEditing = false
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(Theme.Colors.textSecondary(colorScheme))
            
            Text(value)
                .font(.body)
                .foregroundColor(Theme.Colors.textPrimary(colorScheme))
        }
    }
}

private struct AttendeeRowView: View {
    let attendee: Attendee
    let canDelete: Bool
    let onDelete: () -> Void
    let onTogglePresence: () -> Void
    @State private var showingDetails = false
    @EnvironmentObject private var partyManager: PartyManager
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.colorScheme) private var colorScheme
    
    private var canModifyAttendance: Bool {
        if let userId = authManager.currentUser?.id,
           let party = partyManager.currentParty {
            return party.creatorId == userId || 
                   authManager.currentUser?.isAdmin == true || 
                   party.editors.contains(userId)
        }
        return false
    }
    
    var body: some View {
        HStack {
            // Attendee Info
            VStack(alignment: .leading, spacing: Theme.Spacing.tiny) {
                Text("\(attendee.firstName) \(attendee.lastName)")
                    .font(.headline)
                    .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                
                Text(attendee.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(Theme.Colors.textSecondary(colorScheme))
            }
            .onTapGesture {
                showingDetails = true
            }
            
            Spacer()
            
            // Status Badge (only tappable for authorized users)
            StatusBadge(isPresent: attendee.isPresent)
                .onTapGesture {
                    if canModifyAttendance {
                        onTogglePresence()
                    }
                }
            
            // Delete Button
            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(Theme.Colors.error)
                }
                .padding(.leading, Theme.Spacing.medium)
            }
        }
        .padding()
        .background(Theme.Colors.surfaceLight(colorScheme))
        .cornerRadius(Theme.CornerRadius.medium)
        .sheet(isPresented: $showingDetails) {
            AttendeeDetailsView(
                attendee: attendee,
                canEdit: canDelete,
                isShowing: $showingDetails
            )
        }
        .contextMenu {
            if canModifyAttendance {
                Button(action: onTogglePresence) {
                    Label(
                        attendee.isPresent ? "Mark as Absent" : "Mark as Present",
                        systemImage: attendee.isPresent ? "person.fill.xmark" : "person.fill.checkmark"
                    )
                }
            }
            
            Button(action: { showingDetails = true }) {
                Label("View Details", systemImage: "info.circle")
            }
            
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

private struct AddAttendeeView: View {
    @Binding var isShowing: Bool
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var showError: Bool
    @Binding var errorMessage: String
    @Binding var isLoading: Bool
    @Environment(\.colorScheme) private var colorScheme
    let onAdd: () -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background(colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: Theme.Spacing.large) {
                    AppTextField(placeholder: "First Name", text: $firstName)
                    AppTextField(placeholder: "Last Name", text: $lastName)
                    
                    if showError {
                        Text(errorMessage)
                            .foregroundColor(Theme.Colors.error)
                            .font(.caption)
                    }
                    
                    PrimaryButton(
                        title: "Add Attendee",
                        action: onAdd,
                        isLoading: isLoading
                    )
                }
                .padding()
            }
            .navigationTitle("Add Attendee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isShowing = false
                        firstName = ""
                        lastName = ""
                    }
                    .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                }
            }
        }
    }
}

private struct PartySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var partyManager: PartyManager
    @EnvironmentObject private var authManager: AuthManager
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showingAddEditor = false
    @State private var editorEmail = ""
    @State private var isLoading = false
    @State private var editorUsers: [String: User] = [:]  // Cache for editor user info
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background(colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.large) {
                        if let party = partyManager.currentParty {
                            // Party Info
                            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                                DetailRow(title: "Party Name", value: party.name)
                                DetailRow(title: "Passcode", value: party.passcode)
                                DetailRow(title: "Created", value: party.createdAt.formatted(date: .long, time: .shortened))
                                DetailRow(title: "Total Attendees", value: "\(party.attendees.count)")
                                DetailRow(title: "Present", value: "\(party.attendees.filter(\.isPresent).count)")
                            }
                            .padding()
                            .background(Theme.Colors.surfaceLight(colorScheme))
                            .cornerRadius(Theme.CornerRadius.medium)
                            
                            // Event Managers Section (visible to creator and admin)
                            if authManager.currentUser?.id == party.creatorId || authManager.currentUser?.isAdmin == true {
                                VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                                    Text("Event Managers")
                                        .font(.headline)
                                        .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                                    
                                    ForEach(party.editors, id: \.self) { editorId in
                                        HStack {
                                            if let user = editorUsers[editorId] {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("\(user.firstName) \(user.lastName)")
                                                        .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                                                    Text(user.email)
                                                        .font(.caption)
                                                        .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                                                }
                                            } else {
                                                Text("Loading...")
                                                    .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                                                    .onAppear {
                                                        // Fetch user info when row appears
                                                        Task {
                                                            if let user = try? await authManager.getUserById(editorId) {
                                                                editorUsers[editorId] = user
                                                            }
                                                        }
                                                    }
                                            }
                                            
                                            Spacer()
                                            
                                            if editorId != party.creatorId {
                                                Button(action: {
                                                    Task {
                                                        try? await partyManager.removeEditor(editorId)
                                                    }
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(Theme.Colors.error)
                                                }
                                            } else {
                                                Text("Creator")
                                                    .font(.caption)
                                                    .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Theme.Colors.surfaceLight(colorScheme))
                                                    .cornerRadius(Theme.CornerRadius.small)
                                            }
                                        }
                                        .padding()
                                        .background(Theme.Colors.surfaceLight(colorScheme))
                                        .cornerRadius(Theme.CornerRadius.medium)
                                    }
                                    
                                    Button(action: { showingAddEditor = true }) {
                                        HStack {
                                            Image(systemName: "person.badge.plus")
                                            Text("Add Manager")
                                        }
                                        .foregroundColor(Theme.Colors.primary)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Theme.Colors.surfaceLight(colorScheme))
                                        .cornerRadius(Theme.CornerRadius.medium)
                                    }
                                }
                                .padding()
                                .background(Theme.Colors.surfaceLight(colorScheme))
                                .cornerRadius(Theme.CornerRadius.medium)
                            }
                            
                            // Delete Party Button (visible to creator and admin)
                            if authManager.currentUser?.id == party.creatorId || authManager.currentUser?.isAdmin == true {
                                Button(action: {
                                    Task {
                                        do {
                                            try await partyManager.deleteParty(party.id)
                                            await authManager.removePartyFromActive(party.id)
                                            dismiss()
                                        } catch {
                                            showError = true
                                            errorMessage = error.localizedDescription
                                        }
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Delete Party")
                                    }
                                    .foregroundColor(Theme.Colors.error)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Theme.Colors.surfaceLight(colorScheme))
                                    .cornerRadius(Theme.CornerRadius.medium)
                                }
                            }
                            
                            // Leave Party Button (visible to editors who are not the creator)
                            if let userId = authManager.currentUser?.id,
                               party.editors.contains(userId),
                               userId != party.creatorId,
                               authManager.currentUser?.isAdmin != true {
                                Button(action: {
                                    Task {
                                        do {
                                            try await partyManager.removeEditor(userId)
                                            await authManager.removePartyFromActive(party.id)
                                            dismiss()
                                        } catch {
                                            showError = true
                                            errorMessage = error.localizedDescription
                                        }
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "rectangle.portrait.and.arrow.right")
                                        Text("Leave Party")
                                    }
                                    .foregroundColor(Theme.Colors.error)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Theme.Colors.surfaceLight(colorScheme))
                                    .cornerRadius(Theme.CornerRadius.medium)
                                }
                            }
                        }
                        
                        if showError {
                            Text(errorMessage)
                                .foregroundColor(Theme.Colors.error)
                                .font(.caption)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Party Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                }
            }
            .sheet(isPresented: $showingAddEditor) {
                NavigationView {
                    ZStack {
                        Theme.Colors.background(colorScheme)
                            .ignoresSafeArea()
                        
                        VStack(spacing: Theme.Spacing.large) {
                            AppTextField(placeholder: "Email", text: $editorEmail)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                            
                            if showError {
                                Text(errorMessage)
                                    .foregroundColor(Theme.Colors.error)
                                    .font(.caption)
                            }
                            
                            PrimaryButton(
                                title: "Add Manager",
                                action: addEditor,
                                isLoading: isLoading
                            )
                        }
                        .padding()
                    }
                    .navigationTitle("Add Manager")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showingAddEditor = false
                                editorEmail = ""
                            }
                            .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                        }
                    }
                }
            }
        }
        .task {
            // Load all editor user info when view appears
            if let party = partyManager.currentParty {
                for editorId in party.editors {
                    if editorUsers[editorId] == nil {
                        if let user = try? await authManager.getUserById(editorId) {
                            editorUsers[editorId] = user
                        }
                    }
                }
            }
        }
    }
    
    private func addEditor() {
        guard !editorEmail.isEmpty else {
            showError = true
            errorMessage = "Please enter an email"
            return
        }
        
        isLoading = true
        showError = false
        
        Task {
            do {
                // First, find the user by email
                if let userId = try await authManager.getUserIdByEmail(editorEmail) {
                    try await partyManager.addEditor(userId)
                    showingAddEditor = false
                    editorEmail = ""
                } else {
                    showError = true
                    errorMessage = "User not found"
                }
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

private struct FilteredAttendeeListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let attendees: [Attendee]
    let isPresent: Bool
    let isAdmin: Bool
    let creatorId: String?
    let userId: String?
    let editors: [String]
    let onDelete: (Attendee) -> Void
    let onTogglePresence: (Attendee) -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background(colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.small) {
                            ForEach(attendees) { attendee in
                                AttendeeRowView(
                                    attendee: attendee,
                                    canDelete: isAdmin || creatorId == userId || (userId != nil && editors.contains(userId!)),
                                    onDelete: { onDelete(attendee) },
                                    onTogglePresence: { onTogglePresence(attendee) }
                                )
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle(isPresent ? "Present Attendees" : "Absent Attendees")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        AttendeeListView()
            .environmentObject(PartyManager.preview)
            .environmentObject(AuthManager())
    }
} 
