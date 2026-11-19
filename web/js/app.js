(function () {
  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => Array.from(document.querySelectorAll(sel));
  const t = (key, vars) => LeanI18n.t(key, vars);

  function pageTitle(name) {
    return ({
      dashboard: t('nav.dashboard'),
      dns: t('nav.dns'),
      adblock: t('nav.adblock'),
      lists: t('nav.lists'),
      system: t('nav.system'),
      help: t('nav.help')
    })[name] || name;
  }

  let hostsCache = [];
  let editingHost = null;
  let hostsSaving = false;
  let lists = null;
  let currentList = 'allow';
  let listPage = 0;
  let listsDirty = false;
  let currentPage;
  let statusTimer;
  let statusRequest;
  let statusFailures = 0;
  const pageSize = 50;

  function showToast(msg, ok) {
    const toastEl = $('#toast');
    toastEl.textContent = msg;
    toastEl.classList.remove('hidden', 'ok', 'err', 'busy');
    if (ok === 'busy') toastEl.classList.add('busy');
    else toastEl.classList.add(ok ? 'ok' : 'err');
    clearTimeout(showToast._timer);
    if (ok !== 'busy') {
      showToast._timer = setTimeout(() => toastEl.classList.add('hidden'), 3500);
    }
  }

  function actionControl(ev) {
    if (!ev) return null;
    if (ev.submitter) return ev.submitter;
    if (ev.currentTarget && ev.currentTarget !== document) return ev.currentTarget;
    return null;
  }

  async function runBusy(ev, work) {
    const ctl = actionControl(ev);
    if (ctl) ctl.disabled = true;
    showToast(t('msg.busy'), 'busy');
    try {
      await work();
    } catch (e) {
      showToast(e.message || t('msg.requestFail'), false);
    } finally {
      if (ctl) ctl.disabled = false;
      const toastEl = $('#toast');
      if (toastEl && toastEl.classList.contains('busy')) toastEl.classList.add('hidden');
    }
  }

  function fmtBytesKb(kb) {
    if (kb == null || kb === 'unsupported') return t('msg.unsupported');
    const n = Number(kb);
    if (n > 1024) return (n / 1024).toFixed(1) + ' MB';
    return n + ' KB';
  }

  function fmtUptime(sec) {
    sec = Number(sec) || 0;
    const d = Math.floor(sec / 86400);
    const h = Math.floor((sec % 86400) / 3600);
    const m = Math.floor((sec % 3600) / 60);
    return t('msg.uptime', { d, h, m });
  }

  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('leandns_theme', theme);
    $$('.theme-toggle').forEach((btn) => {
      btn.setAttribute('aria-label', t(theme === 'dark' ? 'theme.light' : 'theme.dark'));
    });
  }

  function setDrawer(open) {
    document.body.classList.toggle('drawer-open', open);
    const toggle = $('#menu-toggle');
    const backdrop = $('#drawer-backdrop');
    if (toggle) {
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
      toggle.setAttribute('aria-label', t(open ? 'nav.closeMenu' : 'nav.openMenu'));
    }
    if (backdrop) backdrop.setAttribute('aria-hidden', open ? 'false' : 'true');
  }

  function showPage(name) {
    $$('.page').forEach((p) => p.classList.add('hidden'));
    const el = $('#page-' + name);
    if (el) el.classList.remove('hidden');
    $$('.nav').forEach((b) => b.classList.toggle('active', b.dataset.page === name));
    $('#page-title').textContent = pageTitle(name);
    currentPage = name;
    setDrawer(false);
    hideToken();
    scheduleStatus(true);
    if (name === 'lists') renderLists();
    if (name === 'dns') loadDns();
    if (name === 'adblock') loadAdblock();
    if (name === 'lists' && !listsDirty) loadLists();
    if (name === 'system') loadSystem();
  }

  function metric(id, value, state = '') {
    const el = $(id);
    el.textContent = value;
    el.dataset.state = state;
  }

  function fmtDate(value) {
    if (!value || value === 'unsupported') return '—';
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(value)) {
      return value.replace('T', ' ');
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '—';
    const pad = (n) => String(n).padStart(2, '0');
    return [
      [date.getFullYear(), pad(date.getMonth() + 1), pad(date.getDate())].join('-'),
      [pad(date.getHours()), pad(date.getMinutes()), pad(date.getSeconds())].join(':')
    ].join(' ');
  }

  function fmtLatency(s) {
    const value = Number(s.dns_test_latency_ms);
    if (!Number.isFinite(value) || s.dns_test_latency_ms == null) return '';
    const precision = Number(s.dns_test_resolution_ms) || 1;
    if (value === 0) return t('msg.ltMs', { n: precision });
    return precision > 1 ? t('msg.approxMs', { n: value }) : t('msg.ms', { n: value });
  }

  function dnsSucceeded(s) {
    return s.dns_test_ok === true || s.dns_test_ok === 'true';
  }

  function flashScope(s) {
    return s.flash_scope === 'overlay' ? t('msg.flashOverlay') : t('msg.flashRoot');
  }

  function enabledAdblock(a) {
    return a.leandns_enabled == null ? a.adblock_state === 'enabled' : String(a.leandns_enabled) === '1';
  }

  function countRules(a) {
    const count = Number(a.rule_count);
    return a.rule_count != null && Number.isFinite(count) ? count.toLocaleString(LeanI18n.numberLocale) : '—';
  }

  function fmtCount(n) {
    const v = Number(n);
    return Number.isFinite(v) ? v.toLocaleString(LeanI18n.numberLocale) : '—';
  }

  function fmtAge(sec) {
    const v = Number(sec);
    if (!Number.isFinite(v) || v < 0) return '';
    if (v < 60) return t('msg.lastBlockSec', { n: v });
    if (v < 3600) return t('msg.lastBlockMin', { n: Math.floor(v / 60) });
    return t('msg.lastBlockHour', { n: Math.floor(v / 3600) });
  }

  function fmtDelta(today, yesterday) {
    const tv = Number(today);
    const y = Number(yesterday);
    if (!Number.isFinite(tv) || !Number.isFinite(y) || y <= 0) return t('msg.sinceReboot');
    const pct = Math.round(((tv - y) / y) * 100);
    if (pct === 0) return t('msg.sameAsYesterday');
    return t('msg.vsYesterday', { pct: (pct > 0 ? '+' : '') + pct });
  }

  function fmtLocalHm(sec) {
    const v = Number(sec);
    if (!Number.isFinite(v) || v <= 0) return '—';
    return new Date(v * 1000).toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  }

  function fmtLocalHms(sec) {
    const v = Number(sec);
    if (!Number.isFinite(v) || v <= 0) return '—';
    return new Date(v * 1000).toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    });
  }

  function trendLabel(row) {
    const m = Number(row && row.m);
    if (Number.isFinite(m) && m > 0) return fmtLocalHm(m * 60);
    return row && row.t ? String(row.t) : '—';
  }

  function updateBlockTrend(trend) {
    const el = $('#st-block-trend');
    if (!el) return;
    const rows = Array.isArray(trend) ? trend : [];
    if (!rows.length) {
      el.innerHTML = '<p class="muted">' + t('msg.trendEmpty') + '</p>';
      return;
    }
    const max = Math.max(1, ...rows.map((r) => Number(r.c) || 0));
    el.innerHTML = rows.map((r) => {
      const c = Number(r.c) || 0;
      const h = Math.max(8, Math.round((c / max) * 100));
      const label = trendLabel(r);
      return '<div class="trend-col" title="' + t('msg.trendTitle', { label, n: c }) + '">' +
        '<div class="trend-bar" style="height:' + h + '%"></div>' +
        '<span class="trend-val">' + c + '</span>' +
        '<span class="trend-label">' + label + '</span></div>';
    }).join('');
  }

  function updateRecentBlocks(bs) {
    const body = $('#st-recent-body');
    const title = $('#st-recent-title');
    const hint = $('#st-recent-hint');
    if (!body) return;
    const limit = Number(bs && bs.recent_limit) || 20;
    if (title) title.textContent = t('msg.recentTitle', { n: limit });
    if (hint) {
      hint.textContent = bs && bs.paused ? t('msg.pausedHint')
        : (limit <= 10 ? t('msg.lowMemHint') : t('msg.memOnlyHint'));
    }
    const rows = (bs && Array.isArray(bs.recent)) ? bs.recent : [];
    if (!rows.length) {
      body.innerHTML = '<tr><td colspan="5" class="muted">' + t('dash.noRecent') + '</td></tr>';
      return;
    }
    body.innerHTML = rows.map((r) => {
      const type = LeanI18n.localizeType(r.type);
      const time = Number.isFinite(Number(r.ts)) ? fmtLocalHms(r.ts) : (r.time || '—');
      return '<tr>' +
        '<td>' + (r.n || '') + '</td>' +
        '<td>' + time + '</td>' +
        '<td class="domain">' + (r.domain || '—') + '</td>' +
        '<td><span class="type-pill ' + LeanI18n.typeClass(r.type) + '">' + type + '</span></td>' +
        '<td>' + (r.client || '—') + '</td>' +
        '</tr>';
    }).join('');
  }

  function updateBlockStats(s) {
    const bs = s.block_stats || {};
    const enabled = bs.enabled === true || bs.enabled === 'true';
    const paused = bs.paused === true || bs.paused === 'true';
    if (!enabled) {
      metric('#st-block-10m', t('msg.off'));
      metric('#st-block-last', t('msg.queryLogOff'));
      metric('#st-block-today', '—');
      metric('#st-block-delta', '');
      metric('#st-sum-1m', '—');
      metric('#st-sum-10m', '—');
      metric('#st-sum-today', '—');
      metric('#st-sum-state', t('msg.notCollecting'));
      updateBlockTrend([]);
      updateRecentBlocks({ recent_limit: 20, recent: [], paused: false });
      metric('#st-block-trend-note', t('msg.enableQueryLog'));
      return;
    }
    metric('#st-block-10m', t('msg.nBlocks', { n: fmtCount(bs.count_10m) }));
    metric('#st-block-last', fmtAge(bs.last_block_age_sec) || (bs.count_today ? '' : t('msg.noBlocksYet')));
    metric('#st-block-today', t('msg.nBlocks', { n: fmtCount(bs.count_today) }));
    metric('#st-block-delta', fmtDelta(bs.count_today, bs.count_yesterday), Number(bs.count_today) >= Number(bs.count_yesterday) ? 'ok' : '');
    metric('#st-sum-1m', t('msg.nBlocks', { n: fmtCount(bs.count_1m) }));
    metric('#st-sum-10m', t('msg.nBlocks', { n: fmtCount(bs.count_10m) }));
    metric('#st-sum-today', t('msg.nBlocks', { n: fmtCount(bs.count_today) }));
    metric('#st-sum-state', paused ? t('msg.paused') : (Number(bs.recent_limit) <= 10 ? t('msg.lowMemMode') : t('msg.collecting')),
      paused ? 'warn' : 'ok');
    updateBlockTrend(bs.trend);
    updateRecentBlocks(bs);
    metric('#st-block-trend-note', t('msg.perMinNote'));
  }

  function updateResourceMeter(meterId, readingId, amount, total) {
    const meter = $(meterId);
    const valid = Number.isFinite(amount) && Number.isFinite(total) && total > 0 && amount >= 0 && amount <= total;
    meter.hidden = !valid;
    if (!valid) {
      metric(readingId, '—');
      return;
    }
    const reading = fmtBytesKb(amount) + ' / ' + fmtBytesKb(total);
    metric(readingId, reading);
    meter.value = amount / total;
    meter.setAttribute('aria-valuetext', reading);
  }

  function updateDashboard(s) {
    const a = s.adblock || {};
    const dns = !s.dnsmasq_running ? [t('msg.stopped'), 'error'] : dnsSucceeded(s)
      ? [t('msg.ok'), 'ok'] : s.dns_test_ok === 'unsupported' ? [t('msg.running'), ''] : [t('msg.lookupFail'), 'warn'];
    metric('#st-dns', ...dns);
    metric('#st-rtt', [s.dns_test_host, dnsSucceeded(s) && fmtLatency(s)].filter(Boolean).join(' · '));
    const adblock = a.list_state === 'updating' ? [t('msg.updating'), 'warn']
      : a.list_state === 'applied' ? [t('msg.applied'), 'ok']
      : !a.adblock_available ? [t('msg.notInstalled'), 'warn']
      : enabledAdblock(a) ? [t('msg.needsCheck'), 'warn'] : [t('msg.disabled'), ''];
    metric('#st-adblock', ...adblock);
    metric('#st-rules', a.list_state === 'applied' && countRules(a) !== '—' ? t('msg.nRules', { n: countRules(a) }) : '');
    updateBlockStats(s);
    const hasAvailableRam = Number.isFinite(s.mem_available_kb) && s.mem_available_kb >= 0;
    const used = hasAvailableRam ? s.mem_total_kb - s.mem_available_kb : null;
    updateResourceMeter('#st-mem-meter', '#st-mem-used', used, s.mem_total_kb);
    metric('#st-mem-available', hasAvailableRam ? t('msg.ramAvail', { n: fmtBytesKb(s.mem_available_kb) }) : '');
    metric('#st-flash-label', 'FLASH');
    updateResourceMeter('#st-flash-meter', '#st-flash-total', s.flash_free_kb, s.flash_total_kb);
    metric('#st-flash-scope', flashScope(s));
    metric('#st-up', fmtUptime(s.uptime_sec));
    setVersionLabels(s);
    metric('#st-upstream', (s.upstream || []).join(', ') || '—');
    metric('#st-domain', s.internal_domain || '—');
    metric('#st-upd', fmtDate(a.last_update));
    metric('#st-checked', t('msg.lastChecked', { t: fmtDate(new Date()) }));
  }

  function versionText(s) {
    const fw = s && s.firmware;
    if (fw && fw !== 'unsupported') return fw;
    return '—';
  }

  function setVersionLabels(s) {
    const fw = versionText(s);
    const pkg = (s && s.version) ? String(s.version) : '';
    const label = pkg ? fw + ' · LeanDNS ' + pkg : fw;
    metric('#st-firmware', fw);
    const brand = $('#brand-version');
    if (brand) brand.textContent = label;
    const header = $('#header-version');
    if (header) header.textContent = label;
    const sysFw = $('#sys-firmware');
    if (sysFw) sysFw.textContent = fw;
    const sysPkg = $('#sys-pkg-version');
    if (sysPkg) sysPkg.textContent = pkg ? 'LeanDNS ' + pkg : '';
  }

  function dashboardVisible() {
    return currentPage === 'dashboard' && !document.hidden;
  }

  function scheduleStatus(immediate = false) {
    clearTimeout(statusTimer);
    if (!dashboardVisible() || statusRequest) return;
    if (immediate) refreshStatus();
    else if (statusFailures < 3) statusTimer = setTimeout(refreshStatus, 20000);
  }

  async function refreshStatus() {
    if (!dashboardVisible() || statusRequest) return;
    clearTimeout(statusTimer);
    $('#btn-refresh-status').disabled = true;
    statusRequest = LeanAPI.call('status');
    try {
      updateDashboard(await statusRequest);
      statusFailures = 0;
    } catch (e) {
      statusFailures++;
      metric('#st-checked', t('msg.statusFail', { msg: e.message }), 'error');
    } finally {
      statusRequest = null;
      $('#btn-refresh-status').disabled = false;
      scheduleStatus();
    }
  }

  async function loadDns() {
    $('#host-submit').disabled = true;
    try {
      const d = await LeanAPI.call('dns_get');
      $('#dns-upstream').value = (d.upstream || []).join('\n');
      $('#dns-cache').value = d.cachesize ?? 1000;
      $('#dns-domain').value = d.internal_domain || 'home.arpa';
      $('#dns-test-host').value = d.dns_test_host || 'one.one.one.one';
      $('#dns-ipv6').checked = !!d.ipv6_dns;
      const h = await LeanAPI.call('hosts_list');
      hostsCache = h.hosts || [];
      renderHosts();
      $('#host-submit').disabled = false;
    } catch (e) {
      showToast(t('msg.dnsLoadFail', { msg: e.message }), false);
    }
  }

  function renderHosts() {
    const body = $('#hosts-body');
    body.innerHTML = '';
    if (!hostsCache.length) {
      const row = body.insertRow().insertCell();
      row.colSpan = 3;
      row.textContent = t('dns.noHosts');
    }
    hostsCache.forEach((row, idx) => {
      const tr = document.createElement('tr');
      tr.innerHTML = '<td></td><td></td><td></td>';
      tr.children[0].textContent = row.hostname;
      tr.children[1].textContent = row.ip;
      const actions = tr.children[2];
      const controls = document.createElement('div');
      controls.className = 'row';
      const edit = document.createElement('button');
      edit.type = 'button';
      edit.className = 'secondary';
      edit.textContent = t('dns.edit');
      edit.addEventListener('click', () => {
        editingHost = row.hostname;
        $('#host-name').value = row.hostname;
        $('#host-ip').value = row.ip;
        $('#host-submit').textContent = t('dns.saveHost');
        $('#host-cancel').classList.remove('hidden');
        $('#host-name').focus();
      });
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'secondary';
      remove.textContent = t('dns.delete');
      remove.addEventListener('click', (ev) => {
        runBusy(ev, () => saveHosts(hostsCache.filter((_, i) => i !== idx)));
      });
      controls.append(edit, remove);
      actions.appendChild(controls);
      body.appendChild(tr);
    });
  }

  function resetHostForm() {
    editingHost = null;
    $('#host-add').reset();
    $('#host-submit').textContent = t('dns.add');
    $('#host-cancel').classList.add('hidden');
  }

  async function saveHosts(hosts) {
    if (hostsSaving) return;
    hostsSaving = true;
    try {
      const r = await LeanAPI.call('hosts_set', { hosts });
      if (r.ok === false) throw new Error(r.error || t('msg.saveFail'));
      hostsCache = hosts;
      resetHostForm();
      renderHosts();
      showToast(t('msg.hostsSaved'), true);
    } finally {
      hostsSaving = false;
    }
  }

  async function loadAdblock() {
    try {
      const a = await LeanAPI.call('adblock_status');
      const enabled = enabledAdblock(a);
      $('#adblock-enabled').checked = enabled;
      metric('#adblock-state', enabled ? t('msg.active') : t('msg.inactive'));
      metric('#adblock-engine', ({
        ok: t('msg.ok'), error: t('msg.error'), missing: t('msg.notInstalled'), stopped: t('msg.stopped'), checking: t('msg.checking')
      })[a.engine_state] || t('msg.needsReview'), a.engine_state === 'error' ? 'error' : '');
      metric('#adblock-list-state', ({
        applied: t('msg.applied'), not_applied: t('msg.notApplied'), updating: t('msg.updating'), unknown: t('msg.needsReview')
      })[a.list_state] || t('msg.needsReview'), a.list_state === 'applied' ? 'ok' : 'warn');
      metric('#adblock-rules', countRules(a));
      metric('#adblock-upd', fmtDate(a.last_update));
      const messages = {
        success: t('msg.success'), updating: t('msg.inProgress'), low_ram: t('msg.failLowRam'),
        low_tmp: t('msg.failLowTmp'), failed: t('msg.failCheckLogs')
      };
      metric('#adblock-result', messages[a.update_result] || t('msg.noRecord'));
      $('#btn-adblock-update').disabled = !enabled || a.list_state === 'updating';
      $('#adblock-form [type="submit"]').disabled = a.list_state === 'updating';
    } catch (e) {
      showToast(e.message, false);
    }
  }

  async function loadLists() {
    const controls = $('#lists-controls');
    controls.disabled = true;
    try {
      const data = await LeanAPI.call('lists_get');
      lists = { allow: data.allow || [], block: data.block || [] };
      controls.disabled = false;
      renderLists();
    } catch (e) {
      showToast(e.message, false);
    }
  }

  function renderLists() {
    const entries = $('#list-entries');
    entries.replaceChildren();
    if (!lists) return;
    const all = lists[currentList];
    const query = $('#list-search').value.trim().toLowerCase();
    const matches = query ? all.filter((domain) => domain.toLowerCase().includes(query)) : all;
    const pages = Math.max(1, Math.ceil(matches.length / pageSize));
    listPage = Math.min(listPage, pages - 1);
    const start = listPage * pageSize;
    const range = pages > 1 ? t('msg.listRange', { a: start + 1, b: Math.min(start + pageSize, matches.length) }) : '';
    $('#list-count').textContent = (query
      ? t('msg.listCountSearch', { m: matches.length, n: all.length })
      : t('msg.listCountAll', { n: all.length })) + range;
    $('#list-prev').disabled = listPage === 0;
    $('#list-next').disabled = listPage >= pages - 1;
    $('#btn-lists-save').disabled = !listsDirty;
    $('#list-dirty').classList.toggle('hidden', !listsDirty);
    if (!matches.length) {
      const item = document.createElement('li');
      item.textContent = query ? t('msg.noSearch') : t('msg.noDomains');
      entries.appendChild(item);
    }
    for (const domain of matches.slice(start, start + pageSize)) {
      const item = document.createElement('li');
      const label = document.createElement('span');
      label.textContent = domain;
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'secondary';
      remove.textContent = t('dns.delete');
      remove.setAttribute('aria-label', t('msg.deleteAria', { domain }));
      remove.addEventListener('click', () => {
        lists[currentList] = lists[currentList].filter((d) => d !== domain);
        listsDirty = true;
        renderLists();
      });
      item.append(label, remove);
      entries.appendChild(item);
    }
  }

  function addDomains(domains) {
    const normalized = new Set(lists[currentList].map((d) => d.toLowerCase().replace(/\.$/, '')));
    const additions = [];
    const valid = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$/;
    for (const raw of domains) {
      const domain = raw.toLowerCase().replace(/\.$/, '');
      if (!domain) continue;
      if (domain.length > 253 || !valid.test(domain)) throw new Error(t('msg.badDomain', { raw }));
      if (!normalized.has(domain)) additions.push(domain);
      normalized.add(domain);
    }
    if (!additions.length) {
      showToast(t('msg.noNewDomains'), false);
      return;
    }
    lists[currentList] = lists[currentList].concat(additions).sort();
    listsDirty = true;
    $('#list-search').value = '';
    listPage = 0;
    renderLists();
    showToast(t('msg.addedNeedSave', { n: additions.length }), true);
  }

  function hideToken() {
    $('#udp-token').textContent = '';
    $('#udp-token-line').classList.add('hidden');
    $('#btn-udp-reveal').textContent = t('sys.tokenShow');
  }

  function revealToken(token) {
    $('#udp-token').textContent = token;
    $('#udp-token-line').classList.remove('hidden');
    $('#btn-udp-reveal').textContent = t('sys.tokenHide');
  }

  function updateNetwork(s) {
    $('#net-ip').value = s.ipaddr || '';
    $('#net-mask').value = s.netmask || '';
    $('#net-gw').value = s.gateway || '';
    const netIp = $('#sys-net-ip');
    const netGw = $('#sys-net-gw');
    if (netIp) netIp.textContent = s.ipaddr ? ('IP ' + s.ipaddr) : '—';
    if (netGw) netGw.textContent = s.gateway ? ('GW ' + s.gateway) : '';
    const pending = s.pending_ip || '';
    $('#net-apply').disabled = !!pending;
    $('#net-pending').classList.toggle('hidden', !pending);
    if (!pending) return;
    const isNewAddress = LeanAPI.state.mode === 'mock' || location.hostname === pending;
    const ready = s.pending_state === 'ready';
    $('#net-confirm').classList.toggle('hidden', !isNewAddress || !ready);
    const statusMsgs = {
      applying: t('msg.netApplying'),
      ready: t('msg.netReady'),
      restore_failed: t('msg.netRestoreFail')
    };
    metric('#net-pending-text', pending + ' · ' + (statusMsgs[s.pending_state] || statusMsgs.applying),
      s.pending_state === 'restore_failed' ? 'error' : '');
    const link = $('#net-pending-link');
    const url = new URL(location.href);
    url.hostname = pending;
    url.hash = 'system';
    link.href = url.href;
    link.classList.toggle('hidden', isNewAddress);
  }

  async function loadLogs() {
    const logs = await LeanAPI.call('logs_get', { lines: 100 });
    $('#sys-logs').textContent = (logs.lines || []).join('\n') || t('msg.noLogs');
  }

  function setFirmwareUi(state) {
    const ready = !!(state && state.image_present && (state.verified || state.state === 'verified'));
    const applying = state && state.state === 'applying';
    const btnApply = $('#btn-fw-apply');
    const btnAbort = $('#btn-fw-abort');
    if (btnApply) btnApply.disabled = !ready || applying;
    if (btnAbort) {
      btnAbort.disabled = !state || !(state.image_present || state.state === 'prepared' || state.state === 'uploaded' || state.state === 'verified');
    }
  }

  function isSysupgradeName(name) {
    const n = String(name || '').toLowerCase();
    if (!/\.bin$/i.test(n)) return false;
    if (n.includes('factory')) return false;
    return n.includes('sysupgrade');
  }

  async function refreshFirmwareStatus(msg) {
    const st = await LeanAPI.call('firmware_status');
    setFirmwareUi(st);
    const infoTmp = $('#sys-info-tmp');
    if (infoTmp && st.tmp_free_kb != null) infoTmp.textContent = fmtBytesKb(st.tmp_free_kb);
    if (msg != null) metric('#fw-status', msg, /실패|불가|부족|factory|fail|unavailable|low|insufficient/i.test(String(msg)) ? 'error' : (st.verified ? 'ok' : ''));
    else if (st.image_present && st.verified) {
      metric('#fw-status',
        t('msg.fwVerified', { img: fmtBytesKb(st.image_kb), ram: fmtBytesKb(st.mem_available_kb), tmp: fmtBytesKb(st.tmp_free_kb) }),
        'ok');
    } else if (st.image_present) {
      metric('#fw-status',
        t('msg.fwUploaded', { img: fmtBytesKb(st.image_kb), ram: fmtBytesKb(st.mem_available_kb) }),
        'warn');
    } else {
      metric('#fw-status',
        t('msg.fwIdle', { ram: fmtBytesKb(st.mem_available_kb), tmp: fmtBytesKb(st.tmp_free_kb) }));
    }
    return st;
  }

  async function loadSystem() {
    try {
      const [s, n, udpTok] = await Promise.all([
        LeanAPI.call('system_info'), LeanAPI.call('network_get'), LeanAPI.call('udp_token_get')
      ]);
      setVersionLabels(s);
      const flashLabel = t('msg.flashFreeLabel', { scope: flashScope(s) });
      $('#sys-flash-label').textContent = flashLabel;
      $('#sys-flash').textContent = fmtBytesKb(s.flash_free_kb) + ' / ' + fmtBytesKb(s.flash_total_kb);
      $('#sys-mem').textContent = fmtBytesKb(s.mem_available_kb) + ' / ' + fmtBytesKb(s.mem_total_kb);
      const infoRam = $('#sys-info-ram');
      const infoFlash = $('#sys-info-flash');
      const infoFlashLabel = $('#sys-info-flash-label');
      if (infoRam) infoRam.textContent = fmtBytesKb(s.mem_available_kb) + ' / ' + fmtBytesKb(s.mem_total_kb);
      if (infoFlash) infoFlash.textContent = fmtBytesKb(s.flash_free_kb) + ' / ' + fmtBytesKb(s.flash_total_kb);
      if (infoFlashLabel) infoFlashLabel.textContent = flashLabel;
      updateNetwork(n);
      $('#udp-token-required').checked = udpTok.required !== false;
      $('#udp-token-required').disabled = false;
      try {
        await refreshFirmwareStatus();
      } catch (_) {
        metric('#fw-status', t('msg.fwStatusFail'));
      }
      await loadLogs();
    } catch (e) {
      showToast(e.message, false);
    }
  }

  async function boot() {
    LeanI18n.apply();

    const theme = localStorage.getItem('leandns_theme') || 'light';
    setTheme(theme);

    $$('.nav').forEach((b) => b.addEventListener('click', () => showPage(b.dataset.page)));
    $$('.theme-toggle').forEach((btn) => {
      btn.addEventListener('click', () => {
        const cur = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
        setTheme(cur);
      });
    });
    const menuToggle = $('#menu-toggle');
    if (menuToggle) {
      menuToggle.addEventListener('click', () => {
        setDrawer(!document.body.classList.contains('drawer-open'));
      });
    }
    const backdrop = $('#drawer-backdrop');
    if (backdrop) backdrop.addEventListener('click', () => setDrawer(false));
    document.addEventListener('keydown', (ev) => {
      if (ev.key === 'Escape') setDrawer(false);
    });
    window.addEventListener('resize', () => {
      if (window.matchMedia('(min-width: 861px)').matches) setDrawer(false);
    });
    const dnsSummary = $('#dns-summary-card');
    if (dnsSummary) {
      const openDns = () => showPage('dns');
      dnsSummary.addEventListener('click', openDns);
      dnsSummary.addEventListener('keydown', (ev) => {
        if (ev.key === 'Enter' || ev.key === ' ') {
          ev.preventDefault();
          openDns();
        }
      });
    }
    $('#logout-btn').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        await LeanAPI.logout();
        location.reload();
      });
    });
    $('#btn-refresh-status').addEventListener('click', refreshStatus);
    document.addEventListener('visibilitychange', () => scheduleStatus(true));

    $('#dns-form').addEventListener('submit', (ev) => {
      ev.preventDefault();
      runBusy(ev, async () => {
        const upstream = $('#dns-upstream').value.split(/\n+/).map((s) => s.trim()).filter(Boolean);
        try {
          const r = await LeanAPI.call('dns_set', {
            upstream,
            cachesize: Number($('#dns-cache').value),
            internal_domain: $('#dns-domain').value.trim(),
            dns_test_host: $('#dns-test-host').value.trim(),
            ipv6_dns: $('#dns-ipv6').checked
          });
          if (r.ok === false) throw new Error(r.error || t('msg.saveFail'));
          showToast(t('msg.dnsApplied'), true);
          await loadDns();
        } catch (e) {
          showToast(e.message, false);
          await loadDns();
        }
      });
    });

    $('#dns-test-form').addEventListener('submit', (ev) => {
      ev.preventDefault();
      runBusy(ev, async () => {
        const host = $('#dns-test-host').value.trim();
        const result = $('#dns-result');
        result.classList.remove('hidden');
        metric('#dns-result', t('msg.dnsLooking', { host }));
        try {
          const r = await LeanAPI.call('dns_test', { host });
          if (r.ok === false) throw new Error(r.error || t('msg.lookupFailShort'));
          const ok = dnsSucceeded(r);
          const status = ok ? t('msg.dnsOk') : r.dns_test_ok === 'unsupported' ? t('msg.dnsUnsupported') : t('msg.dnsFail');
          metric('#dns-result', [status + ' · ' + (r.dns_test_host || host),
            (r.addresses || []).join(', '), ok && fmtLatency(r)].filter(Boolean).join('\n'), ok ? 'ok' : 'error');
        } catch (e) {
          metric('#dns-result', e.message, 'error');
        }
      });
    });
    $('#btn-dns-restart').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        try {
          await LeanAPI.call('dns_restart');
          showToast(t('msg.dnsRestarted'), true);
        } catch (e) {
          showToast(e.message, false);
        }
      });
    });

    $('#host-add').addEventListener('submit', (ev) => {
      ev.preventDefault();
      runBusy(ev, async () => {
        const hostname = $('#host-name').value.trim();
        const ip = $('#host-ip').value.trim();
        if (hostsCache.some((h) => h.hostname !== editingHost && h.hostname.toLowerCase() === hostname.toLowerCase())) {
          throw new Error(t('msg.hostExists'));
        }
        await saveHosts([...hostsCache.filter((h) => h.hostname !== editingHost), { hostname, ip }]);
      });
    });
    $('#host-cancel').addEventListener('click', resetHostForm);

    $('#adblock-form').addEventListener('submit', (ev) => {
      ev.preventDefault();
      runBusy(ev, async () => {
        try {
          const r = await LeanAPI.call('adblock_set', { enabled: $('#adblock-enabled').checked });
          if (r.ok === false) throw new Error(r.error || t('msg.setFail'));
          showToast(t('msg.adblockApplied'), true);
        } finally {
          await loadAdblock();
        }
      });
    });
    $('#btn-adblock-status').addEventListener('click', (ev) => runBusy(ev, loadAdblock));
    $('#btn-adblock-update').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        const update = LeanAPI.call('adblock_update');
        metric('#adblock-list-state', t('msg.updateRequesting'), 'warn');
        try {
          const r = await update;
          if (r.ok === false) throw new Error(r.error || t('msg.updateFail'));
          showToast(r.started === 'background' ? t('msg.updateStarted') : t('msg.updateDone'), true);
        } finally {
          await loadAdblock();
        }
      });
    });

    $$('[data-list]').forEach((button) => button.addEventListener('click', () => {
      currentList = button.dataset.list;
      $$('[data-list]').forEach((b) => b.setAttribute('aria-pressed', String(b === button)));
      $('#list-search').value = '';
      listPage = 0;
      renderLists();
    }));
    $('#list-search').addEventListener('input', () => {
      listPage = 0;
      renderLists();
    });
    $('#list-prev').addEventListener('click', () => { listPage--; renderLists(); });
    $('#list-next').addEventListener('click', () => { listPage++; renderLists(); });
    for (const id of ['list-add', 'list-bulk']) {
      $('#' + id).addEventListener('submit', (ev) => {
        ev.preventDefault();
        const input = ev.currentTarget.querySelector('input, textarea');
        try {
          addDomains(input.value.trim().split(/\r?\n/).map((s) => s.trim()));
          input.value = '';
        } catch (e) {
          showToast(e.message, false);
        }
      });
    }
    $('#btn-lists-save').addEventListener('click', () => {
      runBusy(null, async () => {
        const controls = $('#lists-controls');
        controls.disabled = true;
        try {
          const r = await LeanAPI.call('lists_set', lists);
          if (r.ok === false) throw new Error(r.error || t('msg.saveFail'));
          listsDirty = false;
          renderLists();
          showToast(t('msg.listsSaved'), true);
        } finally {
          controls.disabled = false;
        }
      });
    });

    $('#btn-logs').addEventListener('click', (ev) => runBusy(ev, loadLogs));
    $('#btn-logs-clear').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        await LeanAPI.call('logs_clear');
        showToast(t('msg.logsCleared'), true);
        await loadLogs();
      });
    });
    $('#btn-svc-restart').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        await LeanAPI.call('system_restart_services');
        showToast(t('msg.svcRestarted'), true);
      });
    });
    $('#net-form').addEventListener('submit', (ev) => {
      ev.preventDefault();
      const ipaddr = $('#net-ip').value.trim();
      const netmask = $('#net-mask').value.trim();
      const gateway = $('#net-gw').value.trim();
      if (!confirm(t('msg.netConfirm', { ip: ipaddr }))) return;
      runBusy(null, async () => {
        $('#net-apply').disabled = true;
        try {
          const r = await LeanAPI.call('network_set', { ipaddr, netmask, gateway });
          if (r.ok === false) throw new Error(r.error || t('msg.netApplyFail'));
          updateNetwork({ ipaddr, netmask, gateway, pending_ip: '', pending_state: '' });
          if (LeanAPI.state.mode !== 'mock' && location.hostname !== ipaddr) {
            const url = new URL(location.href);
            url.hostname = ipaddr;
            url.hash = 'system';
            showToast(t('msg.netAppliedGoto', { ip: ipaddr }), true);
            window.setTimeout(() => { location.href = url.href; }, 1200);
          } else {
            showToast(t('msg.netApplied'), true);
            updateNetwork(await LeanAPI.call('network_get'));
          }
        } catch (e) {
          $('#net-apply').disabled = false;
          throw e;
        }
      });
    });
    $('#net-check').addEventListener('click', (ev) => {
      runBusy(ev, async () => updateNetwork(await LeanAPI.call('network_get')));
    });
    $('#net-confirm').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        const r = await LeanAPI.call('network_confirm');
        if (r.ok === false) throw new Error(r.error || t('msg.netConfirmFail'));
        updateNetwork(await LeanAPI.call('network_get'));
        showToast(t('msg.netSaved'), true);
      });
    });
    $('#udp-token-required').addEventListener('change', (ev) => {
      const box = ev.currentTarget;
      const required = box.checked;
      runBusy(ev, async () => {
        try {
          const r = await LeanAPI.call('udp_token_set', { required, enabled: true });
          if (r.ok === false) throw new Error(r.error || t('msg.setFail'));
          box.checked = r.required !== false;
          showToast(required ? t('msg.udpTokenOn') : t('msg.udpTokenOff'), true);
        } catch (e) {
          box.checked = !required;
          throw e;
        }
      });
    });
    $('#btn-udp-reveal').addEventListener('click', (ev) => {
      if (!$('#udp-token-line').classList.contains('hidden')) {
        hideToken();
        return;
      }
      runBusy(ev, async () => {
        const tok = await LeanAPI.call('udp_token_get', { reveal: true });
        if (!tok.token) throw new Error(tok.error || t('msg.tokenFail'));
        if (currentPage === 'system') revealToken(tok.token);
      });
    });
    $('#btn-udp-regen').addEventListener('click', (ev) => {
      if (!confirm(t('msg.tokenRegenConfirm'))) return;
      runBusy(ev, async () => {
        const r = await LeanAPI.call('udp_token_regen');
        if (r.ok === false) throw new Error(r.error || t('msg.regenFail'));
        hideToken();
        showToast(t('msg.tokenRegenOk'), true);
      });
    });
    $$('.copy-command').forEach((button) => button.addEventListener('click', async () => {
      const code = button.previousElementSibling;
      try {
        await navigator.clipboard.writeText(code.textContent);
        showToast(t('msg.copied'), true);
      } catch (_) {
        const range = document.createRange();
        range.selectNodeContents(code);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        if (document.execCommand('copy')) showToast(t('msg.copied'), true);
        else showToast(t('msg.copyManual'), false);
      }
    }));
    $('#fw-file').addEventListener('change', () => {
      const file = $('#fw-file').files && $('#fw-file').files[0];
      $('#fw-file-label').textContent = file
        ? (file.name + ' · ' + fmtBytesKb(Math.ceil(file.size / 1024)))
        : t('sys.fwNone');
      $('#btn-fw-apply').disabled = true;
    });

    $('#btn-fw-upload').addEventListener('click', (ev) => {
      const file = $('#fw-file').files && $('#fw-file').files[0];
      if (!file) {
        showToast(t('msg.pickSysupgrade'), false);
        return;
      }
      if (!isSysupgradeName(file.name)) {
        showToast(t('msg.notFactory'), false);
        metric('#fw-status', t('msg.factoryHint'), 'error');
        return;
      }
      runBusy(ev, async () => {
        metric('#fw-status', t('msg.fwPreparing'), 'warn');
        const prep = await LeanAPI.call('firmware_prepare', { size: file.size });
        if (prep.ok === false) throw new Error(prep.error || t('msg.prepFail'));
        metric('#fw-status', t('msg.uploading', { pct: 0 }), 'warn');
        const up = await LeanAPI.uploadFirmware(file, (p) => {
          metric('#fw-status', t('msg.uploading', { pct: Math.round(p * 100) }), 'warn');
        });
        if (up.ok === false) throw new Error(up.error || t('msg.uploadFail'));
        metric('#fw-status', t('msg.verifying'), 'warn');
        const ver = await LeanAPI.call('firmware_verify');
        if (ver.ok === false) {
          await LeanAPI.call('firmware_abort').catch(() => {});
          $('#btn-fw-apply').disabled = true;
          throw new Error(ver.error || t('msg.verifyFail'));
        }
        await refreshFirmwareStatus(t('msg.fwReady'));
        showToast(t('msg.fwUploadOk'), true);
      });
    });

    $('#btn-fw-abort').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        const r = await LeanAPI.call('firmware_abort');
        if (r.ok === false) throw new Error(r.error || t('msg.abortFail'));
        $('#fw-file').value = '';
        $('#fw-file-label').textContent = t('sys.fwNone');
        await refreshFirmwareStatus(t('msg.fwAbortedStatus'));
        showToast(t('msg.fwAborted'), true);
      });
    });

    $('#btn-fw-apply').addEventListener('click', (ev) => {
      const keep = $('#fw-keep').checked;
      const warn = keep ? t('msg.fwWarnKeep') : t('msg.fwWarnReset');
      if (!confirm(warn + t('msg.continueQ'))) return;
      runBusy(ev, async () => {
        metric('#fw-status', t('msg.fwApplying'), 'warn');
        let r;
        try {
          r = await LeanAPI.call('firmware_apply', { keep_settings: keep });
        } catch (e) {
          await refreshFirmwareStatus(e.message || t('msg.applyFail'));
          throw e;
        }
        if (r.ok === false) {
          await refreshFirmwareStatus(r.error || t('msg.applyFail'));
          throw new Error(r.error || t('msg.applyFail'));
        }
        showToast(t('msg.fwStarted'), true);
        // Require offline→online transition. Immediate ping success is still the old OS.
        let tries = 0;
        let sawDown = false;
        const anonymousSid = '00000000000000000000000000000000';
        const pollPing = async () => {
          if (LeanAPI.state.mode === 'mock') return LeanAPI.call('ping');
          return LeanAPI.ubusCall('leandns', 'ping', {}, anonymousSid);
        };
        const tick = async () => {
          tries += 1;
          let up = false;
          let ping = null;
          try {
            ping = await pollPing();
            up = !!(ping && ping.ok);
          } catch (_) {
            up = false;
          }
          if (!up) {
            if (!sawDown) {
              sawDown = true;
              // Old session will be invalid after reboot.
              try { await LeanAPI.logout(); } catch (_) { /* ignore */ }
            }
            metric('#fw-status', t('msg.rebooting', { n: tries }), 'warn');
          } else if (!sawDown) {
            metric('#fw-status', t('msg.stillOld', { n: tries }), 'warn');
          } else {
            metric('#fw-status', t('msg.rebootDone', { fw: ping.firmware || 'OK' }), 'ok');
            showToast(t('msg.onlineAgain'), true);
            return;
          }
          if (tries > 120) {
            metric('#fw-status', t('msg.noResponse'), 'error');
            return;
          }
          window.setTimeout(tick, 2000);
        };
        window.setTimeout(tick, 3000);
      });
    });

    $('#btn-backup').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        try {
          const r = await LeanAPI.call('backup_export');
          if (r.ok === false) throw new Error(r.error || t('msg.exportFail'));
          const b64 = (r.data_base64 || '').trim();
          if (!b64) throw new Error(t('msg.emptyBackup'));
          const blob = new Blob([b64], { type: 'text/plain' });
          const a = document.createElement('a');
          a.href = URL.createObjectURL(blob);
          a.download = r.filename ? r.filename + '.b64' : 'leandns-backup.b64';
          a.click();
          URL.revokeObjectURL(a.href);
          showToast(t('msg.exportOk'), true);
        } catch (e) {
          showToast(e.message, false);
        }
      });
    });
    $('#import-file').addEventListener('change', (ev) => {
      const file = ev.target.files && ev.target.files[0];
      if (!file) return;
      runBusy(ev, async () => {
        let text = (await file.text()).trim();
        try {
          // Older broken exports saved the JSON envelope instead of raw base64.
          if (text.startsWith('{') && text.includes('data_base64')) {
            try {
              const parsed = JSON.parse(text);
              if (parsed && typeof parsed.data_base64 === 'string') text = parsed.data_base64.trim();
            } catch (_) { /* keep raw text */ }
          }
          if (!text) throw new Error(t('msg.emptyFile'));
          const r = await LeanAPI.call('backup_import', { data_base64: text });
          if (r.ok === false) throw new Error(r.error || t('msg.importFail'));
          showToast(t('msg.importOk'), true);
        } catch (e) {
          showToast(e.message, false);
        } finally {
          ev.target.value = '';
        }
      });
    });

    $('#login-form').addEventListener('submit', (ev) => {
      ev.preventDefault();
      const btn = ev.submitter;
      const label = btn ? btn.textContent : '';
      if (btn) {
        btn.disabled = true;
        btn.textContent = t('login.busy');
      }
      $('#login-error').textContent = '';
      LeanAPI.login($('#login-user').value.trim(), $('#login-pass').value).then(async () => {
        try {
          setVersionLabels(await LeanAPI.call('ping'));
        } catch (_) { /* status refresh will fill version */ }
        enterApp();
      }).catch((e) => {
        $('#login-error').textContent = t('login.fail', { msg: e.message });
      }).finally(() => {
        if (btn) {
          btn.disabled = false;
          btn.textContent = label;
        }
      });
    });

    if (LeanAPI.isAuthed()) {
      try {
        const pong = await LeanAPI.call('ping');
        setVersionLabels(pong);
        enterApp();
        return;
      } catch (_) {
        await LeanAPI.logout();
      }
    }
    $('#login-view').classList.remove('hidden');
    try {
      const a = await LeanAPI.call('auth_required');
      if (a.force_password_change) $('#force-pw').classList.remove('hidden');
    } catch (_) { /* mock/device may differ before login */ }
  }

  function enterApp() {
    $('#login-view').classList.add('hidden');
    $('#app').classList.remove('hidden');
    showPage(location.hash === '#system' ? 'system' : 'dashboard');
  }

  boot();
})();
