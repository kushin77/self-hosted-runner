"use strict";

// Simple in-memory job store for provisioner-worker used in local runs.
const store = new Map();

function get(id) {
  if (!id) return null;
  return store.get(String(id)) || null;
}

function set(idOrObj, obj) {
  if (typeof idOrObj === 'object' && idOrObj !== null && idOrObj.request_id) {
    store.set(String(idOrObj.request_id), idOrObj);
    return idOrObj;
  }
  if (typeof idOrObj === 'string' && obj) {
    store.set(String(idOrObj), obj);
    return obj;
  }
  return null;
}

function list() {
  return Array.from(store.values());
}

module.exports = { get, set, list };
