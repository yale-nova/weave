import unittest
import subprocess
import time
import urllib.request
import os
import signal

class TestDummyHTTPServer(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.port = 8005
        cls.proc = subprocess.Popen(
            ["gramine-direct", "python", "scripts/dummy-web-server.py", str(cls.port)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        time.sleep(2)  # wait for server to start

    @classmethod
    def tearDownClass(cls):
        if cls.proc:
            os.kill(cls.proc.pid, signal.SIGTERM)
            cls.proc.wait()

    def test_server_response(self):
        url = f"http://127.0.0.1:{self.port}/index.html"
        with urllib.request.urlopen(url, timeout=5) as response:
            html = response.read().decode()
        self.assertIn("<h1>hi!</h1>", html)


