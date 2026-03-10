from flask import Flask, request, jsonify
import subprocess
import os

app = Flask(__name__)

def run_script(path, args=None):
    cmd = [path]
    if args:
        cmd.extend(args)
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return proc.returncode, proc.stdout

@app.route('/', methods=['POST'])
def handler():
    payload = request.get_json(silent=True) or {}
    action = payload.get('action') or payload.get('message', {}).get('data')

    if isinstance(action, str) and action.startswith('ey'):  # base64 encoded maybe
        try:
            import base64
            decoded = base64.b64decode(action).decode('utf-8')
            import json
            j = json.loads(decoded)
            action = j.get('action', action)
        except Exception:
            pass

    if action == 'vault_sync':
        path = '/app/../vault/sync_gsm_to_vault.sh'
        code, out = run_script(path)
        return jsonify({'action': 'vault_sync', 'exit': code, 'output': out}), (200 if code == 0 else 500)
    elif action == 'cleanup_ephemeral':
        path = '/app/../cleanup/cleanup_ephemeral_runners.sh'
        # expect env PROJECT and ZONE to be set in runtime
        code, out = run_script(path)
        return jsonify({'action': 'cleanup_ephemeral', 'exit': code, 'output': out}), (200 if code == 0 else 500)
    else:
        return jsonify({'error': 'unknown action', 'received': payload}), 400

@app.route('/health', methods=['GET'])
def health():
    return 'OK', 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', '8080')))
