const SECRET_PROPERTY = 'SHARED_SECRET';
const LINK_BASE_PROPERTY = 'ACTIVATION_LINK_BASE';
const SENDER_NAME_PROPERTY = 'SENDER_NAME';

function doPost(e) {
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return respond_({ status: 'error', message: 'Empty request.' });
    }

    let body;
    try {
      body = JSON.parse(e.postData.contents);
    } catch (err) {
      return respond_({ status: 'error', message: 'Invalid JSON.' });
    }

    const expected = PropertiesService
      .getScriptProperties()
      .getProperty(SECRET_PROPERTY);

    if (!expected || !timingSafeEqual_(String(body.secret || ''), expected)) {
      return respond_({ status: 'error', message: 'Unauthorized.' });
    }

    const action = String(body.action || '').trim().toLowerCase();
    if (action !== 'activation') {
      return respond_({ status: 'error', message: 'Unknown action.' });
    }

    const email = String(body.email || '').trim().toLowerCase();
    const token = String(body.token || '').trim().toLowerCase();

    if (!isEmail_(email)) {
      return respond_({ status: 'error', message: 'A valid email is required.' });
    }
    if (!/^[0-9a-f]{64}$/.test(token)) {
      return respond_({ status: 'error', message: 'A valid activation token is required.' });
    }

    const props = PropertiesService.getScriptProperties();
    const linkBase = (props.getProperty(LINK_BASE_PROPERTY) || '').trim().replace(/\/+$/, '');
    const senderName = (props.getProperty(SENDER_NAME_PROPERTY) || 'TesterLoop').trim();

    if (!/^https:\/\//i.test(linkBase)) {
      return respond_({ status: 'error', message: 'ACTIVATION_LINK_BASE must start with https://.' });
    }

    const link = linkBase + '?token=' + encodeURIComponent(token);

    MailApp.sendEmail(email, 'Activate your TesterLoop account', plainBody_(link), {
      htmlBody: htmlBody_(email, link),
      name: senderName || 'TesterLoop',
    });

    return respond_({ status: 'ok', queued: true });
  } catch (err) {
    return respond_({
      status: 'error',
      message: String(err && err.message ? err.message : err),
    });
  }
}

function doGet() {
  return respond_({ status: 'ok', service: 'testerloop-account-activation' });
}

function testSend() {
  const props = PropertiesService.getScriptProperties();
  const email = (props.getProperty('TEST_EMAIL') || '').trim();
  if (!isEmail_(email)) {
    Logger.log('Set Script Property TEST_EMAIL to a real address first.');
    return;
  }

  const base = (props.getProperty(LINK_BASE_PROPERTY) || '').trim().replace(/\/+$/, '');
  if (!/^https:\/\//i.test(base)) {
    Logger.log('Set ACTIVATION_LINK_BASE to the activate-account function URL.');
    return;
  }

  const token = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  MailApp.sendEmail(email, 'Activate your TesterLoop account', plainBody_(base + '?token=' + token), {
    htmlBody: htmlBody_(email, base + '?token=' + token),
    name: (props.getProperty(SENDER_NAME_PROPERTY) || 'TesterLoop').trim(),
  });
  Logger.log('Test email sent to ' + email + '. The link token is not valid for activation.');
}

function plainBody_(link) {
  return [
    'Welcome to TesterLoop.',
    '',
    'Open this link to activate your account:',
    link,
    '',
    'The link expires in 24 hours and works once.',
    '',
    'If you did not create this account, ignore this email.',
    '',
    'TesterLoop',
  ].join('\n');
}

function htmlBody_(email, link) {
  return [
    '<div style="margin:0;padding:32px;background:#f7f4ed;font-family:Arial,Helvetica,sans-serif;color:#12211e;">',
    '<div style="max-width:520px;margin:0 auto;background:#fffdf8;border:1px solid #e3ded2;border-radius:16px;padding:28px;">',
    '<div style="font-size:12px;letter-spacing:0.16em;text-transform:uppercase;color:#0f766e;font-weight:700;">TesterLoop</div>',
    '<h1 style="font-size:24px;line-height:1.25;margin:14px 0 10px;">Activate your account</h1>',
    '<p style="font-size:15px;line-height:1.6;color:#5d6b67;margin:0 0 18px;">Confirm that this address belongs to you. This lets your developer or tester workspace open.</p>',
    '<p style="font-size:14px;line-height:1.6;margin:0 0 22px;"><strong>Account:</strong> ' + escapeHtml_(email) + '</p>',
    '<a href="' + escapeHtml_(link) + '" style="display:inline-block;background:#0f766e;color:#ffffff;text-decoration:none;font-weight:700;font-size:15px;padding:14px 24px;border-radius:999px;">Activate my account</a>',
    '<p style="font-size:12px;line-height:1.6;color:#7a8783;margin:22px 0 0;">The link expires in 24 hours and works once. If the button does not open, copy this address into your browser:</p>',
    '<p style="font-size:12px;line-height:1.6;color:#0f766e;word-break:break-all;margin:8px 0 0;">' + escapeHtml_(link) + '</p>',
    '<p style="font-size:12px;line-height:1.6;color:#7a8783;margin:18px 0 0;">If you did not create this account, ignore this email.</p>',
    '</div>',
    '</div>',
  ].join('');
}

function isEmail_(value) {
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value);
}

function escapeHtml_(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function timingSafeEqual_(left, right) {
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i++) {
    diff |= left.charCodeAt(i) ^ right.charCodeAt(i);
  }
  return diff === 0;
}

function respond_(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}
