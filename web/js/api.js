/* LeanDNS API client — ubus JSON-RPC on device, /api mock on host */
(function (global) {
  const MODE = (typeof location !== 'undefined' && location.port === '8765') ? 'mock' : 'ubus';
  const state = {
    mode: MODE,
    session: localStorage.getItem('leandns_session') || '',
    username: localStorage.getItem('leandns_user') || 'root'
  };

  function toastCapable() {}

  async function ubusCall(object, method, params, session) {
    const sid = session || state.session || '00000000000000000000000000000000';
    const body = {
      jsonrpc: '2.0',
      id: Date.now(),
      method: 'call',
      params: [sid, object, method, params || {}]
    };
    const res = await fetch('/ubus', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    const text = await res.text();
    let data;
    try {
      data = JSON.parse(text);
    } catch (_) {
      throw new Error(
        res.status === 404
          ? 'ubus 엔드포인트 없음(uhttpd-mod-ubus 설치 필요)'
          : ('ubus 응답이 JSON이 아님: ' + text.slice(0, 80))
      );
    }
    if (data.error) throw new Error(data.error.message || 'ubus error');
    const result = data.result;
    if (Array.isArray(result) && result[0] !== 0) {
      throw new Error('ubus status ' + result[0]);
    }
    return Array.isArray(result) ? (result[1] || {}) : (result || {});
  }

  async function mockCall(method, params) {
    const res = await fetch('/api/' + method, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Session': state.session || ''
      },
      body: JSON.stringify(params || {})
    });
    const data = await res.json();
    if (!res.ok || data.error) throw new Error((data && data.error) || res.statusText);
    return data;
  }

  async function call(method, params) {
    if (state.mode === 'mock') return mockCall(method, params);
    return ubusCall('leandns', method, params);
  }

  async function login(username, password) {
    if (state.mode === 'mock') {
      const data = await mockCall('login', { username, password });
      state.session = data.session;
      state.username = username;
      localStorage.setItem('leandns_session', state.session);
      localStorage.setItem('leandns_user', username);
      return data;
    }
    const result = await ubusCall('session', 'login', {
      username: username,
      password: password,
      timeout: 3600
    }, '00000000000000000000000000000000');
    state.session = result.ubus_rpc_session;
    state.username = username;
    localStorage.setItem('leandns_session', state.session);
    localStorage.setItem('leandns_user', username);
    // grant leandns ACL via session (already bound to user ACLs on OpenWrt)
    return result;
  }

  async function logout() {
    try {
      if (state.mode === 'mock') await mockCall('logout', {});
      else if (state.session) await ubusCall('session', 'destroy', {});
    } catch (_) { /* ignore */ }
    state.session = '';
    localStorage.removeItem('leandns_session');
  }

  function isAuthed() {
    return !!(state.session && state.session !== '00000000000000000000000000000000');
  }

  global.LeanAPI = { state, call, login, logout, isAuthed, ubusCall };
})(window);
