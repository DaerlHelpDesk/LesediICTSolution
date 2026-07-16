const SUPABASE_URL = 'https://aeyzzztyfawavsoupitk.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_yitlzLZCQL4BLZqZ41li4Q_Oc1LHHIx';

async function supabaseRequest(path, options = {}) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...options,
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${SUPABASE_PUBLISHABLE_KEY}`,
      ...options.headers
    }
  });
  if (!response.ok) throw new Error(await response.text());

  const body = await response.text();
  return body ? JSON.parse(body) : null;
}
