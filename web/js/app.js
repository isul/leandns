(function () {
  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => Array.from(document.querySelectorAll(sel));
  const titles = {
    dashboard: '대시보드',
    dns: 'DNS 설정',
    adblock: '광고 차단',
    lists: '허용/차단',
    system: '시스템',
    help: '도움말'
  };

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
    const t = $('#toast');
    t.textContent = msg;
    t.classList.remove('hidden', 'ok', 'err', 'busy');
    if (ok === 'busy') t.classList.add('busy');
    else t.classList.add(ok ? 'ok' : 'err');
    clearTimeout(showToast._timer);
    if (ok !== 'busy') {
      showToast._timer = setTimeout(() => t.classList.add('hidden'), 3500);
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
    showToast('처리중...', 'busy');
    try {
      await work();
    } catch (e) {
      showToast(e.message || '요청 실패', false);
    } finally {
      if (ctl) ctl.disabled = false;
      const t = $('#toast');
      if (t && t.classList.contains('busy')) t.classList.add('hidden');
    }
  }

  function fmtBytesKb(kb) {
    if (kb == null || kb === 'unsupported') return '지원하지 않음';
    const n = Number(kb);
    if (n > 1024) return (n / 1024).toFixed(1) + ' MB';
    return n + ' KB';
  }

  function fmtUptime(sec) {
    sec = Number(sec) || 0;
    const d = Math.floor(sec / 86400);
    const h = Math.floor((sec % 86400) / 3600);
    const m = Math.floor((sec % 3600) / 60);
    return d + '일 ' + h + '시간 ' + m + '분';
  }

  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('leandns_theme', theme);
    $$('.theme-toggle').forEach((btn) => {
      btn.setAttribute('aria-label', theme === 'dark' ? '라이트 테마' : '다크 테마');
    });
  }

  function setDrawer(open) {
    document.body.classList.toggle('drawer-open', open);
    const toggle = $('#menu-toggle');
    const backdrop = $('#drawer-backdrop');
    if (toggle) {
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
      toggle.setAttribute('aria-label', open ? '메뉴 닫기' : '메뉴 열기');
    }
    if (backdrop) backdrop.setAttribute('aria-hidden', open ? 'false' : 'true');
  }

  function showPage(name) {
    $$('.page').forEach((p) => p.classList.add('hidden'));
    const el = $('#page-' + name);
    if (el) el.classList.remove('hidden');
    $$('.nav').forEach((b) => b.classList.toggle('active', b.dataset.page === name));
    $('#page-title').textContent = titles[name] || name;
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
    if (value === 0) return precision + ' ms 미만';
    return (precision > 1 ? '약 ' : '') + value + ' ms';
  }

  function dnsSucceeded(s) {
    return s.dns_test_ok === true || s.dns_test_ok === 'true';
  }

  function flashScope(s) {
    return s.flash_scope === 'overlay' ? '쓰기 가능 영역 (/overlay)' : '루트 파일시스템 (/)';
  }

  function enabledAdblock(a) {
    return a.leandns_enabled == null ? a.adblock_state === 'enabled' : String(a.leandns_enabled) === '1';
  }

  function countRules(a) {
    const count = Number(a.rule_count);
    return a.rule_count != null && Number.isFinite(count) ? count.toLocaleString('ko-KR') : '—';
  }

  function fmtCount(n) {
    const v = Number(n);
    return Number.isFinite(v) ? v.toLocaleString('ko-KR') : '—';
  }

  function fmtAge(sec) {
    const v = Number(sec);
    if (!Number.isFinite(v) || v < 0) return '';
    if (v < 60) return '마지막 차단 ' + v + '초 전';
    if (v < 3600) return '마지막 차단 ' + Math.floor(v / 60) + '분 전';
    return '마지막 차단 ' + Math.floor(v / 3600) + '시간 전';
  }

  function fmtDelta(today, yesterday) {
    const t = Number(today);
    const y = Number(yesterday);
    if (!Number.isFinite(t) || !Number.isFinite(y) || y <= 0) return '재부팅 후 집계';
    const pct = Math.round(((t - y) / y) * 100);
    if (pct === 0) return '어제와 같음';
    return (pct > 0 ? '+' : '') + pct + '% 어제 대비';
  }

  function typeClass(label) {
    if (label === '광고') return 'type-ad';
    if (label === '추적') return 'type-track';
    return 'type-block';
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
      el.innerHTML = '<p class="muted">추이 데이터 없음</p>';
      return;
    }
    const max = Math.max(1, ...rows.map((r) => Number(r.c) || 0));
    el.innerHTML = rows.map((r) => {
      const c = Number(r.c) || 0;
      const h = Math.max(8, Math.round((c / max) * 100));
      const label = trendLabel(r);
      return '<div class="trend-col" title="' + label + ' · ' + c + '건">' +
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
    if (title) title.textContent = '최근 차단 ' + limit + '개 도메인';
    if (hint) {
      hint.textContent = bs && bs.paused ? '일시 중지됨 (중요 작업 중)'
        : (limit <= 10 ? '저메모리 · 최근 10건' : '메모리 전용');
    }
    const rows = (bs && Array.isArray(bs.recent)) ? bs.recent : [];
    if (!rows.length) {
      body.innerHTML = '<tr><td colspan="5" class="muted">아직 차단 기록이 없습니다.</td></tr>';
      return;
    }
    body.innerHTML = rows.map((r) => {
      const type = r.type || '차단';
      const time = Number.isFinite(Number(r.ts)) ? fmtLocalHms(r.ts) : (r.time || '—');
      return '<tr>' +
        '<td>' + (r.n || '') + '</td>' +
        '<td>' + time + '</td>' +
        '<td class="domain">' + (r.domain || '—') + '</td>' +
        '<td><span class="type-pill ' + typeClass(type) + '">' + type + '</span></td>' +
        '<td>' + (r.client || '—') + '</td>' +
        '</tr>';
    }).join('');
  }

  function updateBlockStats(s) {
    const bs = s.block_stats || {};
    const enabled = bs.enabled === true || bs.enabled === 'true';
    const paused = bs.paused === true || bs.paused === 'true';
    if (!enabled) {
      metric('#st-block-10m', '꺼짐');
      metric('#st-block-last', '질의 로그 비활성');
      metric('#st-block-today', '—');
      metric('#st-block-delta', '');
      metric('#st-sum-1m', '—');
      metric('#st-sum-10m', '—');
      metric('#st-sum-today', '—');
      metric('#st-sum-state', '수집 안 함');
      updateBlockTrend([]);
      updateRecentBlocks({ recent_limit: 20, recent: [], paused: false });
      metric('#st-block-trend-note', '설정에서 질의 로그를 켜면 표시됩니다.');
      return;
    }
    metric('#st-block-10m', fmtCount(bs.count_10m) + '건');
    metric('#st-block-last', fmtAge(bs.last_block_age_sec) || (bs.count_today ? '' : '아직 차단 없음'));
    metric('#st-block-today', fmtCount(bs.count_today) + '건');
    metric('#st-block-delta', fmtDelta(bs.count_today, bs.count_yesterday), Number(bs.count_today) >= Number(bs.count_yesterday) ? 'ok' : '');
    metric('#st-sum-1m', fmtCount(bs.count_1m) + '건');
    metric('#st-sum-10m', fmtCount(bs.count_10m) + '건');
    metric('#st-sum-today', fmtCount(bs.count_today) + '건');
    metric('#st-sum-state', paused ? '일시 중지' : (Number(bs.recent_limit) <= 10 ? '저메모리 모드' : '수집 중'),
      paused ? 'warn' : 'ok');
    updateBlockTrend(bs.trend);
    updateRecentBlocks(bs);
    metric('#st-block-trend-note', '분당 차단 수 · 최근 10분');
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
    const dns = !s.dnsmasq_running ? ['중지됨', 'error'] : dnsSucceeded(s)
      ? ['정상', 'ok'] : s.dns_test_ok === 'unsupported' ? ['실행 중', ''] : ['조회 실패', 'warn'];
    metric('#st-dns', ...dns);
    metric('#st-rtt', [s.dns_test_host, dnsSucceeded(s) && fmtLatency(s)].filter(Boolean).join(' · '));
    const adblock = a.list_state === 'updating' ? ['업데이트 중', 'warn']
      : a.list_state === 'applied' ? ['적용됨', 'ok']
      : !a.adblock_available ? ['미설치', 'warn']
      : enabledAdblock(a) ? ['적용 확인 필요', 'warn'] : ['비활성', ''];
    metric('#st-adblock', ...adblock);
    metric('#st-rules', a.list_state === 'applied' && countRules(a) !== '—' ? countRules(a) + '개 규칙' : '');
    updateBlockStats(s);
    const hasAvailableRam = Number.isFinite(s.mem_available_kb) && s.mem_available_kb >= 0;
    const used = hasAvailableRam ? s.mem_total_kb - s.mem_available_kb : null;
    updateResourceMeter('#st-mem-meter', '#st-mem-used', used, s.mem_total_kb);
    metric('#st-mem-available', hasAvailableRam ? '가용 RAM ' + fmtBytesKb(s.mem_available_kb) : '');
    metric('#st-flash-label', 'FLASH');
    updateResourceMeter('#st-flash-meter', '#st-flash-total', s.flash_free_kb, s.flash_total_kb);
    metric('#st-flash-scope', flashScope(s));
    metric('#st-up', fmtUptime(s.uptime_sec));
    setVersionLabels(s);
    metric('#st-upstream', (s.upstream || []).join(', ') || '—');
    metric('#st-domain', s.internal_domain || '—');
    metric('#st-upd', fmtDate(a.last_update));
    metric('#st-checked', '최근 확인 ' + fmtDate(new Date()));
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
      metric('#st-checked', '상태 조회 실패 · ' + e.message, 'error');
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
      showToast('DNS 설정 로드 실패: ' + e.message, false);
    }
  }

  function renderHosts() {
    const body = $('#hosts-body');
    body.innerHTML = '';
    if (!hostsCache.length) {
      const row = body.insertRow().insertCell();
      row.colSpan = 3;
      row.textContent = '등록된 내부 DNS 레코드가 없습니다.';
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
      edit.textContent = '수정';
      edit.addEventListener('click', () => {
        editingHost = row.hostname;
        $('#host-name').value = row.hostname;
        $('#host-ip').value = row.ip;
        $('#host-submit').textContent = '저장';
        $('#host-cancel').classList.remove('hidden');
        $('#host-name').focus();
      });
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'secondary';
      remove.textContent = '삭제';
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
    $('#host-submit').textContent = '추가';
    $('#host-cancel').classList.add('hidden');
  }

  async function saveHosts(hosts) {
    if (hostsSaving) return;
    hostsSaving = true;
    try {
      const r = await LeanAPI.call('hosts_set', { hosts });
      if (r.ok === false) throw new Error(r.error || '저장 실패');
      hostsCache = hosts;
      resetHostForm();
      renderHosts();
      showToast('내부 DNS 저장됨', true);
    } finally {
      hostsSaving = false;
    }
  }

  async function loadAdblock() {
    try {
      const a = await LeanAPI.call('adblock_status');
      const enabled = enabledAdblock(a);
      $('#adblock-enabled').checked = enabled;
      metric('#adblock-state', enabled ? '활성' : '비활성');
      metric('#adblock-engine', ({
        ok: '정상', error: '오류', missing: '미설치', stopped: '중지됨', checking: '확인 대기'
      })[a.engine_state] || '확인 필요', a.engine_state === 'error' ? 'error' : '');
      metric('#adblock-list-state', ({
        applied: '적용됨', not_applied: '미적용', updating: '업데이트 중', unknown: '확인 필요'
      })[a.list_state] || '확인 필요', a.list_state === 'applied' ? 'ok' : 'warn');
      metric('#adblock-rules', countRules(a));
      metric('#adblock-upd', fmtDate(a.last_update));
      const messages = {
        success: '성공', updating: '진행 중', low_ram: '실패 · 가용 RAM 부족',
        low_tmp: '실패 · 임시 공간 부족', failed: '실패 · 시스템 로그 확인'
      };
      metric('#adblock-result', messages[a.update_result] || '기록 없음');
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
    const range = pages > 1 ? ' · ' + (start + 1) + '–' + Math.min(start + pageSize, matches.length) : '';
    $('#list-count').textContent = (query ? '검색 결과 ' + matches.length + ' / ' : '전체 ') + all.length + '개' + range;
    $('#list-prev').disabled = listPage === 0;
    $('#list-next').disabled = listPage >= pages - 1;
    $('#btn-lists-save').disabled = !listsDirty;
    $('#list-dirty').classList.toggle('hidden', !listsDirty);
    if (!matches.length) {
      const item = document.createElement('li');
      item.textContent = query ? '검색 결과가 없습니다.' : '등록된 도메인이 없습니다.';
      entries.appendChild(item);
    }
    for (const domain of matches.slice(start, start + pageSize)) {
      const item = document.createElement('li');
      const label = document.createElement('span');
      label.textContent = domain;
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'secondary';
      remove.textContent = '삭제';
      remove.setAttribute('aria-label', domain + ' 삭제');
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
      if (domain.length > 253 || !valid.test(domain)) throw new Error('도메인 형식 확인: ' + raw);
      if (!normalized.has(domain)) additions.push(domain);
      normalized.add(domain);
    }
    if (!additions.length) {
      showToast('추가할 새 도메인이 없습니다.', false);
      return;
    }
    lists[currentList] = lists[currentList].concat(additions).sort();
    listsDirty = true;
    $('#list-search').value = '';
    listPage = 0;
    renderLists();
    showToast(additions.length + '개 추가됨. 목록 저장을 눌러 적용하세요.', true);
  }

  function hideToken() {
    $('#udp-token').textContent = '';
    $('#udp-token-line').classList.add('hidden');
    $('#btn-udp-reveal').textContent = '토큰 표시';
  }

  function revealToken(token) {
    $('#udp-token').textContent = token;
    $('#udp-token-line').classList.remove('hidden');
    $('#btn-udp-reveal').textContent = '토큰 숨기기';
  }

  function updateNetwork(s) {
    $('#net-ip').value = s.ipaddr || '';
    $('#net-mask').value = s.netmask || '';
    $('#net-gw').value = s.gateway || '';
    $('#sys-net').textContent = (s.ipaddr || '—') + ' · GW ' + (s.gateway || '—');
    const pending = s.pending_ip || '';
    $('#net-apply').disabled = !!pending;
    $('#net-pending').classList.toggle('hidden', !pending);
    if (!pending) return;
    const isNewAddress = LeanAPI.state.mode === 'mock' || location.hostname === pending;
    const ready = s.pending_state === 'ready';
    $('#net-confirm').classList.toggle('hidden', !isNewAddress || !ready);
    const status = {
      applying: '적용 준비 중입니다.',
      ready: '120초 안에 새 주소에서 로그인한 뒤 변경을 확정하세요.',
      restore_failed: '자동 복구에 실패했습니다. 시스템 로그를 확인하세요.'
    };
    metric('#net-pending-text', pending + ' · ' + (status[s.pending_state] || status.applying),
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
    $('#sys-logs').textContent = (logs.lines || []).join('\n') || '(로그 없음)';
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
    if (msg != null) metric('#fw-status', msg, /실패|불가|부족|factory/i.test(String(msg)) ? 'error' : (st.verified ? 'ok' : ''));
    else if (st.image_present && st.verified) {
      metric('#fw-status',
        '검사 통과 · ' + fmtBytesKb(st.image_kb) +
        ' · 가용 RAM ' + fmtBytesKb(st.mem_available_kb) +
        ' · /tmp ' + fmtBytesKb(st.tmp_free_kb),
        'ok');
    } else if (st.image_present) {
      metric('#fw-status',
        '업로드됨(미검사) · ' + fmtBytesKb(st.image_kb) +
        ' · 가용 RAM ' + fmtBytesKb(st.mem_available_kb),
        'warn');
    } else {
      metric('#fw-status',
        '대기 · 가용 RAM ' + fmtBytesKb(st.mem_available_kb) +
        ' · /tmp ' + fmtBytesKb(st.tmp_free_kb));
    }
    return st;
  }

  async function loadSystem() {
    try {
      const [s, n, t] = await Promise.all([
        LeanAPI.call('system_info'), LeanAPI.call('network_get'), LeanAPI.call('udp_token_get')
      ]);
      setVersionLabels(s);
      $('#sys-flash-label').textContent = flashScope(s) + ' 여유';
      $('#sys-flash').textContent = fmtBytesKb(s.flash_free_kb) + ' / ' + fmtBytesKb(s.flash_total_kb);
      $('#sys-mem').textContent = fmtBytesKb(s.mem_available_kb) + ' / ' + fmtBytesKb(s.mem_total_kb);
      updateNetwork(n);
      $('#udp-token-required').checked = t.required !== false;
      $('#udp-token-required').disabled = false;
      try {
        await refreshFirmwareStatus();
      } catch (_) {
        metric('#fw-status', '펌웨어 상태 조회 불가');
      }
      await loadLogs();
    } catch (e) {
      showToast(e.message, false);
    }
  }

  async function boot() {
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
          if (r.ok === false) throw new Error(r.error || '저장 실패');
          showToast('DNS 설정 적용됨', true);
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
        metric('#dns-result', host + ' 조회 중…');
        try {
          const r = await LeanAPI.call('dns_test', { host });
          if (r.ok === false) throw new Error(r.error || '조회 실패');
          const ok = dnsSucceeded(r);
          const status = ok ? 'DNS 조회 성공' : r.dns_test_ok === 'unsupported' ? 'DNS 조회 불가' : 'DNS 조회 실패';
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
          showToast('DNS 재시작됨', true);
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
          throw new Error('같은 호스트가 이미 있습니다. 목록에서 수정하세요.');
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
          if (r.ok === false) throw new Error(r.error || '설정 실패');
          showToast('광고 차단 설정 적용됨', true);
        } finally {
          await loadAdblock();
        }
      });
    });
    $('#btn-adblock-status').addEventListener('click', (ev) => runBusy(ev, loadAdblock));
    $('#btn-adblock-update').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        const update = LeanAPI.call('adblock_update');
        metric('#adblock-list-state', '업데이트 요청 중', 'warn');
        try {
          const r = await update;
          if (r.ok === false) throw new Error(r.error || '업데이트 실패');
          showToast(r.started === 'background' ? '업데이트 시작됨' : '목록 업데이트 완료', true);
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
          if (r.ok === false) throw new Error(r.error || '저장 실패');
          listsDirty = false;
          renderLists();
          showToast('목록 저장됨. 광고 차단 화면에서 목록을 갱신하면 적용됩니다.', true);
        } finally {
          controls.disabled = false;
        }
      });
    });

    $('#btn-logs').addEventListener('click', (ev) => runBusy(ev, loadLogs));
    $('#btn-logs-clear').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        await LeanAPI.call('logs_clear');
        showToast('로그 초기화 요청됨', true);
        await loadLogs();
      });
    });
    $('#btn-svc-restart').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        await LeanAPI.call('system_restart_services');
        showToast('서비스 재시작됨', true);
      });
    });
    $('#net-form').addEventListener('submit', (ev) => {
      ev.preventDefault();
      const ipaddr = $('#net-ip').value.trim();
      const netmask = $('#net-mask').value.trim();
      const gateway = $('#net-gw').value.trim();
      if (!confirm(ipaddr + '에 네트워크 설정을 적용할까요?\n즉시 영구 반영되며 자동으로 되돌리지 않습니다.')) return;
      runBusy(null, async () => {
        $('#net-apply').disabled = true;
        try {
          const r = await LeanAPI.call('network_set', { ipaddr, netmask, gateway });
          if (r.ok === false) throw new Error(r.error || '네트워크 적용 실패');
          updateNetwork({ ipaddr, netmask, gateway, pending_ip: '', pending_state: '' });
          if (LeanAPI.state.mode !== 'mock' && location.hostname !== ipaddr) {
            const url = new URL(location.href);
            url.hostname = ipaddr;
            url.hash = 'system';
            showToast('적용됨 · 새 주소로 접속: ' + ipaddr, true);
            window.setTimeout(() => { location.href = url.href; }, 1200);
          } else {
            showToast('네트워크 설정이 적용되었습니다', true);
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
        if (r.ok === false) throw new Error(r.error || '변경 확정 실패');
        updateNetwork(await LeanAPI.call('network_get'));
        showToast('네트워크 설정 저장됨', true);
      });
    });
    $('#udp-token-required').addEventListener('change', (ev) => {
      const box = ev.currentTarget;
      const required = box.checked;
      runBusy(ev, async () => {
        try {
          const r = await LeanAPI.call('udp_token_set', { required, enabled: true });
          if (r.ok === false) throw new Error(r.error || '설정 실패');
          box.checked = r.required !== false;
          showToast(required ? 'UDP IP 변경에 토큰이 필요합니다.' : '토큰 없이 UDP IP 변경을 허용했습니다.', true);
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
        const t = await LeanAPI.call('udp_token_get', { reveal: true });
        if (!t.token) throw new Error(t.error || '토큰 조회 실패');
        if (currentPage === 'system') revealToken(t.token);
      });
    });
    $('#btn-udp-regen').addEventListener('click', (ev) => {
      if (!confirm('토큰을 재발급하면 기존 토큰을 사용할 수 없습니다. 계속할까요?')) return;
      runBusy(ev, async () => {
        const r = await LeanAPI.call('udp_token_regen');
        if (r.ok === false) throw new Error(r.error || '재발급 실패');
        hideToken();
        showToast('UDP 토큰 재발급됨', true);
      });
    });
    $$('.copy-command').forEach((button) => button.addEventListener('click', async () => {
      const code = button.previousElementSibling;
      try {
        await navigator.clipboard.writeText(code.textContent);
        showToast('명령어 복사됨', true);
      } catch (_) {
        const range = document.createRange();
        range.selectNodeContents(code);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        if (document.execCommand('copy')) showToast('명령어 복사됨', true);
        else showToast('선택된 명령어를 복사하세요.', false);
      }
    }));
    $('#fw-file').addEventListener('change', () => {
      const file = $('#fw-file').files && $('#fw-file').files[0];
      $('#fw-file-label').textContent = file
        ? (file.name + ' · ' + fmtBytesKb(Math.ceil(file.size / 1024)))
        : '선택된 파일 없음';
      $('#btn-fw-apply').disabled = true;
    });

    $('#btn-fw-upload').addEventListener('click', (ev) => {
      const file = $('#fw-file').files && $('#fw-file').files[0];
      if (!file) {
        showToast('sysupgrade .bin 파일을 선택하세요.', false);
        return;
      }
      if (!isSysupgradeName(file.name)) {
        showToast('factory.bin이 아닙니다. *-sysupgrade.bin 파일을 선택하세요.', false);
        metric('#fw-status', 'factory.bin은 Firmware Restoration용입니다. sysupgrade.bin을 사용하세요.', 'error');
        return;
      }
      runBusy(ev, async () => {
        metric('#fw-status', 'RAM 확보 및 준비 중…', 'warn');
        const prep = await LeanAPI.call('firmware_prepare', { size: file.size });
        if (prep.ok === false) throw new Error(prep.error || '준비 실패');
        metric('#fw-status', '업로드 중… 0%', 'warn');
        const up = await LeanAPI.uploadFirmware(file, (p) => {
          metric('#fw-status', '업로드 중… ' + Math.round(p * 100) + '%', 'warn');
        });
        if (up.ok === false) throw new Error(up.error || '업로드 실패');
        metric('#fw-status', '이미지 검사 중…', 'warn');
        const ver = await LeanAPI.call('firmware_verify');
        if (ver.ok === false) {
          await LeanAPI.call('firmware_abort').catch(() => {});
          $('#btn-fw-apply').disabled = true;
          throw new Error(ver.error || '이미지 검사 실패');
        }
        await refreshFirmwareStatus('검사 통과 · 업그레이드 적용을 눌러 진행하세요.');
        showToast('펌웨어 업로드·검사 완료', true);
      });
    });

    $('#btn-fw-abort').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        const r = await LeanAPI.call('firmware_abort');
        if (r.ok === false) throw new Error(r.error || '취소 실패');
        $('#fw-file').value = '';
        $('#fw-file-label').textContent = '선택된 파일 없음';
        await refreshFirmwareStatus('업로드가 취소되었습니다.');
        showToast('펌웨어 업로드 취소됨', true);
      });
    });

    $('#btn-fw-apply').addEventListener('click', (ev) => {
      const keep = $('#fw-keep').checked;
      const warn = keep
        ? '펌웨어를 적용하고 재부팅합니다. 설정은 유지됩니다. 전원을 유지하세요.'
        : '펌웨어를 적용하고 재부팅합니다. 설정이 초기화됩니다. 전원을 유지하세요.';
      if (!confirm(warn + '\n계속할까요?')) return;
      runBusy(ev, async () => {
        metric('#fw-status', '업그레이드 적용 중… 재부팅까지 기다리세요.', 'warn');
        let r;
        try {
          r = await LeanAPI.call('firmware_apply', { keep_settings: keep });
        } catch (e) {
          await refreshFirmwareStatus(e.message || '적용 실패');
          throw e;
        }
        if (r.ok === false) {
          await refreshFirmwareStatus(r.error || '적용 실패');
          throw new Error(r.error || '적용 실패');
        }
        showToast('업그레이드 시작됨 · 재부팅 대기', true);
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
            metric('#fw-status', '재부팅 중… 응답 대기 (' + tries + ')', 'warn');
          } else if (!sawDown) {
            metric('#fw-status', '플래시/재부팅 준비 중… 아직 이전 펌웨어가 응답 중 (' + tries + ')', 'warn');
          } else {
            metric('#fw-status', '재부팅 완료 · ' + (ping.firmware || 'OK'), 'ok');
            showToast('장치가 다시 온라인입니다. 다시 로그인하세요.', true);
            return;
          }
          if (tries > 120) {
            metric('#fw-status', '응답 없음 · 전원 LED와 복구 절차를 확인하세요.', 'error');
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
          const blob = new Blob([r.data_base64 || JSON.stringify(r)], { type: 'text/plain' });
          const a = document.createElement('a');
          a.href = URL.createObjectURL(blob);
          a.download = r.filename ? r.filename + '.b64' : 'leandns-backup.b64';
          a.click();
          showToast('백업 내보내기 완료', true);
        } catch (e) {
          showToast(e.message, false);
        }
      });
    });
    $('#import-file').addEventListener('change', (ev) => {
      const file = ev.target.files && ev.target.files[0];
      if (!file) return;
      runBusy(ev, async () => {
        const text = await file.text();
        try {
          const r = await LeanAPI.call('backup_import', { data_base64: text.trim() });
          if (r.ok === false) throw new Error(r.error || '가져오기 실패');
          showToast('설정 가져오기 완료', true);
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
        btn.textContent = '처리중...';
      }
      $('#login-error').textContent = '';
      LeanAPI.login($('#login-user').value.trim(), $('#login-pass').value).then(async () => {
        try {
          setVersionLabels(await LeanAPI.call('ping'));
        } catch (_) { /* status refresh will fill version */ }
        enterApp();
      }).catch((e) => {
        $('#login-error').textContent = '로그인 실패: ' + e.message;
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
