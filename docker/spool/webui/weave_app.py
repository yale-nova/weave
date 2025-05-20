from flask import Flask, render_template_string

app = Flask(__name__)

@app.route('/')
def index():
    return render_template_string('''
    <h2>Spark Cluster Dashboard</h2>
    <ul>
      <li><a href="/master0/">Spark Master 0</a></li>
      <li><a href="/master1/">Spark Master 1</a></li>
      <li><a href="/worker-direct-1/">Direct Worker 1</a></li>
      <li><a href="/worker-sgx-1/">SGX Worker 1</a></li>
      <li><a href="/plot/">Plotting Dashboard</a></li>
    </ul>
    ''')
