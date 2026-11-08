const SECRET_PROPERTY = 'SHARED_SECRET';

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

    const groupEmail = String(body.group || '').trim().toLowerCase();
    const groupName = String(body.name || '').trim().toLowerCase();
    const memberEmail = String(body.email || '').trim().toLowerCase();
    const action = String(body.action || 'membership').trim().toLowerCase();

    if (!isEmail_(groupEmail)) {
      return respond_({ status: 'error', message: 'A group email is required.' });
    }
    if (!groupName || !isGroupName_(groupName)) {
      return respond_({
        status: 'error',
        message: 'The group name is not a valid Google Groups URL name.',
      });
    }

    if (action !== 'membership') {
      return respond_({ status: 'error', message: 'Unknown action.' });
    }

    if (!isEmail_(memberEmail)) {
      return respond_({ status: 'error', message: 'A member email is required.' });
    }

    let group;
    try {
      group = GroupsApp.getGroupByEmail(groupEmail);
    } catch (err) {
      return respond_({
        status: 'error',
        code: 'group_unavailable',
        message: 'The Google Group checker cannot read ' + groupEmail + '. Confirm the script account owns or can see the group and try again.',
      });
    }

    let active = false;
    try {
      active = group.hasUser(memberEmail);
    } catch (err) {
      return respond_({
        status: 'error',
        code: 'group_unavailable',
        message: 'The Google Group checker cannot read ' + groupEmail + '. Confirm the script account owns or can see the group and try again.',
      });
    }

    return respond_({
      status: active ? 'active' : 'inactive',
      group: groupEmail,
      name: groupName,
    });
  } catch (err) {
    return respond_({
      status: 'error',
      message: String(err && err.message ? err.message : err),
    });
  }
}

function doGet() {
  return respond_({ status: 'ok', service: 'testerloop-group-check' });
}

function testMembership() {
  const props = PropertiesService.getScriptProperties();
  const groupEmail = (props.getProperty('TEST_GROUP_EMAIL') || '').trim().toLowerCase();
  const memberEmail = (props.getProperty('TEST_MEMBER_EMAIL') || '').trim().toLowerCase();

  try {
    Logger.log('Active user: ' + Session.getActiveUser().getEmail());
  } catch (err) {
    Logger.log('Active user: unavailable');
  }
  try {
    Logger.log('Effective user: ' + Session.getEffectiveUser().getEmail());
  } catch (err) {
    Logger.log('Effective user: unavailable');
  }

  try {
    const groups = GroupsApp.getGroups();
    Logger.log('Groups visible to this account: ' + groups.length);
    groups.slice(0, 20).forEach(function (g) {
      try {
        Logger.log('  - ' + g.getEmail());
      } catch (e) {
        Logger.log('  - [unreadable]');
      }
    });
  } catch (err) {
    Logger.log('Could not list groups: ' + (err.message || err));
    Logger.log('Tip: the executing account may not have permission to list groups.');
  }

  if (!groupEmail) {
    Logger.log('Set Script Property TEST_GROUP_EMAIL to a group this account can see (Project Settings > Script Properties).');
    return;
  }
  if (!isEmail_(groupEmail)) {
    Logger.log('TEST_GROUP_EMAIL is not a valid email.');
    return;
  }
  if (memberEmail && !isEmail_(memberEmail)) {
    Logger.log('TEST_MEMBER_EMAIL is not a valid email.');
    return;
  }

  try {
    const group = GroupsApp.getGroupByEmail(groupEmail);
    Logger.log('Found group: ' + group.getEmail());
    const testEmail = memberEmail || Session.getActiveUser().getEmail();
    Logger.log('hasUser(' + testEmail + '): ' + group.hasUser(testEmail));
  } catch (err) {
    Logger.log('ERROR looking up group: ' + (err.message || err));
    Logger.log('Tip: the executing account must be owner/manager or allowed to view members of that group.');
  }
}

function isEmail_(value) {
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value);
}

function isGroupName_(value) {
  return /^[a-z0-9]([a-z0-9._-]{0,198}[a-z0-9])?$/.test(value);
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
