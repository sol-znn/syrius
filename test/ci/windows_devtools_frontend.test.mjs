import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {FrontendExchange, Refused, frontendAddress, frontendPageExpression, serviceKey} from '../../tool/ci/windows_devtools_frontend.mjs';

const service = 'ws://127.0.0.1:45123/fixture=/ws';
const frontend = `http://127.0.0.1:9100/?uri=${encodeURIComponent(service)}`;
const socket = 'private-network-request';
function exchange() {
  const value = new FrontendExchange(service, 1234);
  value.event('Network.webSocketCreated', {requestId: socket, url: service});
  return value;
}
function frame(value, method, message) {
  value.event(`Network.webSocketFrame${method}`, {requestId: socket,
    response: {opcode: 1, payloadData: JSON.stringify(message)}});
}

test('frontend address preserves exact private bytes and binds one original VM', () => {
  assert.equal(frontendAddress(frontend, service), frontend);
  assert.equal(serviceKey(service.replace('fixture=', 'fixture%3D')), serviceKey(service));
  for (const raw of [frontend.replace('45123', '45124'), frontend.replace('fixture', 'changed'),
    `${frontend}&uri=${encodeURIComponent(service)}`, frontend.replace('127.0.0.1', 'example.invalid')]) {
    assert.throws(() => frontendAddress(raw, service), Refused);
  }
});
test('remote aliases, credentials, malformed authentication and low ports are refused', () => {
  for (const raw of [service.replace('127.0.0.1', 'localhost'), service.replace('127.0.0.1', 'user@127.0.0.1'),
    service.replace('45123', '80'), service.replace('fixture=', '..'), `${service}?secret=value`]) {
    assert.throws(() => serviceKey(raw), Refused);
  }
});
test('availability and unsolicited VM data cannot prove a frontend attachment', () => {
  const value = exchange();
  frame(value, 'Received', {id: 'unrequested', result: {type: 'VM', pid: 1234}});
  assert.equal(value.public().frontendGetVmMatched, false);
});
test('only the correlated frontend getVM response with the original PID qualifies', () => {
  const value = exchange();
  frame(value, 'Sent', {jsonrpc: '2.0', id: 'original', method: 'getVM'});
  frame(value, 'Received', {jsonrpc: '2.0', id: 'original', result: {type: 'VM', pid: 1234}});
  assert.equal(value.public().frontendGetVmMatched, true);
  assert.equal(value.public().getVmRequests, 1);
  assert.equal(value.public().getVmReplies, 1);
  assert.equal(value.public().serviceSocketSeen, true);
  assert.doesNotMatch(JSON.stringify(value.public()), /private|127\.0|1234|fixture/);
});
test('another socket or PID does not complete the original request', () => {
  const value = exchange();
  frame(value, 'Sent', {id: 7, method: 'getVM'});
  value.event('Network.webSocketFrameReceived', {requestId: 'replacement',
    response: {opcode: 1, payloadData: JSON.stringify({id: 7, result: {type: 'VM', pid: 1234}})}});
  assert.equal(value.public().frontendGetVmMatched, false);
  assert.throws(() => frame(value, 'Received', {id: 7, result: {type: 'VM', pid: 1235}}), Refused);
});
test('replacement sockets, duplicate requests and closed original sockets refuse admission', () => {
  const value = exchange();
  assert.throws(() => value.event('Network.webSocketCreated', {requestId: 'replacement', url: service}), Refused);
  assert.throws(() => frame(value, 'Sent', {id: 7, method: 'getVM'}), Refused);
  const duplicate = exchange();
  frame(duplicate, 'Sent', {id: 7, method: 'getVM'});
  assert.throws(() => frame(duplicate, 'Sent', {id: 7, method: 'getVM'}), Refused);
  const closed = exchange();
  frame(closed, 'Sent', {id: 7, method: 'getVM'});
  closed.event('Network.webSocketClosed', {requestId: socket});
  assert.throws(() => frame(closed, 'Received', {id: 7, result: {type: 'VM', pid: 1234}}), Refused);
});
test('boolean request IDs and opaque errors cannot count as VM responses', () => {
  const value = exchange();
  assert.throws(() => frame(value, 'Sent', {id: true, method: 'getVM'}), Refused);
  const failed = exchange();
  frame(failed, 'Sent', {id: 8, method: 'getVM'});
  assert.throws(() => frame(failed, 'Received', {id: 8, error: {message: 'private diagnostic'}}), Refused);
  assert.equal(value.public().frontendGetVmMatched, false);
});
test('WebSocket control frames carry no application reply or attachment evidence', () => {
  const value = exchange();
  for (const opcode of [8, 9, 10]) {
    value.event('Network.webSocketFrameReceived', {requestId: socket,
      response: {opcode, payloadData: 'private-control-bytes'}});
  }
  assert.equal(value.public().frontendGetVmMatched, false);
  assert.equal(value.public().held, false);
  assert.equal(value.public().frontendSocketClosed, true);
});
test('unrelated sockets are counted without retaining their address or request identity', () => {
  const value = exchange();
  value.event('Network.webSocketCreated', {requestId: 'private-other', url: 'ws://127.0.0.1:45678/private-other/ws'});
  assert.equal(value.public().otherSockets, 1);
  assert.doesNotMatch(JSON.stringify(value.public()), /private|45678/);
  assert.equal(value.public().frontendGetVmMatched, false);
});
test('page identity binds the SDK origin while allowing its connected-app title', () => {
  const expression = frontendPageExpression(frontend);
  assert.doesNotMatch(expression, /fixture|45123/);
  const state = vm.runInNewContext(expression, {document: {readyState: 'complete', title: 'Connected application'},
    location: {origin: 'http://127.0.0.1:9100'}});
  assert.equal(state.ready, true);
  assert.equal(state.devtools, false);
  assert.equal(state.sourceMatched, true);
  for (const origin of ['http://127.0.0.1:9101', 'http://example.invalid:9100', 'https://127.0.0.1:9100']) {
    const changed = vm.runInNewContext(expression, {document: {readyState: 'complete', title: 'DevTools'}, location: {origin}});
    assert.equal(changed.sourceMatched, false);
  }
});
