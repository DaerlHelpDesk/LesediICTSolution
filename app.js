async function sendRequest(event) {
  event.preventDefault();

  const form = event.currentTarget;
  const button = form.querySelector('button[type="submit"]');
  const status = document.getElementById('requestStatus');
  const originalLabel = button.textContent;
  const ticket = `LES-${Date.now().toString(36).toUpperCase()}-${Math.floor(Math.random() * 900 + 100)}`;
  document.getElementById('ticketNumber').value = ticket;

  button.disabled = true;
  button.textContent = 'Sending request...';
  status.className = 'request-status';
  status.textContent = '';

  try {
    const data = Object.fromEntries(new FormData(form));
    await supabaseRequest('service_requests', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Prefer: 'return=minimal' },
      body: JSON.stringify({
        ticket_number: ticket,
        name: data.name,
        email: data.email,
        company: data.company || null,
        phone: data.phone || null,
        preferred_contact_time: data.preferred_contact_time,
        service: data.service,
        description: data.description
      })
    });
    await supabaseRequest('ticket_statuses', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Prefer: 'return=minimal' },
      body: JSON.stringify({ ticket_number: ticket, service: data.service, status: 'Request received' })
    });

    // Send the technician an email copy without taking the visitor away from the page.
    // The ticket remains saved in Supabase even if the email provider is temporarily unavailable.
    try {
      const emailResponse = await fetch('https://formsubmit.co/ajax/ghavysa@gmail.com', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          _subject: `New ICT Service Request — ${ticket}`,
          ticket_number: ticket,
          name: data.name,
          email: data.email,
          company: data.company || 'Not provided',
          phone: data.phone || 'Not provided',
          preferred_contact_time: data.preferred_contact_time,
          service: data.service,
          description: data.description
        })
      });
      if (!emailResponse.ok) throw new Error('Email notification failed');
    } catch (emailError) {
      console.warn('The request was saved, but the email notification could not be sent.', emailError);
    }

    form.reset();
    status.classList.add('success');
    status.innerHTML = `Thanks! Your service request has been received. Your ticket number is <strong>${ticket}</strong>. Keep it for follow-up or <a href="status.html?ticket=${ticket}">check its status</a>.`;
  } catch (error) {
    status.classList.add('error');
    status.textContent = 'Your request could not be sent. Please try again or contact us by phone.';
  } finally {
    button.disabled = false;
    button.textContent = originalLabel;
  }
}

const estimateForm = document.getElementById('estimateForm');
if (estimateForm) {
  estimateForm.addEventListener('submit', (event) => {
    event.preventDefault();
    const service = document.getElementById('serviceType').value;
    const size = Number(document.getElementById('teamSize').value);
    const urgency = Number(document.getElementById('urgency').value);
    const basePrices = { 'Website Development': 5500, 'Azure Cloud': 4200, Networking: 2500, Security: 3200 };
    const base = basePrices[service] || 1800;
    const sizeMultiplier = [0, 1, 1.35, 1.7][size];
    const urgencyMultiplier = [0, 1, 1.2, 1.4][urgency];
    document.getElementById('quoteResult').textContent = `Estimated starting cost for ${service}: R${Math.round(base * sizeMultiplier * urgencyMultiplier)}`;
  });
}

document.querySelectorAll('.faq-item').forEach((item) => {
  item.querySelector('.faq-question').addEventListener('click', () => {
    document.querySelectorAll('.faq-item').forEach((faq) => faq.classList.remove('active'));
    item.classList.add('active');
  });
});
