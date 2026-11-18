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
  let allowAll = [];
  let blockAll = [];

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
  }

  function showPage(name) {
    $$('.page').forEach((p) => p.classList.add('hidden'));
    const el = $('#page-' + name);
    if (el) el.classList.remove('hidden');
    $$('.nav').forEach((b) => b.classList.toggle('active', b.dataset.page === name));
    $('#page-title').textContent = titles[name] || name;
    if (name === 'dashboard') refreshStatus();
    if (name === 'dns') loadDns();
    if (name === 'adblock') loadAdblock();
    if (name === 'lists') loadLists();
    if (name === 'system') loadSystem();
  }

  async function refreshStatus() {
    try {
      const s = await LeanAPI.call('status');
      $('#st-dns').textContent = s.dnsmasq_running ? '실행 중' : '중지됨';
      const ab = s.adblock || {};
      $('#st-adblock').textContent = ab.adblock_state || '—';
      $('#st-mem').textContent = fmtBytesKb(s.mem_available_kb) + ' / ' + fmtBytesKb(s.mem_total_kb);
      $('#st-cpu').textContent = s.cpu_percent === 'unsupported' ? '지원하지 않음' : (s.cpu_percent + '%');
      $('#st-rules').textContent = ab.rule_count === 'unsupported' ? '지원하지 않음' : (ab.rule_count || '—');
      const rtt = s.dns_test_latency_ms;
      $('#st-rtt').textContent = (s.dns_test_ok === 'true' || s.dns_test_ok === true)
        ? ((rtt === 'unsupported' ? '성공' : rtt + ' ms') + ' (' + (s.dns_test_host || '') + ')')
        : (s.dns_test_ok === 'unsupported' ? '지원하지 않음' : '실패');
      $('#st-upd').textContent = ab.last_update || '—';
      $('#st-up').textContent = fmtUptime(s.uptime_sec);
    } catch (e) {
      showToast('상태 조회 실패: ' + e.message, false);
    }
  }

  async function loadDns() {
    try {
      const d = await LeanAPI.call('dns_get');
      $('#dns-upstream').value = (d.upstream || []).join('\n');
      $('#dns-cache').value = d.cachesize || 1000;
      $('#dns-domain').value = d.internal_domain || 'home.arpa';
      $('#dns-test-host').value = d.dns_test_host || 'one.one.one.one';
      $('#dns-ipv6').checked = !!d.ipv6_dns;
      const h = await LeanAPI.call('hosts_list');
      hostsCache = h.hosts || [];
      renderHosts();
    } catch (e) {
      showToast('DNS 설정 로드 실패: ' + e.message, false);
    }
  }

  function renderHosts() {
    const body = $('#hosts-body');
    body.innerHTML = '';
    hostsCache.forEach((row, idx) => {
      const tr = document.createElement('tr');
      tr.innerHTML = '<td></td><td></td><td></td>';
      tr.children[0].textContent = row.hostname;
      tr.children[1].textContent = row.ip;
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'secondary';
      btn.textContent = '삭제';
      btn.addEventListener('click', (ev) => {
        runBusy(ev, async () => {
          hostsCache.splice(idx, 1);
          await saveHosts();
        });
      });
      tr.children[2].appendChild(btn);
      body.appendChild(tr);
    });
  }

  async function saveHosts() {
    try {
      const r = await LeanAPI.call('hosts_set', { hosts: hostsCache });
      if (r.ok === false) throw new Error(r.error || '실패');
      showToast('내부 DNS 저장됨', true);
      renderHosts();
    } catch (e) {
      showToast(e.message, false);
      loadDns();
    }
  }

  async function loadAdblock() {
    try {
      const a = await LeanAPI.call('adblock_status');
      $('#adblock-enabled').checked = a.adblock_state === 'enabled';
      $('#adblock-state').textContent = a.adblock_available === false ? 'adblock-lean 미설치' : (a.adblock_state || '—');
      $('#adblock-rules').textContent = a.rule_count === 'unsupported' ? '지원하지 않음' : (a.rule_count || '—');
      $('#adblock-upd').textContent = a.last_update || '—';
    } catch (e) {
      showToast(e.message, false);
    }
  }

  function filterLines(text, q) {
    if (!q) return text;
    return text.split('\n').filter((l) => l.toLowerCase().includes(q.toLowerCase())).join('\n');
  }

  async function loadLists() {
    try {
      const l = await LeanAPI.call('lists_get');
      allowAll = l.allow || [];
      blockAll = l.block || [];
      $('#allow-list').value = allowAll.join('\n');
      $('#block-list').value = blockAll.join('\n');
    } catch (e) {
      showToast(e.message, false);
    }
  }

  function showUdpToken(t) {
    const required = t.required !== false;
    $('#udp-token').textContent = t.token || '—';
    const box = $('#udp-token-required');
    if (box) box.checked = required;
    const hint = $('#udp-token-hint');
    const line = $('#udp-token-line');
    if (hint) {
      hint.textContent = required
        ? '켜져 있습니다. leandns-tool set 에 --token 이 필요합니다.'
        : '꺼져 있습니다. 같은 LAN에서 leandns-tool set 으로 토큰 없이 IP를 바꿀 수 있습니다.';
      hint.classList.toggle('warn', !required);
    }
    if (line) line.classList.toggle('muted', !required);
  }

  async function loadSystem() {
    try {
      const s = await LeanAPI.call('system_info');
      $('#sys-flash').textContent = fmtBytesKb(s.flash_free_kb) + ' / ' + fmtBytesKb(s.flash_total_kb);
      $('#sys-mem').textContent = fmtBytesKb(s.mem_available_kb) + ' / ' + fmtBytesKb(s.mem_total_kb);
      const n = await LeanAPI.call('network_get');
      $('#net-ip').value = n.ipaddr || '';
      $('#net-mask').value = n.netmask || '';
      $('#net-gw').value = n.gateway || '';
      $('#sys-net').textContent = (n.ipaddr || '—') + ' → GW ' + (n.gateway || '—');
      const t = await LeanAPI.call('udp_token_get');
      showUdpToken(t);
      const logs = await LeanAPI.call('logs_get', { lines: 100 });
      $('#sys-logs').textContent = (logs.lines || []).join('\n') || '(로그 없음)';
    } catch (e) {
      showToast(e.message, false);
    }
  }

  async function boot() {
    const theme = localStorage.getItem('leandns_theme') || 'light';
    setTheme(theme);

    $$('.nav').forEach((b) => b.addEventListener('click', () => showPage(b.dataset.page)));
    $('#theme-toggle').addEventListener('click', () => {
      const cur = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      setTheme(cur);
    });
    $('#logout-btn').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        await LeanAPI.logout();
        location.reload();
      });
    });
    $('#btn-refresh-status').addEventListener('click', (ev) => {
      runBusy(ev, refreshStatus);
    });

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

    $('#btn-dns-test').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        try {
          const r = await LeanAPI.call('dns_test');
          showToast('테스트: ' + (r.dns_test_ok || r.ok) + ' / ' + (r.dns_test_latency_ms || '?') + ' ms', true);
        } catch (e) {
          showToast(e.message, false);
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
        hostsCache = hostsCache.filter((h) => h.hostname !== hostname);
        hostsCache.push({ hostname, ip });
        $('#host-name').value = '';
        $('#host-ip').value = '';
        await saveHosts();
      });
    });

    $('#adblock-form').addEventListener('submit', (ev) => {
      ev.preventDefault();
      runBusy(ev, async () => {
        try {
          const r = await LeanAPI.call('adblock_set', { enabled: $('#adblock-enabled').checked });
          if (r.ok === false) throw new Error(r.error || '실패');
          showToast('광고 차단 설정 적용', true);
          loadAdblock();
        } catch (e) {
          showToast(e.message, false);
        }
      });
    });
    $('#btn-adblock-update').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        try {
          const r = await LeanAPI.call('adblock_update');
          if (r.ok === false) throw new Error(r.error || '업데이트 실패');
          showToast('차단 목록 업데이트 완료', true);
          loadAdblock();
        } catch (e) {
          showToast(e.message, false);
        }
      });
    });

    $('#allow-search').addEventListener('input', (e) => {
      $('#allow-list').value = filterLines(allowAll.join('\n'), e.target.value);
    });
    $('#block-search').addEventListener('input', (e) => {
      $('#block-list').value = filterLines(blockAll.join('\n'), e.target.value);
    });
    $('#btn-lists-save').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        const allow = $('#allow-list').value.split(/\n+/).map((s) => s.trim()).filter(Boolean);
        const block = $('#block-list').value.split(/\n+/).map((s) => s.trim()).filter(Boolean);
        try {
          const r = await LeanAPI.call('lists_set', { allow, block });
          if (r.ok === false) throw new Error(r.error || '실패');
          showToast('목록 저장됨', true);
          loadLists();
        } catch (e) {
          showToast(e.message, false);
        }
      });
    });

    $('#btn-logs').addEventListener('click', (ev) => {
      runBusy(ev, loadSystem);
    });
    $('#btn-logs-clear').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        await LeanAPI.call('logs_clear');
        showToast('로그 초기화 요청됨', true);
        await loadSystem();
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
      runBusy(ev, async () => {
        const ipaddr = $('#net-ip').value.trim();
        const netmask = $('#net-mask').value.trim();
        const gateway = $('#net-gw').value.trim();
        try {
          const r = await LeanAPI.call('network_set', { ipaddr, netmask, gateway });
          if (r.ok === false) throw new Error(r.error || '네트워크 적용 실패');
          showToast('네트워크 적용됨. 새 IP로 다시 접속하세요: ' + ipaddr, true);
        } catch (e) {
          showToast(e.message, false);
        }
      });
    });
    $('#udp-token-required').addEventListener('change', (ev) => {
      const box = $('#udp-token-required');
      const required = box.checked;
      if (!required && !confirm('토큰 확인을 끄면 같은 LAN의 누구나 관리 IP를 바꿀 수 있습니다. 계속할까요?')) {
        box.checked = true;
        return;
      }
      runBusy(ev, async () => {
        try {
          const r = await LeanAPI.call('udp_token_set', { required });
          if (r.ok === false) throw new Error(r.error || '설정 실패');
          showUdpToken({ token: $('#udp-token').textContent, required: r.required !== false });
          showToast(required ? 'UDP 토큰 확인을 켰습니다' : 'UDP 토큰 확인을 껐습니다. 토큰 없이 IP를 바꿀 수 있습니다', true);
        } catch (e) {
          box.checked = !required;
          showToast(e.message, false);
        }
      });
    });
    $('#btn-udp-regen').addEventListener('click', (ev) => {
      runBusy(ev, async () => {
        try {
          const r = await LeanAPI.call('udp_token_regen');
          $('#udp-token').textContent = r.token || '—';
          showToast('UDP 토큰 재발급됨', true);
        } catch (e) {
          showToast(e.message, false);
        }
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
      LeanAPI.login($('#login-user').value.trim(), $('#login-pass').value).then(() => {
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
        await LeanAPI.call('ping');
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
    showPage('dashboard');
  }

  boot();
})();
