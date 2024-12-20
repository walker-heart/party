import SwiftUI

struct AttendeeListView: View {
    @EnvironmentObject private var partyManager: PartyManager
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingAddAttendee = false
    @State private var newFirstName = ""
    @State private var newLastName = ""
    @State private var errorMessage: String? = nil
    @State private var showingError = false
    @State private var showingDeleteConfirmation = false
    @State private var attendeeToDelete: Attendee? = nil
    
    var filteredAttendees: [Attendee] {
        partyManager.searchAttendees(query: searchText)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let party = partyManager.currentParty {
                // Party Info
                HStack {
                    Text(party.name)
                        .font(.headline)
                    Text("-")
                    Text(party.passcode)
                        .font(.headline)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("Here: \(party.attendees.filter(\.isPresent).count)")
                        .foregroundColor(.green)
                    Text("Away: \(party.attendees.filter { !$0.isPresent }.count)")
                        .foregroundColor(.red)
                }
                .padding(.vertical, 8)
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search attendees...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                
                // Attendee List
                List {
                    ForEach(filteredAttendees) { attendee in
                        Button(action: {
                            Task {
                                do {
                                    try await partyManager.updateAttendanceStatus(
                                        for: attendee.id,
                                        isPresent: !attendee.isPresent
                                    )
                                } catch {
                                    errorMessage = error.localizedDescription
                                    showingError = true
                                }
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(attendee.fullName)
                                        .font(.headline)
                                    Text("Added: \(attendee.createdAt.formatted(date: .abbreviated, time: .shortened)) via \(attendee.addMethod)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { attendee.isPresent },
                                    set: { newValue in
                                        Task {
                                            do {
                                                try await partyManager.updateAttendanceStatus(
                                                    for: attendee.id,
                                                    isPresent: newValue
                                                )
                                            } catch {
                                                errorMessage = error.localizedDescription
                                                showingError = true
                                            }
                                        }
                                    }
                                ))
                                
                                if authManager.currentUser?.isAdmin == true || 
                                   authManager.currentUser?.id == partyManager.currentParty?.creatorId {
                                    Button(action: {
                                        attendeeToDelete = attendee
                                        showingDeleteConfirmation = true
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                    .simultaneousGesture(TapGesture().onEnded {})
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(PlainListStyle())
                .navigationTitle(party.name)
                .navigationBarItems(
                    trailing: Button(action: { showingAddAttendee = true }) {
                        Image(systemName: "plus")
                    }
                )
                .sheet(isPresented: $showingAddAttendee) {
                    NavigationView {
                        Form {
                            Section(header: Text("Attendee Information")) {
                                TextField("First Name", text: $newFirstName)
                                    .textInputAutocapitalization(.words)
                                TextField("Last Name", text: $newLastName)
                                    .textInputAutocapitalization(.words)
                            }
                        }
                        .navigationTitle("Add Attendee")
                        .navigationBarItems(
                            leading: Button("Cancel") {
                                showingAddAttendee = false
                                resetFields()
                            },
                            trailing: Button("Add") {
                                addAttendee()
                            }
                            .disabled(newFirstName.isEmpty || newLastName.isEmpty)
                        )
                    }
                }
                .alert("Error", isPresented: $showingError, presenting: errorMessage) { _ in
                    Button("OK", role: .cancel) { }
                } message: { error in
                    Text(error)
                }
                .alert("Remove Attendee", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) {
                        attendeeToDelete = nil
                    }
                    Button("Remove", role: .destructive) {
                        if let attendee = attendeeToDelete {
                            Task {
                                do {
                                    try await partyManager.removeAttendee(attendee.id)
                                } catch {
                                    errorMessage = error.localizedDescription
                                    showingError = true
                                }
                            }
                        }
                        attendeeToDelete = nil
                    }
                } message: {
                    if let attendee = attendeeToDelete {
                        Text("Are you sure you want to remove \(attendee.fullName) from the party?")
                    }
                }
            } else {
                ProgressView()
                    .onAppear {
                        dismiss()
                    }
            }
        }
    }
    
    private func addAttendee() {
        Task {
            do {
                try await partyManager.addAttendee(firstName: newFirstName, lastName: newLastName)
                showingAddAttendee = false
                resetFields()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func resetFields() {
        newFirstName = ""
        newLastName = ""
    }
}

#Preview {
    NavigationView {
        AttendeeListView()
            .environmentObject(PartyManager.preview)
            .environmentObject(AuthManager())
    }
} 
