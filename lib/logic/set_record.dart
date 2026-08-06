/// One confirmed set, as displayed.
// Lives here, not in repositories/, so logic/ depends on nothing.
// repositories/records.dart re-exports it.
// id addresses the row for edits; collapse ignores it.
typedef SetRecord = ({int id, int setNumber, double weight, int reps});
