enum VersionPing: String, Sendable {
    case install
    case update

    /// A version change is an update even when the ping ID is new, so installs that never pinged before do not count as new.
    init?(pingIDIsNew: Bool, updatedFrom: String?) {
        if updatedFrom != nil {
            self = .update
        } else if pingIDIsNew {
            self = .install
        } else {
            return nil
        }
    }
}
