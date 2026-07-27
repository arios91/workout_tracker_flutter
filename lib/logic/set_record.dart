/// One confirmed set, as displayed.
// Lives here, not in repositories/, so logic/ depends on nothing.
// repositories/records.dart re-exports it.
typedef SetRecord = ({int setNumber, double weight, int reps});
