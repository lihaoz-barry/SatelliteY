# minimal_backend.py
# 最小化测试后端 - 在 Windows PC 上运行

from flask import Flask, request, jsonify
from datetime import datetime
import socket

app = Flask(__name__)

# 记录请求计数
request_count = 0

@app.route('/health', methods=['GET'])
def health():
    """健康检查端点"""
    return jsonify({
        'status': 'ok',
        'message': 'Backend is running',
        'timestamp': datetime.now().isoformat(),
        'hostname': socket.gethostname()
    })

@app.route('/execute/ai', methods=['POST'])
def execute_ai():
    """模拟 AI 执行端点 - 和你的 Comet TaskRunner 接口一致"""
    global request_count
    request_count += 1
    
    data = request.get_json() or {}
    instruction = data.get('instruction', '')
    
    print(f"[{datetime.now()}] Received instruction: {instruction}")
    
    return jsonify({
        'success': True,
        'task_id': f'test-{request_count}',
        'instruction_received': instruction,
        'message': f'Task queued successfully! This is request #{request_count}',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/status/<task_id>', methods=['GET'])
def get_status(task_id):
    """任务状态查询"""
    return jsonify({
        'task_id': task_id,
        'status': 'done',
        'result': 'Test task completed successfully',
        'timestamp': datetime.now().isoformat()
    })

if __name__ == '__main__':
    print("=" * 50)
    print("Minimal Test Backend")
    print("=" * 50)
    print(f"Hostname: {socket.gethostname()}")
    print(f"Starting server on 0.0.0.0:5000")
    print("")
    print("Endpoints:")
    print("  GET  /health      - Health check")
    print("  POST /execute/ai  - Execute AI task")
    print("  GET  /status/<id> - Get task status")
    print("")
    print("Waiting for requests from Raspberry Pi...")
    print("=" * 50)
    
    app.run(host='0.0.0.0', port=5000, debug=True)