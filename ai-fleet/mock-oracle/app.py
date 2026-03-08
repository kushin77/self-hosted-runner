from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/suggest', methods=['POST'])
def suggest():
    data = request.get_json() or {}
    # Very simple heuristic: if avg_latency > 200ms, suggest scale up
    latency = data.get('avg_latency', 0)
    if latency > 200:
        action = {'action':'scale_up','reason':'high_latency'}
    else:
        action = {'action':'none','reason':'healthy'}
    return jsonify(action), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9090)
