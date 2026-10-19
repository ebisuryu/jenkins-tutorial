import math

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get('/health')
    assert response.status_code == 200
    assert response.json() == {'status': 'ok', 'model_loaded': True}


def test_predict_defaults():
    response = client.post('/predict', json={})
    assert response.status_code == 200
    price = response.json()['price']
    assert math.isfinite(price)
    assert price == pytest.approx(157551.3761237591)


def test_predict_explicit_input():
    response = client.post('/predict', json={
        'MSSubClass': 60, 'MSZoning': 'RL', 'LotArea': 7844,
        'LotConfig': 'Inside', 'BldgType': '1Fam', 'OverallCond': 7,
        'YearBuilt': 1978, 'YearRemodAdd': 1978, 'Exterior1st': 'HdBoard',
        'BsmtFinSF2': 0, 'TotalBsmtSF': 672,
    })
    assert response.status_code == 200
    assert response.json()['price'] == pytest.approx(157551.3761237591)


@pytest.mark.parametrize('body', [{'LotArea': 'invalid'}, {'YearBuilt': None}])
def test_predict_rejects_invalid_input(body):
    assert client.post('/predict', json=body).status_code == 422
