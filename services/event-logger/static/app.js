// --- Tab navigation ---
document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
        tab.classList.add('active');
        document.getElementById(tab.dataset.tab).classList.add('active');

        if (tab.dataset.tab === 'streams') loadStreams();
        if (tab.dataset.tab === 'consumers') loadStreamList();
        if (tab.dataset.tab === 'overview') loadOverview();
    });
});

// --- Toast ---
function showToast(msg, type = 'success') {
    const toast = document.getElementById('toast');
    toast.textContent = msg;
    toast.className = `toast ${type}`;
    setTimeout(() => toast.classList.add('hidden'), 3000);
}

// --- API helper ---
async function api(url, opts = {}) {
    try {
        const res = await fetch(url, {
            headers: { 'Content-Type': 'application/json' },
            ...opts
        });
        if (!res.ok) {
            const text = await res.text();
            throw new Error(text);
        }
        return await res.json();
    } catch (err) {
        showToast(err.message, 'error');
        throw err;
    }
}

// --- Overview ---
async function loadOverview() {
    try {
        const data = await api('/api/server');
        document.getElementById('ov-status').textContent = data.connected ? 'Connected' : 'Disconnected';
        document.getElementById('ov-streams').textContent = data.streams;
        document.getElementById('ov-consumers').textContent = data.consumers;
        document.getElementById('ov-messages').textContent = Number(data.total_messages).toLocaleString();
        document.getElementById('ov-bytes').textContent = formatBytes(data.total_bytes);
        document.getElementById('ov-url').textContent = data.server_url;

        const dot = document.getElementById('status-dot');
        const txt = document.getElementById('status-text');
        dot.className = `dot ${data.connected ? 'connected' : 'disconnected'}`;
        txt.textContent = data.connected ? 'NATS Connected' : 'NATS Disconnected';
    } catch (e) {
        document.getElementById('status-dot').className = 'dot disconnected';
        document.getElementById('status-text').textContent = 'API Unreachable';
    }
}

function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

// --- Streams ---
async function loadStreams() {
    const data = await api('/api/streams');
    const tbody = document.getElementById('streams-body');
    tbody.innerHTML = data.map(s => `
        <tr>
            <td><strong>${s.name}</strong></td>
            <td>${Array.isArray(s.subjects) ? s.subjects.join(', ') : s.subjects}</td>
            <td>${s.storage}</td>
            <td>${s.retention}</td>
            <td>${Number(s.messages).toLocaleString()}</td>
            <td>${formatBytes(s.bytes)}</td>
            <td>${s.consumers}</td>
            <td>${s.max_age}</td>
            <td><button class="btn-danger" onclick="deleteStream('${s.name}')">Delete</button></td>
        </tr>
    `).join('');
}

function showCreateStream() {
    document.getElementById('create-stream-form').classList.remove('hidden');
}

function hideCreateStream() {
    document.getElementById('create-stream-form').classList.add('hidden');
}

async function createStream() {
    const name = document.getElementById('cs-name').value.trim();
    const subjects = document.getElementById('cs-subjects').value.split(',').map(s => s.trim()).filter(Boolean);
    const storage = document.getElementById('cs-storage').value;
    const retention = document.getElementById('cs-retention').value;
    const maxAge = document.getElementById('cs-maxage').value.trim();

    if (!name || subjects.length === 0) {
        showToast('Name and subjects are required', 'error');
        return;
    }

    await api('/api/streams/create', {
        method: 'POST',
        body: JSON.stringify({ name, subjects, storage, retention, max_age: maxAge })
    });
    showToast(`Stream "${name}" created`);
    hideCreateStream();
    loadStreams();
}

async function deleteStream(name) {
    if (!confirm(`Delete stream "${name}"? This will delete all messages.`)) return;
    await api('/api/streams/delete', {
        method: 'POST',
        body: JSON.stringify({ name })
    });
    showToast(`Stream "${name}" deleted`);
    loadStreams();
}

// --- Consumers ---
async function loadStreamList() {
    const data = await api('/api/streams');
    const select = document.getElementById('consumer-stream-select');
    const current = select.value;
    select.innerHTML = '<option value="">Select a stream</option>' +
        data.map(s => `<option value="${s.name}" ${s.name === current ? 'selected' : ''}>${s.name}</option>`).join('');
    if (current) loadConsumers();
}

async function loadConsumers() {
    const stream = document.getElementById('consumer-stream-select').value;
    if (!stream) {
        document.getElementById('consumers-body').innerHTML = '';
        return;
    }
    const data = await api(`/api/consumers?stream=${stream}`);
    const tbody = document.getElementById('consumers-body');
    tbody.innerHTML = data.map(c => `
        <tr>
            <td><strong>${c.name}</strong></td>
            <td>${c.stream}</td>
            <td>${c.filter_subject || '*'}</td>
            <td>${c.ack_policy}</td>
            <td>${Number(c.num_pending).toLocaleString()}</td>
            <td>${Number(c.num_ack_pending).toLocaleString()}</td>
            <td>${c.num_redelivered}</td>
            <td><button class="btn-danger" onclick="deleteConsumer('${c.stream}','${c.name}')">Delete</button></td>
        </tr>
    `).join('');
}

function showCreateConsumer() {
    document.getElementById('create-consumer-form').classList.remove('hidden');
}

function hideCreateConsumer() {
    document.getElementById('create-consumer-form').classList.add('hidden');
}

async function createConsumer() {
    const stream = document.getElementById('consumer-stream-select').value;
    const name = document.getElementById('cc-name').value.trim();
    const filterSubject = document.getElementById('cc-filter').value.trim();
    const ackPolicy = document.getElementById('cc-ack').value;
    const deliverPolicy = document.getElementById('cc-deliver').value;

    if (!stream || !name) {
        showToast('Select a stream and provide a name', 'error');
        return;
    }

    await api('/api/consumers/create', {
        method: 'POST',
        body: JSON.stringify({
            stream, name,
            filter_subject: filterSubject,
            ack_policy: ackPolicy,
            deliver_policy: deliverPolicy
        })
    });
    showToast(`Consumer "${name}" created`);
    hideCreateConsumer();
    loadConsumers();
}

async function deleteConsumer(stream, name) {
    if (!confirm(`Delete consumer "${name}" from stream "${stream}"?`)) return;
    await api('/api/consumers/delete', {
        method: 'POST',
        body: JSON.stringify({ stream, name })
    });
    showToast(`Consumer "${name}" deleted`);
    loadConsumers();
}

// --- Publish ---
async function publishMessage() {
    const subject = document.getElementById('pub-subject').value.trim();
    const data = document.getElementById('pub-data').value.trim();
    const resultDiv = document.getElementById('pub-result');

    if (!subject) {
        showToast('Subject is required', 'error');
        return;
    }

    try {
        const res = await api('/api/publish', {
            method: 'POST',
            body: JSON.stringify({ subject, data })
        });
        resultDiv.className = 'result success';
        resultDiv.textContent = JSON.stringify(res, null, 2);
        showToast('Message published');
    } catch (e) {
        resultDiv.className = 'result error';
        resultDiv.textContent = e.message;
    }
}

// --- WebSocket Live Events ---
let ws = null;
let liveEventCount = 0;

function toggleWebSocket() {
    if (ws && ws.readyState === WebSocket.OPEN) {
        ws.close();
        return;
    }

    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    ws = new WebSocket(`${proto}//${location.host}/ws`);

    ws.onopen = () => {
        document.getElementById('ws-status').className = 'badge connected';
        document.getElementById('ws-status').textContent = 'connected';
        document.getElementById('ws-toggle').textContent = 'Disconnect';
        showToast('WebSocket connected');
    };

    ws.onmessage = (evt) => {
        const event = JSON.parse(evt.data);
        liveEventCount++;
        document.getElementById('live-count').textContent = `${liveEventCount} events`;

        const feed = document.getElementById('live-events');
        const div = document.createElement('div');
        div.className = 'live-event';
        div.innerHTML = `
            <span class="timestamp">${event.timestamp || new Date().toISOString()}</span>
            <span class="subject">${event.subject || 'unknown'}</span>
            <span class="data">${JSON.stringify(event)}</span>
        `;
        feed.insertBefore(div, feed.firstChild);

        // Keep max 200 events in DOM
        while (feed.children.length > 200) {
            feed.removeChild(feed.lastChild);
        }
    };

    ws.onclose = () => {
        document.getElementById('ws-status').className = 'badge disconnected';
        document.getElementById('ws-status').textContent = 'disconnected';
        document.getElementById('ws-toggle').textContent = 'Connect';
    };

    ws.onerror = () => {
        showToast('WebSocket error', 'error');
    };
}

function clearLiveEvents() {
    document.getElementById('live-events').innerHTML = '';
    liveEventCount = 0;
    document.getElementById('live-count').textContent = '0 events';
}

// --- Init ---
loadOverview();
setInterval(loadOverview, 10000);
