const app = document.getElementById('app');
const modalRoot = document.getElementById('modal-root');
const toastRoot = document.getElementById('toast-root');
const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ssrp_business';

let requestSeq = 0;
const pendingRequests = new Map();

const state = {
    visible: false,
    view: 'business',
    config: {
        title: 'SSRP Business',
        theme: {},
        businessTypes: []
    },
    dashboard: null,
    admin: null,
    selectedBusinessId: null,
    selectedAdminBusinessId: null,
    adminSearch: '',
    loading: false,
    modal: null
};

function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

function normalize(value) {
    return String(value ?? '').toLowerCase();
}

function applyTheme(theme = {}) {
    const root = document.documentElement;
    const keys = {
        Gold: '--gold',
        Blue: '--blue',
        Background: '--bg',
        Panel: '--panel',
        PanelSoft: '--panel-soft',
        Text: '--text',
        Muted: '--muted',
        Danger: '--danger',
        Success: '--success'
    };

    Object.entries(keys).forEach(([key, variable]) => {
        if (theme[key]) {
            root.style.setProperty(variable, theme[key]);
        }
    });
}

function api(action, payload = {}) {
    const requestId = `${Date.now()}-${++requestSeq}`;

    return new Promise((resolve) => {
        const timeout = setTimeout(() => {
            pendingRequests.delete(requestId);
            resolve({ ok: false, message: 'Request timed out.' });
        }, 12000);

        pendingRequests.set(requestId, { resolve, timeout });

        fetch(`https://${resourceName}/request`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({ requestId, action, payload })
        }).catch(() => {
            clearTimeout(timeout);
            pendingRequests.delete(requestId);
            resolve({ ok: false, message: 'NUI bridge unavailable.' });
        });
    });
}

function resolveRequest(requestId, response) {
    const pending = pendingRequests.get(requestId);
    if (!pending) {
        return;
    }

    clearTimeout(pending.timeout);
    pendingRequests.delete(requestId);
    pending.resolve(response || { ok: true });
}

function closeUi() {
    fetch(`https://${resourceName}/close`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: '{}'
    }).catch(() => {});
}

function toast(kind, message) {
    if (!message) {
        return;
    }

    const el = document.createElement('div');
    el.className = `toast ${escapeHtml(kind || 'info')}`;
    el.textContent = message;
    toastRoot.appendChild(el);

    setTimeout(() => {
        el.style.opacity = '0';
        el.style.transform = 'translateY(8px)';
    }, 3600);

    setTimeout(() => {
        el.remove();
    }, 4200);
}

async function runAction(action, payload = {}, refresh = true) {
    const response = await api(action, payload);
    if (response.message) {
        toast(response.ok ? 'success' : 'error', response.message);
    }

    if (response.ok && refresh) {
        await loadData(true);
    }

    return response;
}

function formatDate(value) {
    if (!value) {
        return '-';
    }

    if (typeof value === 'number') {
        return new Date(value * 1000).toLocaleString();
    }

    return String(value).replace('T', ' ').replace('.000Z', '');
}

function formatMinutes(value) {
    const minutes = Number(value || 0);
    if (minutes < 60) {
        return `${minutes}m`;
    }

    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return rest ? `${hours}h ${rest}m` : `${hours}h`;
}

function typeOptions(selected) {
    return (state.config.businessTypes || []).map((type) => {
        const value = escapeHtml(type);
        return `<option value="${value}" ${type === selected ? 'selected' : ''}>${value}</option>`;
    }).join('');
}

function getBusinessById(id) {
    const list = state.dashboard?.businesses || [];
    return list.find((business) => Number(business.id) === Number(id)) || list[0] || null;
}

function getAdminBusinessById(id) {
    const list = state.admin?.businesses || [];
    return list.find((business) => Number(business.id) === Number(id)) || list[0] || null;
}

async function loadData(silent = false) {
    if (!state.visible) {
        return;
    }

    state.loading = !silent;
    render();

    const action = state.view === 'admin' ? 'admin:getData' : 'business:getDashboard';
    const response = await api(action);

    state.loading = false;
    if (!response.ok) {
        toast('error', response.message || 'Unable to load data.');
        render();
        return;
    }

    if (state.view === 'admin') {
        state.admin = response.data;
        if (!getAdminBusinessById(state.selectedAdminBusinessId)) {
            state.selectedAdminBusinessId = state.admin.businesses?.[0]?.id || null;
        }
    } else {
        state.dashboard = response.data;
        const activeBusinessId = response.data?.activeShift?.businessId;
        if (activeBusinessId) {
            state.selectedBusinessId = activeBusinessId;
        } else if (!getBusinessById(state.selectedBusinessId)) {
            state.selectedBusinessId = state.dashboard.businesses?.[0]?.id || null;
        }
    }

    render();
}

function shell(content) {
    const admin = state.view === 'admin';
    const title = admin ? 'Business Administration' : 'Business Management';
    const subtitle = admin ? 'Director tools' : 'Owner and employee payroll';
    const search = admin ? `
        <input class="input search-input" value="${escapeHtml(state.adminSearch)}" data-admin-search placeholder="Search...">
        <button class="btn primary" data-action="open-create-business">+ Create</button>
    ` : '';

    return `
        <div class="app-shell staff-shell">
            <header class="app-header">
                <div class="window-title">
                    <span class="crest">SS</span>
                    <strong>${escapeHtml(title)}</strong>
                </div>
                <button class="btn icon" data-action="close-ui" title="Close">x</button>
            </header>

            <section class="staff-toolbar">
                <div class="staff-tabs">
                    <button class="staff-tab active">${admin ? 'Businesses' : 'Dashboard'}</button>
                    <button class="staff-tab">${admin ? 'Employees' : 'Payroll'}</button>
                    <button class="staff-tab">${admin ? 'Online Owners' : 'Shifts'}</button>
                </div>
                <div class="toolbar-actions">${search}</div>
            </section>

            <section class="content staff-stage">
                <div class="watermark">SSRP</div>
                <div class="stage-head">
                    <div>
                        <h1>${escapeHtml(title)}</h1>
                        <p>${escapeHtml(subtitle)}</p>
                    </div>
                </div>
                ${content}
            </section>
        </div>
    `;
}

function render() {
    if (!state.visible) {
        app.innerHTML = '';
        modalRoot.innerHTML = '';
        document.body.classList.remove('app-visible');
        return;
    }

    document.body.classList.add('app-visible');
    app.innerHTML = shell(state.view === 'admin' ? renderAdmin() : renderBusiness());
}

function renderBusiness() {
    if (state.loading || !state.dashboard) {
        return `<div class="empty">Loading business records...</div>`;
    }

    const businesses = state.dashboard.businesses || [];
    if (!businesses.length) {
        return `<div class="empty">No business payroll access found.</div>`;
    }

    const business = getBusinessById(state.selectedBusinessId);
    const activeShift = state.dashboard.activeShift;
    const onSelectedShift = activeShift && Number(activeShift.businessId) === Number(business.id);
    const lockedByOtherShift = activeShift && !onSelectedShift;
    const employeeCount = business.employees?.length || 0;
    const activeCount = business.activeEmployees?.length || 0;

    return `
        <div class="business-tabs">
            ${businesses.map((item) => `
                <button class="business-tab ${Number(item.id) === Number(business.id) ? 'active' : ''}" data-select-business="${item.id}">
                    <strong>${escapeHtml(item.name)}</strong>
                    <span>${escapeHtml(item.type)}</span>
                </button>
            `).join('')}
        </div>

        <section class="grid three">
            <div class="metric">
                <span>Business</span>
                <strong>${escapeHtml(business.name)}</strong>
                <em>${escapeHtml(business.type)}</em>
            </div>
            <div class="metric">
                <span>Owner</span>
                <strong>${escapeHtml(business.ownerDisplayName)}</strong>
                <em>${escapeHtml(business.ownerDiscordId)}</em>
            </div>
            <div class="metric">
                <span>Status</span>
                <strong>${onSelectedShift ? (activeShift.isAfk ? 'AFK' : 'On Shift') : 'Off Shift'}</strong>
                <em>${employeeCount} employees, ${activeCount} active</em>
            </div>
        </section>

        <section class="panel pad shift-card">
            <div>
                <h2>${escapeHtml(business.name)}</h2>
                <p>${business.isOwner ? 'Owner access' : escapeHtml(business.employeeTitle || 'Employee access')}</p>
            </div>
            <div class="row">
                <button class="btn blue" data-action="start-shift" ${activeShift ? 'disabled' : ''}>Start Shift</button>
                <button class="btn primary" data-action="end-shift" ${onSelectedShift ? '' : 'disabled'}>End Shift</button>
                ${lockedByOtherShift ? `<span class="badge red">Active elsewhere</span>` : ''}
                ${onSelectedShift && activeShift.isAfk ? `<span class="badge red">AFK pay paused</span>` : ''}
                ${onSelectedShift && !activeShift.isAfk ? `<span class="badge green">Pay eligible</span>` : ''}
            </div>
        </section>

        <section class="grid two">
            <div class="panel">
                <div class="panel-head">
                    <h2>Current Employees</h2>
                    <span class="badge blue">${employeeCount}</span>
                </div>
                ${renderEmployeesTable(business)}
            </div>

            <div class="panel">
                <div class="panel-head">
                    <h2>On Shift</h2>
                    <span class="badge green">${activeCount}</span>
                </div>
                ${renderActiveEmployees(business.activeEmployees || [])}
            </div>
        </section>

        ${business.isOwner ? renderOwnerTools(business) : ''}

        <section class="panel">
            <div class="panel-head">
                <h2>Shift History</h2>
                <span class="badge">${business.recentShifts?.length || 0}</span>
            </div>
            ${renderShiftHistory(business.recentShifts || [])}
        </section>
    `;
}

function renderEmployeesTable(business) {
    const employees = business.employees || [];
    if (!employees.length) {
        return `<div class="empty">No employees on payroll.</div>`;
    }

    return `
        <div class="table-wrap">
            <table>
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Discord ID</th>
                        <th>Title</th>
                        ${business.isOwner ? '<th>Actions</th>' : ''}
                    </tr>
                </thead>
                <tbody>
                    ${employees.map((employee) => `
                        <tr>
                            <td>${escapeHtml(employee.displayName)}</td>
                            <td>${escapeHtml(employee.discordId)}</td>
                            <td>
                                ${business.isOwner
                                    ? `<input class="input compact-input" data-title-input="${employee.id}" value="${escapeHtml(employee.title)}">`
                                    : escapeHtml(employee.title)}
                            </td>
                            ${business.isOwner ? `
                                <td>
                                    <button class="btn ghost" data-action="save-title" data-id="${employee.id}">Save</button>
                                    <button class="btn danger" data-action="remove-employee" data-id="${employee.id}">Remove</button>
                                </td>
                            ` : ''}
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
    `;
}

function renderActiveEmployees(activeEmployees) {
    if (!activeEmployees.length) {
        return `<div class="empty">Nobody is clocked in.</div>`;
    }

    return `
        <div class="mini-list">
            ${activeEmployees.map((shift) => `
                <div class="mini-item">
                    <div>
                        <strong>${escapeHtml(shift.displayName)}</strong>
                        <span>${escapeHtml(shift.businessType)}</span>
                    </div>
                    <span class="badge ${shift.isAfk ? 'red' : 'green'}">${shift.isAfk ? 'AFK' : 'Active'}</span>
                </div>
            `).join('')}
        </div>
    `;
}

function renderOwnerTools(business) {
    return `
        <section class="panel pad">
            <div class="panel-head clean">
                <h2>Owner Payroll Tools</h2>
            </div>
            <form class="field-grid owner-form" data-form="add-employee">
                <input type="hidden" name="businessId" value="${business.id}">
                <div class="field">
                    <label>Discord ID</label>
                    <input class="input" name="discordId" required>
                </div>
                <div class="field">
                    <label>Display Name</label>
                    <input class="input" name="displayName" required>
                </div>
                <div class="field">
                    <label>Role / Title</label>
                    <input class="input" name="title" value="Employee">
                </div>
                <div class="field submit-field">
                    <label>&nbsp;</label>
                    <button class="btn primary" type="submit">+ Add Employee</button>
                </div>
            </form>
        </section>
    `;
}

function renderShiftHistory(shifts) {
    if (!shifts.length) {
        return `<div class="empty">No shift history yet.</div>`;
    }

    return `
        <div class="table-wrap">
            <table>
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Started</th>
                        <th>Ended</th>
                        <th>Total</th>
                        <th>AFK</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                    ${shifts.map((shift) => `
                        <tr>
                            <td>${escapeHtml(shift.displayName)}</td>
                            <td>${formatDate(shift.shiftStart)}</td>
                            <td>${formatDate(shift.shiftEnd)}</td>
                            <td>${formatMinutes(shift.totalMinutes)}</td>
                            <td>${formatMinutes(shift.afkMinutes)}</td>
                            <td><span class="badge">${escapeHtml(shift.status)}</span></td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
    `;
}

function renderAdmin() {
    if (state.loading || !state.admin) {
        return `<div class="empty">Loading business administration...</div>`;
    }

    const query = normalize(state.adminSearch);
    const businesses = (state.admin.businesses || []).filter((business) => {
        const haystack = `${business.name} ${business.type} ${business.ownerDisplayName} ${business.ownerDiscordId} ${business.status}`;
        return normalize(haystack).includes(query);
    });
    const selected = getAdminBusinessById(state.selectedAdminBusinessId);

    return `
        <section class="admin-layout">
            <div class="panel admin-list">
                <div class="panel-head">
                    <h2>Businesses</h2>
                    <span class="badge blue">${businesses.length}</span>
                </div>
                <div class="list-stack">
                    ${businesses.length ? businesses.map((business) => renderBusinessListItem(business, selected)).join('') : '<div class="empty">No businesses match search.</div>'}
                </div>
            </div>

            <div class="panel admin-detail">
                ${selected ? renderAdminDetail(selected) : '<div class="empty">Select a business.</div>'}
            </div>
        </section>
    `;
}

function renderBusinessListItem(business, selected) {
    const active = selected && Number(selected.id) === Number(business.id);
    return `
        <button class="list-card ${active ? 'active' : ''}" data-select-admin-business="${business.id}">
            <div>
                <strong>${escapeHtml(business.name)}</strong>
                <p>${escapeHtml(business.type)} | Employees: ${business.employees?.length || 0} | Owner: ${escapeHtml(business.ownerDisplayName)}</p>
            </div>
            <span class="badge ${business.status === 'active' ? 'green' : 'red'}">${escapeHtml(business.status)}</span>
            <span class="chevron">&gt;</span>
        </button>
    `;
}

function renderAdminDetail(business) {
    return `
        <div class="panel-head">
            <div>
                <h2>${escapeHtml(business.name)}</h2>
                <span class="subtle">${escapeHtml(business.type)} | ${escapeHtml(business.ownerDisplayName)}</span>
            </div>
            <div class="row">
                <button class="btn ghost" data-action="open-edit-business" data-id="${business.id}">Edit</button>
                <button class="btn danger" data-action="archive-business" data-id="${business.id}" ${business.status === 'archived' ? 'disabled' : ''}>Archive</button>
            </div>
        </div>
        <div class="detail-body">
            <section class="grid three">
                <div class="metric">
                    <span>Owner Discord</span>
                    <strong>${escapeHtml(business.ownerDiscordId)}</strong>
                </div>
                <div class="metric">
                    <span>Employees</span>
                    <strong>${business.employees?.length || 0}</strong>
                </div>
                <div class="metric">
                    <span>On Shift</span>
                    <strong>${business.activeEmployees?.length || 0}</strong>
                </div>
            </section>

            <section class="panel inset-panel">
                <div class="panel-head">
                    <h3>Employees</h3>
                </div>
                ${renderEmployeesTable({ ...business, isOwner: false })}
            </section>

            <section class="panel inset-panel">
                <div class="panel-head">
                    <h3>Active Employees</h3>
                </div>
                ${renderActiveEmployees(business.activeEmployees || [])}
            </section>
        </div>
    `;
}

function renderCreateModal() {
    const mode = state.modal?.mode || 'online';
    const query = normalize(state.modal?.query || '');
    const onlinePlayers = (state.admin?.onlinePlayers || []).filter((player) => {
        const haystack = `${player.displayName} ${player.characterName} ${player.discordId} ${player.source}`;
        return normalize(haystack).includes(query);
    });

    modalRoot.innerHTML = `
        <div class="modal-backdrop">
            <div class="modal">
                <div class="modal-head">
                    <h2>Create Business</h2>
                    <button class="btn icon" data-modal-action="close-modal">x</button>
                </div>
                <form data-form="create-business">
                    <div class="modal-body stack">
                        <div class="field-grid">
                            <div class="field">
                                <label>Business Name</label>
                                <input class="input" name="name" required>
                            </div>
                            <div class="field">
                                <label>Business Type</label>
                                <select name="type" required>${typeOptions()}</select>
                            </div>
                        </div>

                        <div class="segmented">
                            <button type="button" class="${mode === 'online' ? 'active' : ''}" data-modal-action="set-create-mode" data-mode="online">Online Player</button>
                            <button type="button" class="${mode === 'offline' ? 'active' : ''}" data-modal-action="set-create-mode" data-mode="offline">Offline Member</button>
                        </div>

                        ${mode === 'online' ? renderOnlineOwnerPicker(onlinePlayers) : renderOfflineOwnerFields()}
                    </div>
                    <div class="modal-foot">
                        <button class="btn ghost" type="button" data-modal-action="close-modal">Cancel</button>
                        <button class="btn primary" type="submit">Confirm</button>
                    </div>
                </form>
            </div>
        </div>
    `;
}

function renderOnlineOwnerPicker(players) {
    return `
        <div class="field">
            <label>Online Player Search</label>
            <input class="input" value="${escapeHtml(state.modal?.query || '')}" data-online-search placeholder="Search name, ID, Discord...">
        </div>
        <div class="player-list">
            ${players.length ? players.map((player) => {
                const selected = Number(state.modal?.selectedOwnerSource) === Number(player.source);
                return `
                    <button type="button" class="player-option ${selected ? 'active' : ''}" data-modal-action="select-owner" data-source="${player.source}">
                        <strong>${escapeHtml(player.displayName)}</strong>
                        <span>${escapeHtml(player.characterName)} | ID ${player.source} | ${escapeHtml(player.discordId || 'no discord')}</span>
                    </button>
                `;
            }).join('') : '<div class="empty">No online players found.</div>'}
        </div>
    `;
}

function renderOfflineOwnerFields() {
    return `
        <div class="field-grid">
            <div class="field">
                <label>Discord ID</label>
                <input class="input" name="ownerDiscordId" required>
            </div>
            <div class="field">
                <label>Display Name</label>
                <input class="input" name="ownerDisplayName" required>
            </div>
        </div>
    `;
}

function renderEditModal(business) {
    modalRoot.innerHTML = `
        <div class="modal-backdrop">
            <div class="modal">
                <div class="modal-head">
                    <h2>Edit Business</h2>
                    <button class="btn icon" data-modal-action="close-modal">x</button>
                </div>
                <form data-form="edit-business">
                    <input type="hidden" name="businessId" value="${business.id}">
                    <div class="modal-body stack">
                        <div class="field-grid">
                            <div class="field">
                                <label>Business Name</label>
                                <input class="input" name="name" value="${escapeHtml(business.name)}" required>
                            </div>
                            <div class="field">
                                <label>Business Type</label>
                                <select name="type" required>${typeOptions(business.type)}</select>
                            </div>
                            <div class="field">
                                <label>Owner Discord ID</label>
                                <input class="input" name="ownerDiscordId" value="${escapeHtml(business.ownerDiscordId)}" required>
                            </div>
                            <div class="field">
                                <label>Owner Display Name</label>
                                <input class="input" name="ownerDisplayName" value="${escapeHtml(business.ownerDisplayName)}" required>
                            </div>
                            <div class="field">
                                <label>Status</label>
                                <select name="status">
                                    <option value="active" ${business.status === 'active' ? 'selected' : ''}>Active</option>
                                    <option value="archived" ${business.status === 'archived' ? 'selected' : ''}>Archived</option>
                                </select>
                            </div>
                        </div>
                    </div>
                    <div class="modal-foot">
                        <button class="btn ghost" type="button" data-modal-action="close-modal">Cancel</button>
                        <button class="btn primary" type="submit">Save</button>
                    </div>
                </form>
            </div>
        </div>
    `;
}

function formData(form) {
    return Object.fromEntries(new FormData(form).entries());
}

app.addEventListener('click', async (event) => {
    const actionButton = event.target.closest('[data-action]');
    if (actionButton) {
        const action = actionButton.dataset.action;

        if (action === 'close-ui') {
            closeUi();
            return;
        }

        if (action === 'start-shift') {
            const business = getBusinessById(state.selectedBusinessId);
            if (business) {
                await runAction('business:startShift', { businessId: business.id });
            }
            return;
        }

        if (action === 'end-shift') {
            await runAction('business:endShift');
            return;
        }

        if (action === 'remove-employee') {
            await runAction('business:removeEmployee', { employeeId: actionButton.dataset.id });
            return;
        }

        if (action === 'save-title') {
            const input = app.querySelector(`[data-title-input="${actionButton.dataset.id}"]`);
            await runAction('business:setEmployeeTitle', {
                employeeId: actionButton.dataset.id,
                title: input?.value || ''
            });
            return;
        }

        if (action === 'open-create-business') {
            state.modal = { type: 'create', mode: 'online', query: '', selectedOwnerSource: null };
            renderCreateModal();
            return;
        }

        if (action === 'open-edit-business') {
            const business = getAdminBusinessById(actionButton.dataset.id);
            if (business) {
                state.modal = { type: 'edit', businessId: business.id };
                renderEditModal(business);
            }
            return;
        }

        if (action === 'archive-business') {
            await runAction('admin:archiveBusiness', { businessId: actionButton.dataset.id });
            return;
        }
    }

    const businessSelector = event.target.closest('[data-select-business]');
    if (businessSelector) {
        state.selectedBusinessId = Number(businessSelector.dataset.selectBusiness);
        render();
        return;
    }

    const adminSelector = event.target.closest('[data-select-admin-business]');
    if (adminSelector) {
        state.selectedAdminBusinessId = Number(adminSelector.dataset.selectAdminBusiness);
        render();
    }
});

app.addEventListener('submit', async (event) => {
    const form = event.target.closest('form');
    if (!form) {
        return;
    }

    event.preventDefault();

    if (form.dataset.form === 'add-employee') {
        await runAction('business:addEmployee', formData(form));
        form.reset();
    }
});

app.addEventListener('input', (event) => {
    if (event.target.matches('[data-admin-search]')) {
        state.adminSearch = event.target.value;
        render();
        const input = app.querySelector('[data-admin-search]');
        if (input) {
            input.focus();
            input.setSelectionRange(state.adminSearch.length, state.adminSearch.length);
        }
    }
});

modalRoot.addEventListener('click', (event) => {
    const button = event.target.closest('[data-modal-action]');
    if (!button) {
        return;
    }

    const action = button.dataset.modalAction;
    if (action === 'close-modal') {
        state.modal = null;
        modalRoot.innerHTML = '';
        return;
    }

    if (action === 'set-create-mode') {
        state.modal.mode = button.dataset.mode;
        state.modal.selectedOwnerSource = null;
        renderCreateModal();
        return;
    }

    if (action === 'select-owner') {
        state.modal.selectedOwnerSource = Number(button.dataset.source);
        renderCreateModal();
    }
});

modalRoot.addEventListener('input', (event) => {
    if (event.target.matches('[data-online-search]')) {
        state.modal.query = event.target.value;
        renderCreateModal();
        const input = modalRoot.querySelector('[data-online-search]');
        if (input) {
            input.focus();
            input.setSelectionRange(state.modal.query.length, state.modal.query.length);
        }
    }
});

modalRoot.addEventListener('submit', async (event) => {
    const form = event.target.closest('form');
    if (!form) {
        return;
    }

    event.preventDefault();
    const data = formData(form);

    if (form.dataset.form === 'create-business') {
        data.assignmentMode = state.modal.mode;
        if (state.modal.mode === 'online') {
            if (!state.modal.selectedOwnerSource) {
                toast('error', 'Select an online owner.');
                return;
            }
            data.ownerSource = state.modal.selectedOwnerSource;
        }

        const response = await runAction('admin:createBusiness', data);
        if (response.ok) {
            state.modal = null;
            modalRoot.innerHTML = '';
        }
        return;
    }

    if (form.dataset.form === 'edit-business') {
        const response = await runAction('admin:updateBusiness', data);
        if (response.ok) {
            state.modal = null;
            modalRoot.innerHTML = '';
        }
    }
});

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && state.visible) {
        if (state.modal) {
            state.modal = null;
            modalRoot.innerHTML = '';
        } else {
            closeUi();
        }
    }
});

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.type === 'open') {
        state.visible = true;
        state.view = data.view || 'business';
        state.config = data.config || state.config;
        applyTheme(state.config.theme || {});
        render();
        loadData();
        return;
    }

    if (data.type === 'close') {
        state.visible = false;
        render();
        return;
    }

    if (data.type === 'response') {
        resolveRequest(data.requestId, data.response);
        return;
    }

    if (data.type === 'refresh') {
        loadData(true);
        return;
    }

    if (data.type === 'notify') {
        toast(data.kind, data.message);
        return;
    }

    if (data.type === 'shiftState' && state.visible) {
        loadData(true);
    }
});
