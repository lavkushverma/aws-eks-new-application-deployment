from flask import Flask, jsonify

app = Flask(__name__)

@app.get("/")
def index():
    return jsonify(
        application="AWS EKS Demo Application",
        status="running",
        message="Hello from a container running on Kubernetes!"
    )

@app.get("/health")
def health():
    return jsonify(status="healthy"), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
