from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/v1/register', methods=['POST'])
def register():
    data = request.get_json() or {}
    instance_id = data.get('instance_id')
    if not instance_id:
        return jsonify({'error':'missing instance_id'}), 400
    # In a real implementation, validate client cert (mTLS) and store registration in DB
    return jsonify({'status':'registered','instance_id':instance_id}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
