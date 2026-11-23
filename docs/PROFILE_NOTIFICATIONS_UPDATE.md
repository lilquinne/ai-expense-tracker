# Profile, startup and notification update

- Startup renders a Spendly loading screen before service initialization; login also hides its form while restoring the existing online session.
- Coach no longer repeats a consent modal before sending. Its existing in-page explanation of Groq processing remains visible.
- Profile removes IP location, currency selection and category management. Display currency is fixed to RM. About describes Groq assistance, local category learning and Google ML Kit OCR.
- Light/dark mode is saved in preferences. UI surfaces and text use a context-aware palette, preserving navigation and form state when the theme changes.
- Clear temporary cache clears in-memory images and generated OCR/report scratch folders older than a day. Camera files, saved receipt images, database records and recent reports are excluded. The storage figure is labelled Saved records because it measures the database.
- The notification bell matches the settings button dimensions. In-app alerts become read on opening the warning or its Send analytics action. Read state is scoped to user, month, category and threshold; crossing a new threshold is unread again.
- Budget analytics shows exact month/category expense totals, shop rankings, dates and saved notes. No missing item details are fabricated. A share button opens the phone share chooser for a text report.

Validation: full Flutter suite passed (64 tests), then two additional startup/Profile tests were added and all four focused Profile/alert tests passed, including a saved light-theme switch. Analyzer found no compile errors; existing style/deprecation notices remain. Android debug build verified before installation.
