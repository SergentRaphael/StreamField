// Comptes StreamField (synchro entre appareils) — projet Supabase.
// Supabase → Project Settings → API Keys : « Project URL » et clé « publishable » (ou « anon »).
// Cette clé est faite pour être dans l'app : les données restent protégées par les règles
// de sécurité (RLS) de supabase/schema.sql. Ne jamais mettre la clé « secret » / « service_role ».
// Laisser vide = l'app fonctionne normalement, sans comptes.
const kSupabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const kSupabaseKey = String.fromEnvironment('SUPABASE_KEY', defaultValue: '');
