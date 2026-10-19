"""Run inside the API container using: docker exec -i NAME python < this_file."""
import json
import math
import time
import urllib.error
import urllib.request


def check():
    with urllib.request.urlopen('http://127.0.0.1:30000/health', timeout=3) as response:
        assert json.load(response) == {'status': 'ok', 'model_loaded': True}
    request = urllib.request.Request(
        'http://127.0.0.1:30000/predict', data=b'{}',
        headers={'Content-Type': 'application/json'}, method='POST',
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        price = json.load(response)['price']
        assert math.isfinite(price) and abs(price - 157551.3761237591) < 0.01


for attempt in range(30):
    try:
        check()
        print('Smoke test passed: /health and /predict')
        break
    except (OSError, urllib.error.URLError, AssertionError, ValueError, KeyError):
        if attempt == 29:
            raise
        time.sleep(2)
