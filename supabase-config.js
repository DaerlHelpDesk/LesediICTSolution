const SUPABASE_URL = 'https://aeyzzztyfawavsoupitk.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_yitlzLZCQL4BLZqZ41li4Q_Oc1LHHIx';

async function supabaseRequest(path, options = {}) {
  const url = `${SUPABASE_URL}/rest/v1/${path}`;
  const headers = {
    apikey: SUPABASE_PUBLISHABLE_KEY,
    // Do not force a default Authorization header here. If the caller
    // provides an Authorization (e.g. a logged-in user's access token),
    // let it win by spreading after. If none is provided, requests will
    // still include the public apikey which is appropriate for anonymous
    // REST calls.
    ...options.headers
  };

  let response;
  try {
    response = await fetch(url, { ...options, headers });
  } catch (networkError) {
    console.error('Network error when calling Supabase REST:', networkError);
    throw new Error('Network error communicating with Supabase');
  }

  const text = await response.text();
  if (!response.ok) {
    console.error('Supabase REST error', { path, status: response.status, body: text });
    throw new Error(text || `Supabase request failed with status ${response.status}`);
  }

  return text ? JSON.parse(text) : null;
}
