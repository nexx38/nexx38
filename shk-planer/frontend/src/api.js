const BASE = '/api';

async function req(url, options = {}) {
  const res = await fetch(BASE + url, options);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

const json = (data) => ({
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(data),
});

const patch = (data) => ({
  method: 'PATCH',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(data),
});

export const api = {
  getTodos:       (date) => req(`/todos?date=${date}`),
  createTodo:     (data) => req('/todos', json(data)),
  updateTodo:     (id, data) => req(`/todos/${id}`, patch(data)),
  deleteTodo:     (id) => req(`/todos/${id}`, { method: 'DELETE' }),

  getTimeblocks:   (date) => req(`/timeblocks?date=${date}`),
  createTimeblock: (data) => req('/timeblocks', json(data)),
  updateTimeblock: (id, data) => req(`/timeblocks/${id}`, patch(data)),
  deleteTimeblock: (id) => req(`/timeblocks/${id}`, { method: 'DELETE' }),
};
