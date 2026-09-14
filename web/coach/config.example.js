// Copy this file to `config.js` and fill in your Supabase project values.
//
// Both values below are *public*. The anon key is designed to ship in clients —
// every table the dashboard touches is protected by row-level security, and a coach
// can only ever read a client who has actively linked to them. It is still kept out
// of git, because the repo convention (see Config/KinetriqSecrets.xcconfig) is that
// project identifiers live outside version control.
//
// Never put the service-role key here. It bypasses RLS entirely and would let any
// visitor read every user's measurements.

window.KINETRIQ_CONFIG = {
  // Supabase → Project Settings → API → Project URL
  supabaseUrl: "https://YOUR-PROJECT-REF.supabase.co",

  // Supabase → Project Settings → API → Project API keys → anon / public
  supabaseAnonKey: "YOUR-ANON-KEY",

  // Optional. Shown on the sign-in screen so a coach can get the iOS app.
  appStoreURL: "",
};
